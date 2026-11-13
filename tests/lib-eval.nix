# Pure-eval contracts for the collection lib (`lib/`). No VM, no NixOS
# eval: the lib is a plain function `import ./lib lib`, so these tests pin
# its behavior directly. Until now parity with SystemNix was proven at
# EXTRACTION time only — these checks re-prove the contracts as the fork
# evolves, and the `lib` negative-harness group mutates the guards to prove
# these tests bite.
{
  lib,
  pkgs,
  collectionLib,
}: let
  inherit (collectionLib) harden hardenUser serviceTypes mkFilesystem mkPortGuard mkPoolDirUnit mkSqliteBackupUnit mkMetricTextfileCollector unitExecText extractPortLiterals;

  # expect: returns null on success, the failure message otherwise. All
  # contracts below collect into `failures`; a non-empty list throws with
  # every message — those messages double as the negative-harness markers.
  expect = cond: msg:
    if cond
    then null
    else msg;

  # Force a mkMerge OUTSIDE the module system: route it through a trivial
  # evalModules option of type `anything`. KNOWN APPROXIMATION (documented
  # 2026-11-13, T3 of the SUPERB plan): `types.anything` merges like the
  # real option merge for the shapes pinned below (nested attrsets, lists,
  # priorities), but it is NOT the NixOS serviceConfig submodule merge —
  # option types, coercion and error loci differ. The contracts stay valid
  # because they pin RESULT VALUES, never merge mechanics; the true
  # serviceConfig merge is covered by the four module contract checks.
  mergeIt = expr:
    (
      lib.evalModules {
        modules = [
          {
            options.merged = lib.mkOption {type = lib.types.anything;};
            config.merged = expr;
          }
        ];
      }
    )
    .config
    .merged;

  # ── harden family ──
  lifecycleThrows = !(builtins.tryEval (harden {ExecStart = "/bin/false";})).success;
  lifecycleThrowsPre =
    !(builtins.tryEval (harden {
      ExecStartPre = "/bin/true";
      Restart = "always";
    })).success;
  h512 = (harden {MemoryMax = "512M";}).MemoryHigh.content;
  h256 = (harden {MemoryMax = "256M";}).MemoryHigh.content;
  h1g = (harden {MemoryMax = "1G";}).MemoryHigh.content;
  h2g = (harden {MemoryMax = "2G";}).MemoryHigh.content;
  explicitHigh =
    (harden {
      MemoryMax = "1G";
      MemoryHigh = "600M";
    }).MemoryHigh.content;
  unparsableHigh = (harden {MemoryMax = "80%";}).MemoryHigh.content;
  bareBytesHigh = (harden {MemoryMax = "5242880";}).MemoryHigh.content;
  userFrag = hardenUser {};
  overrideMax = harden {MemoryMax = lib.mkOverride 50 "1G";};
  overrideHighFromContent = overrideMax.MemoryHigh.content;
  lowerTrap = harden {memoryMax = "1G";};

  # ── extractPortLiterals ──
  epl = extractPortLiterals;

  # ── unitExecText ──
  scanSvc = {
    serviceConfig = {
      ExecStart = "/bin/start --flag";
      ExecStartPre = ["/bin/pre-a" "/bin/pre-b"];
      ExecStartPost = "/bin/post";
      ExecStop = "/bin/stop";
      ExecStopPost = "/bin/stop-post";
      ExecReload = "/bin/reload";
      ExecCondition = "/bin/cond";
      Environment = {METRIC_PORT = "9101";};
    };
  };
  scanText = unitExecText scanSvc;
  scanSvcListEnv = unitExecText {serviceConfig.Environment = ["A=1" "B=2"];};

  # ── generators ──
  poolNoOwner = mkPoolDirUnit {
    description = "pool dir no owner";
    directory = "/mnt/pool/data";
    mountRoot = "/mnt/pool";
  };
  poolOwner = mkPoolDirUnit {
    description = "pool dir owned";
    directory = "/mnt/pool/data";
    owner = "svc";
    group = "svcgrp";
    mountRoot = "/mnt/pool";
  };
  poolNoOwnerCfg = mergeIt poolNoOwner.serviceConfig;
  poolOwnerCfg = mergeIt poolOwner.serviceConfig;

  backup = mkSqliteBackupUnit {
    inherit pkgs;
    name = "testdb-backup";
    description = "test db backup";
    dbPath = "/var/lib/testdb/db.sqlite";
    backupDir = "/mnt/backup/testdb";
    prefix = "testdb-";
    retentionDays = 14;
    startAt = {OnCalendar = "daily";};
  };
  backupSvcCfg = mergeIt backup.services.testdb-backup.serviceConfig;

  collector = mkMetricTextfileCollector {
    inherit pkgs;
    name = "test-collector";
    description = "test collector";
    outFile = "/var/lib/node_exporter/test.prom";
    script = "echo 'metric 1'";
    timerConfig = {OnCalendar = "hourly";};
  };
  collectorSvcCfg = mergeIt collector.services.test-collector.serviceConfig;

  identityOpts = serviceTypes.systemdServiceIdentity {defaultUser = "svc";};

  # ── mkFilesystem ──
  badFs = mkFilesystem {
    device = "/dev/sda1";
    fsType = "ext4";
    options = ["discard=async"];
  };
  goodFs = mkFilesystem {
    device = "/dev/sda1";
    fsType = "btrfs";
    options = ["discard=async" "compress=zstd"];
    neededForBoot = true;
  };

  guardScript = mkPortGuard {
    inherit pkgs;
    name = "test-port-guard";
    logTag = "testguard";
    ownerUnits = ["owner-svc.service"];
  };

  contracts = [
    (expect lifecycleThrows "harden: lifecycle keys must throw (the oneshot+Restart=always crash-loop class)")
    (expect lifecycleThrowsPre "harden: lifecycle keys must throw on ExecStartPre+Restart (the oneshot+Restart=always crash-loop class)")
    (expect (h512 == "429496729") "harden: MemoryHigh must derive as 80% of MemoryMax bytes — 512M → 429496729 (the llama-chat 410M-watermark class)")
    (expect (h256 == "214748364") "harden: MemoryHigh 256M → 214748364")
    (expect (h1g == "858993459") "harden: MemoryHigh 1G → 858993459")
    (expect (h2g == "1717986918") "harden: MemoryHigh 2G → 1717986918")
    (expect (explicitHigh == "600M") "harden: explicit MemoryHigh must pass through verbatim")
    (expect (unparsableHigh == "80%") "harden: unparsable MemoryMax (percent form) must fall back to the 80% default, not throw")
    (expect (bareBytesHigh == "4194304") "harden: bare-byte MemoryMax must parse (5242880 → 4194304)")
    (expect (!(userFrag ? ProtectKernelTunables)) "hardenUser: system-only keys must be omitted (Home Manager rejects them)")
    (expect (!(userFrag ? ProtectControlGroups)) "hardenUser: system-only keys must be omitted")
    (expect (userFrag ? PrivateTmp) "hardenUser: shared sandbox keys must be kept")
    (expect ((harden {ProtectProc = "invisible";}) ? ProtectProc) "harden: unknown keys must pass through to the unit verbatim")
    (expect (lowerTrap.memoryMax == "1G" && lowerTrap.MemoryMax.content == "512M") "harden: the lowercase memoryMax trap must stay pinned — lowercase passes through verbatim while the real ceiling silently stays at the 512M default")
    (expect (overrideMax.MemoryMax.priority == 50) "harden: an override-shaped MemoryMax must be kept as-is (priority survives)")
    (expect (overrideHighFromContent == "858993459") "harden: MemoryHigh must derive from an override-shaped MemoryMax's CONTENT (1G → 858993459)")

    (expect (epl "curl 127.0.0.1:8099" == [8099]) "extractPortLiterals: host-form 127.0.0.1:8099 → [8099]")
    (expect (epl "smtp via localhost 25" == [25]) "extractPortLiterals: host-form 'localhost 25' → [25]")
    (expect (epl "bind 0.0.0.0:53" == [53]) "extractPortLiterals: host-form 0.0.0.0:53 → [53]")
    (expect (epl "listen=:8100" == [8100]) "extractPortLiterals: colon-form 'listen=:8100' → [8100]")
    (expect (epl "proxy http://host:8080/x" == [8080]) "extractPortLiterals: colon-form URL host:8080 → [8080]")
    (expect (epl "--port 8100" == [8100] && epl "--port=8100" == [8100]) "extractPortLiterals: flag-form --port and --port= → [8100]")
    (expect (epl "--port 080" == []) "extractPortLiterals: zero-padded groups must be DROPPED (leading zero is never a port literal)")
    (expect (epl "--port 65536" == []) "extractPortLiterals: out-of-range values must be filtered (2-65535)")
    (expect (epl "DELAY:300" == [300]) "extractPortLiterals: KNOWN limitation pinned — word:NNN tokens DO extract (resend.com:587 class); per-audit allowPorts is the sanctioned escape")
    (expect (epl "resend.com:587" == [587]) "extractPortLiterals: KNOWN limitation pinned — host-like word:port extracts")
    (expect (epl "ollama run qwen3.6-moe:35b-a3b" == []) "extractPortLiterals: model-tag lookalikes must NOT extract (trailing-letter boundary)")
    (expect (epl "a:8080 and b:8080" == [8080]) "extractPortLiterals: duplicates must collapse (unique)")

    (expect (builtins.all (k: lib.hasInfix k scanText) ["--flag" "/bin/pre-a" "/bin/pre-b" "/bin/post" "/bin/stop" "/bin/stop-post" "/bin/reload" "/bin/cond"]) "unitExecText: all 7 Exec keys (incl. list-form ExecStartPre) must land in the scan text")
    (expect (lib.hasInfix "METRIC_PORT=9101" scanText) "unitExecText: attrset Environment form must land in the scan text as k=v")
    (expect (lib.hasInfix "A=1" scanSvcListEnv && lib.hasInfix "B=2" scanSvcListEnv) "unitExecText: list Environment form must land in the scan text")

    (expect (poolNoOwner.unitConfig.RequiresMountsFor == ["/mnt/pool"]) "mkPoolDirUnit: RequiresMountsFor must target the MOUNT ROOT (the 226/NAMESPACE class)")
    (expect (poolNoOwnerCfg.Type == "oneshot" && poolNoOwnerCfg.RemainAfterExit == true && poolNoOwnerCfg.User == "root") "mkPoolDirUnit: root oneshot + RemainAfterExit shape")
    (expect (poolNoOwnerCfg.CapabilityBoundingSet == "") "mkPoolDirUnit: no owner → no caps (harden's empty default bounding set)")
    (expect (poolOwnerCfg.CapabilityBoundingSet == "CAP_CHOWN CAP_FOWNER CAP_DAC_OVERRIDE") "mkPoolDirUnit: owner → CAP_CHOWN/FOWNER/DAC_OVERRIDE (chown + chmod on foreign-owned dir)")
    (expect (poolOwnerCfg.MemoryMax == "128M" && poolOwnerCfg.ReadWritePaths == ["/mnt/pool"]) "mkPoolDirUnit: MemoryMax default + ReadWritePaths on the mount root")
    (expect (lib.hasInfix "chown svc:svcgrp /mnt/pool/data" poolOwner.script && !(lib.hasInfix "chown" poolNoOwner.script)) "mkPoolDirUnit: chown line exactly when owner is set")

    (expect (backup ? services.testdb-backup && backup ? timers.testdb-backup) "mkSqliteBackupUnit: must return the service+timer pair under the name")
    (expect (backup.services.testdb-backup.unitConfig.RequiresMountsFor == ["/mnt/backup/testdb"]) "mkSqliteBackupUnit: RequiresMountsFor must target the backup dir")
    (expect (backupSvcCfg.Type == "oneshot" && backupSvcCfg.ReadWritePaths == ["/mnt/backup/testdb"]) "mkSqliteBackupUnit: oneshot + ReadWritePaths exactly the backup dir")
    (expect (backup.timers.testdb-backup.timerConfig.Persistent == true && backup.timers.testdb-backup.timerConfig.OnCalendar == "daily") "mkSqliteBackupUnit: timer must be Persistent with the startAt calendar")
    (expect (lib.hasInfix "testdb-backup" (toString backupSvcCfg.ExecStart)) "mkSqliteBackupUnit: ExecStart must be the packaged script")

    (expect (collectorSvcCfg.User == "root" && collectorSvcCfg.TimeoutStartSec == "3min") "mkMetricTextfileCollector: root + timeout defaults")
    (expect (lib.hasInfix "mktemp" collector.services.test-collector.script && lib.hasInfix "chmod 644" collector.services.test-collector.script && lib.hasInfix "mv \"$TMP\" \"$OUT\"" collector.services.test-collector.script) "mkMetricTextfileCollector: mktemp/644/atomic-mv wrapper must be intact")
    (expect (collector.timers.test-collector.wantedBy == ["timers.target"] && collector.timers.test-collector.timerConfig.OnCalendar == "hourly") "mkMetricTextfileCollector: timer shape")

    (expect (identityOpts.user._type == "option" && identityOpts.user.default == "svc" && identityOpts.user.type == lib.types.str) "serviceTypes: systemdServiceIdentity.user must be a str option defaulting to the identity user")
    (expect (identityOpts.group.default == "svc" && identityOpts.stateDir.default == "/var/lib/svc") "serviceTypes: group + stateDir defaults must derive from defaultUser")
    (expect ((serviceTypes.servicePort 8080 "p")._type == "option") "serviceTypes: servicePort must be an option")
    (expect ((serviceTypes.servicePort 8080 "p").type == lib.types.port) "serviceTypes: servicePort type must equal lib.types.port (got ${(serviceTypes.servicePort 8080 "p").type.name})")
    (expect ((serviceTypes.servicePort 8080 "p").default == 8080) "serviceTypes: servicePort default must pass through")
    (expect ((serviceTypes.restartDelay "5s").type == lib.types.str && (serviceTypes.stopTimeout "30s").type == lib.types.str) "serviceTypes: restartDelay/stopTimeout must be str options")

    (expect (!(builtins.tryEval badFs).success) "mkFilesystem: the contamination guard must throw on cross-filesystem options (discard=async on ext4)")
    (expect (goodFs.options == ["discard=async" "compress=zstd"] && goodFs.neededForBoot == true) "mkFilesystem: legal fs options and extra fileSystems attrs must round-trip (the …-pattern silent-drop class)")
  ];

  failures = builtins.filter (x: x != null) contracts;

  emptyOwnerGuardThrows =
    !(builtins.tryEval (mkPortGuard {
      inherit pkgs;
      name = "x";
      logTag = "x";
      ownerUnits = [];
    })).success;
in
  pkgs.runCommand "lib-eval" {
    contract =
      if failures != []
      then throw "lib-eval contracts failed:\n${lib.concatStringsSep "\n" failures}"
      else if !emptyOwnerGuardThrows
      then throw "lib-eval contracts failed:\nmkPortGuard: empty ownerUnits must throw (an unnamed owner spares every listener)"
      else
        builtins.toJSON {
          ok = true;
          contracts = builtins.length contracts;
        };
    inherit guardScript;
    passAsFile = ["contract"];
  } ''
    cp "$contractPath" $out
    grep -q "owner-svc.service" "$guardScript" || {
      echo "lib-eval contracts failed: mkPortGuard: the owner-unit pattern must appear in the generated script (spare logic)" >&2
      exit 1
    }
    echo "lib-eval: ${toString (builtins.length contracts)} lib contracts pinned + port-guard owner pattern verified" >&2
  ''
