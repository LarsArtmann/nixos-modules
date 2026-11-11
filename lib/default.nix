# Collection lib — the systemd hardening spine, extracted from SystemNix
# lib/default.nix (portable half). Everything here depends on nixpkgs lib
# ONLY. Fleet-bound helpers (mkOidcGate, mkDnsGate, ports registry, gatus
# helpers, rocm, filesystems, buildcache) stay SystemNix-side: see
# lib/README.md for the split contract and the kill path.
lib:
let
  harden = import ./systemd.nix { inherit lib; };
  inherit (import ./systemd/service-defaults.nix lib)
    serviceDefaults
    serviceDefaultsUser
    serviceOneshotDefaults
    serviceOneshotDefaultsUser
    onFailure
    onFailureP0
    ;
in
{
  inherit harden;
  hardenUser = args: harden (args // { mode = "user"; });
  inherit
    serviceDefaults
    serviceDefaultsUser
    serviceOneshotDefaults
    serviceOneshotDefaultsUser
    onFailure
    onFailureP0
    ;
  serviceTypes = import ./types.nix lib;

  # Release-verified port handoff for `+`-privileged ExecStartPre use (the
  # berth pattern; see ./port-guard.nix for the full contract).
  mkPortGuard = import ./port-guard.nix lib;

  mkStateDir =
    path: mode: user: group:
    "d ${path} ${mode} ${user} ${group} -";

  # mkPoolDirUnit: the ONLY sanctioned creator of a directory that lives
  # under a removable mount.
  #
  # Invariants baked in (do not relax at call sites):
  #   - root oneshot, RemainAfterExit, wantedBy multi-user — mkdir/chown/chmod
  #     are idempotent, so every boot/deploy re-runs safely
  #   - RequiresMountsFor AND ReadWritePaths target the MOUNT ROOT, never the
  #     leaf: on a fresh pool nothing creates the leaf before this unit's
  #     namespace is set up, and a ReadWritePaths entry under the mountpoint
  #     aborts with 226/NAMESPACE before the script can mkdir
  #   - NEVER replace with a tmpfiles rule: pre-mount creation lands on the
  #     root fs and shadows the pool copy
  #   - chown to a service user needs CAP_CHOWN (harden{}'s empty default
  #     bounding set strips it); CAP_FOWNER covers the follow-up chmod on the
  #     then-foreign-owned dir; CAP_DAC_OVERRIDE covers traversal. Owner
  #     omitted → dir stays root-owned, no caps needed.
  mkPoolDirUnit =
    {
      description,
      directory,
      owner ? null,
      group ? owner,
      mode ? "0755",
      mountRoot ? "/mnt/pool",
      memoryMax ? "128M",
    }:
    {
      inherit description;
      wantedBy = [ "multi-user.target" ];
      unitConfig.RequiresMountsFor = [ mountRoot ];
      serviceConfig = lib.mkMerge [
        {
          Type = "oneshot";
          User = "root";
          RemainAfterExit = true;
        }
        (harden (
          {
            # MemoryMax, not memoryMax: harden{}'s argument is capitalised and
            # a lowercase key is passed through to the unit verbatim, where
            # systemd rejects it as an unknown directive AND the intended
            # ceiling is silently replaced by harden's 512M default.
            MemoryMax = memoryMax;
            ReadWritePaths = [ mountRoot ];
          }
          // lib.optionalAttrs (owner != null) {
            CapabilityBoundingSet = "CAP_CHOWN CAP_FOWNER CAP_DAC_OVERRIDE";
          }
        ))
        (serviceOneshotDefaults { })
      ];
      script = lib.concatStringsSep "\n" (
        [ "mkdir -p ${directory}" ]
        ++ lib.optional (owner != null) "chown ${owner}:${group} ${directory}"
        ++ [ "chmod ${mode} ${directory}" ]
      );
    };

  # mkSqliteBackupUnit: the WAL-safe SQLite backup pair (service + timer) as
  # a unit generator. The canonical script is the SUPERSET:
  #   - clean skip when the database does not exist yet
  #   - crash-remnant healing: a run killed mid-.backup leaves a
  #     <prefix>*.sqlite-journal remnant whose sqlite "recovery" silently
  #     ROLLS BACK later copies of the sibling — drop BOTH loudly
  #   - online `.backup` via -readonly (a read-write root open of the live
  #     WAL database can create root-owned -shm/-wal sidecars)
  #   - quick_check on the TEMP copy, atomic rename only after it passes:
  #     a killed run can never leave a torn file that looks valid
  #   - age-based retention matching prefix + tmp + journal remnants
  #
  # Returns { services.<name>; timers.<name>; } for a caller-side
  # `systemd = mkSqliteBackupUnit { ... };`.
  #
  # Invariants baked in (do not relax at call sites):
  #   - RequiresMountsFor targets the backup directory: a detached mount
  #     fails the run as a clean dependency error, never 226/NAMESPACE
  #   - ReadWritePaths is exactly the backup directory
  #   - the timer is Persistent (missed runs while powered off catch up)
  mkSqliteBackupUnit =
    {
      pkgs,
      name,
      description,
      dbPath,
      backupDir,
      prefix,
      retentionDays,
      startAt,
      timestampFormat ? "%Y-%m-%d",
      serviceDeps ? [ ],
      timerAfter ? [ ],
      onFailureDeps ? [ ],
      startLimitBurst ? 5,
      startLimitIntervalSec ? 300,
      memoryMax ? "512M",
      # CapabilityBoundingSet for the single harden call — pass
      # "CAP_DAC_READ_SEARCH" when the DB sits behind a 0700 DynamicUser
      # StateDirectory. A SEPARATE harden{} in extraServiceConfig would
      # conflict on CapabilityBoundingSet (two plain strings cannot merge).
      caps ? "",
      extraServiceConfig ? [ ],
    }:
    {
      services.${name} = {
        inherit description;
        after = serviceDeps;
        wants = serviceDeps;
        unitConfig.RequiresMountsFor = [ backupDir ];
        onFailure = onFailureDeps;
        inherit startLimitBurst;
        inherit startLimitIntervalSec;
        serviceConfig = lib.mkMerge (
          [
            {
              Type = "oneshot";
              ExecStart = pkgs.writeShellScript name ''
                set -euo pipefail
                db="${dbPath}"
                if [ ! -f "$db" ]; then
                  echo "${name}: database $db does not exist yet — nothing to back up"
                  exit 0
                fi
                find ${backupDir} -name "${prefix}*.sqlite-journal" | while read -r j; do
                  echo "${name}: healing crash-interrupted backup remnant: $j (+ sibling)"
                  rm -f "$j" "''${j%-journal}"
                done
                timestamp=$(date +${timestampFormat})
                dst="${backupDir}/${prefix}$timestamp.sqlite"
                # mktemp'd sibling (a fixed .tmp name collides with stale
                # leftovers and cannot self-heal) — the trap plus the
                # ${prefix}*.sqlite* retention match keep any crash remnant
                # from lingering.
                tmp="$(mktemp "$dst.XXXXXX")"
                trap 'rm -f "$tmp"' EXIT
                ${lib.getExe pkgs.sqlite} -readonly "$db" ".backup '$tmp'"
                ${lib.getExe pkgs.sqlite} -readonly "$tmp" "PRAGMA quick_check;" | grep -qx ok
                mv "$tmp" "$dst"
                echo "${name}: wrote $dst"
                find ${backupDir} -name "${prefix}*.sqlite*" -mtime +${toString retentionDays} -delete
              '';
              ReadWritePaths = [ backupDir ];
            }
            (harden (
              {
                MemoryMax = memoryMax;
              }
              // lib.optionalAttrs (caps != "") {
                CapabilityBoundingSet = caps;
              }
            ))
            (serviceOneshotDefaults { })
          ]
          ++ extraServiceConfig
        );
      };
      timers.${name} = {
        description = "${description} (timer)";
        wantedBy = [ "timers.target" ];
        after = timerAfter;
        timerConfig = {
          Persistent = true;
        }
        // startAt;
      };
    };

  # mkMetricTextfileCollector: the fail-closed Prometheus textfile collector
  # pair (service + timer) as a unit generator. The wrapper owns the
  # ATOMICITY contract; the caller's script owns the METRICS:
  #   - caller script emits Prometheus lines on stdout (HELP/TYPE/values)
  #   - stdout lands in a mktemp sibling, chmod 644, atomic mv — node
  #     exporter never scrapes a half-written file, and the sticky 1777
  #     textfile dir's rename-over-foreign-owned rejection is handled by
  #     running as root with CAP_FOWNER when needed (caller's caps)
  #   - a non-zero body exit leaves the PREVIOUS file in place (no mv): the
  #     collector never publishes a torn or empty metric set
  #   - OMIT-ON-ERROR RULE (caller-side, load-bearing): when a source is
  #     unreadable, emit ONLY the scrape_errors gauge and still exit 0 —
  #     an omitted "active/up" metric fails the alert, a frozen green one
  #     phantom-greens it
  # Returns { services.<name>; timers.<name>; } for a caller-side
  # `systemd = mkMetricTextfileCollector { ... };`.
  mkMetricTextfileCollector =
    {
      pkgs,
      name,
      description,
      outFile,
      script,
      timerConfig,
      textfileDir ? dirOf outFile,
      timeoutStartSec ? "3min",
      memoryMax ? "128M",
      caps ? "",
      extraPath ? [ ],
      onFailureDeps ? [ ],
      startLimitBurst ? 5,
      startLimitIntervalSec ? 300,
    }:
    {
      services.${name} = {
        inherit description;
        inherit startLimitBurst;
        inherit startLimitIntervalSec;
        onFailure = onFailureDeps;
        path = [ pkgs.coreutils ] ++ extraPath;
        serviceConfig = lib.mkMerge [
          {
            Type = "oneshot";
            User = "root";
            TimeoutStartSec = timeoutStartSec;
          }
          (harden (
            {
              ReadWritePaths = [ textfileDir ];
              MemoryMax = memoryMax;
            }
            // lib.optionalAttrs (caps != "") {
              CapabilityBoundingSet = caps;
            }
          ))
          (serviceOneshotDefaults { })
        ];
        script = ''
          set -eu
          OUT="${outFile}"
          mkdir -p "${textfileDir}"
          TMP="$(mktemp "$OUT.XXXXXX")"
          chmod 644 "$TMP"
          trap 'rm -f "$TMP"' EXIT
          (
          ${script}
          ) > "$TMP"
          mv "$TMP" "$OUT"
        '';
      };
      timers.${name} = {
        description = "${description} (timer)";
        wantedBy = [ "timers.target" ];
        inherit timerConfig;
      };
    };

  # unitExecText: a unit's Exec* line texts + Environment entries as one
  # concatenated string — the shared scan surface of the port-registry and
  # gatus-coverage eval audits (identical scanner, zero drift: a new Exec
  # key or Environment form added here lands in BOTH audits at once).
  # " \n " separator keeps line-position info for error messages.
  unitExecText =
    svc:
    let
      scanKeys = [
        "ExecStart"
        "ExecStartPre"
        "ExecStartPost"
        "ExecStop"
        "ExecStopPost"
        "ExecReload"
        "ExecCondition"
      ];
      envToString =
        env:
        if builtins.isAttrs env then
          lib.mapAttrsToList (k: v: "${k}=${toString v}") env
        else
          map toString (lib.toList env);
    in
    lib.concatStringsSep " \n " (
      (map (
        k:
        if svc.serviceConfig ? ${k} then
          (lib.concatMapStringsSep " " toString (lib.toList svc.serviceConfig.${k}))
        else
          ""
      ) scanKeys)
      ++ (lib.optionals (svc.serviceConfig ? Environment) (envToString svc.serviceConfig.Environment))
    );

  # extractPortLiterals: port numbers from unit Exec/Environment text in the
  # three forms repos actually write them:
  #   host-form   127.0.0.1:8099 / localhost 25 / 0.0.0.0:53
  #   colon-form  <non-alnum>:<digits>   (listen=:8100, http://host:8080/x)
  #   flag-form   --port 8100 / --port=8100
  # Trailing boundary excludes letters so model-tag lookalikes
  # ("qwen3.6-moe:35b-a3b") never match; "--port=8100abc" is not a port
  # literal.
  # KNOWN LIMITATION: word:NNN tokens ("DELAY:300") are lexically
  # indistinguishable from host:port ("resend.com:587") and DO extract when
  # NNN is in the 2-65535 range; per-audit allowPorts is the sanctioned
  # escape.
  # Zero-padded groups ("10:00" timestamps → "00") are DROPPED before
  # toInt: a leading zero is never a port literal in this style, and
  # lib.toInt("00") dies on the octal/decimal ambiguity.
  extractPortLiterals =
    text:
    let
      portRegex = "((127\\.0\\.0\\.1|localhost|0\\.0\\.0\\.0)[: ]([0-9]{2,5})([^0-9]|$))|([^0-9]:([0-9]{2,5})([^0-9a-zA-Z]|$))|(--port[ =]([0-9]{2,5})([^0-9a-zA-Z]|$))";
      parts = builtins.split portRegex text;
      digitGroups = builtins.filter (g: builtins.isString g && builtins.match "[0-9]+" g != null) (
        lib.flatten (map (x: if builtins.isList x then x else [ ]) parts)
      );
      portCandidates = builtins.filter (g: builtins.match "0[0-9]+" g == null) digitGroups;
    in
    lib.unique (builtins.filter (p: p >= 2 && p <= 65535) (map lib.toInt portCandidates));

  mkSecretCheck =
    pkgs:
    {
      name,
      secretPath,
      message,
      extraCheck ? "",
    }:
    pkgs.writeShellApplication {
      name = "check-${name}";
      runtimeInputs = [ pkgs.coreutils ];
      text = ''
        secret_path="${secretPath}"
        if [ ! -s "$secret_path" ]; then
          echo "${message}" >&2
          exit 1
        fi
        ${extraCheck}
      '';
    };

  mkDesktopNotifyService =
    pkgs:
    {
      name,
      description,
      checkScript,
      runtimeInputs,
      user,
      uid,
      interval ? "5min",
      bootDelay ? "2min",
      hardenFn ? harden,
      extraHarden ? { },
      extraServiceConfig ? { },
    }:
    let
      script = pkgs.writeShellApplication {
        name = "${name}-check";
        inherit runtimeInputs;
        text = checkScript;
      };
    in
    {
      timer = {
        description = "Periodic ${description}";
        timerConfig = {
          OnBootSec = bootDelay;
          OnUnitActiveSec = interval;
          Persistent = true;
        };
        wantedBy = [ "timers.target" ];
      };

      service = {
        inherit description onFailure;
        serviceConfig = lib.mkMerge [
          {
            Type = "oneshot";
            User = user;
            Environment = [
              "DISPLAY=:0"
              "WAYLAND_DISPLAY=wayland-1"
              "XDG_RUNTIME_DIR=/run/user/${uid}"
            ];
            ExecStart = lib.getExe script;
            StandardOutput = "journal";
            StandardError = "journal";
          }
          (hardenFn (
            lib.mkMerge [
              {
                ProtectHome = false;
                NoNewPrivileges = false;
              }
              extraHarden
            ]
          ))
          extraServiceConfig
        ];
      };
    };

  # BFQ I/O priority tiers. Each helper returns a systemd serviceConfig
  # fragment — merge with `mkMerge` alongside `harden {}`.
  #
  # Tier philosophy: lower BE priority = higher I/O precedence. SSH (BE/1)
  # always gets I/O before builds (BE/7). Maintenance (idle) only runs when
  # nothing else needs I/O. This prevents build storms from freezing SSH
  # sessions.
  #
  # Usage: `serviceConfig = lib.mkMerge [ (harden {}) (ioTier.build) ];`
  ioTier = {
    # BE/1 — SSH and critical remote access. Highest priority below realtime.
    interactive = {
      IOSchedulingClass = "best-effort";
      IOSchedulingPriority = 1;
    };
    # BE/3 — Desktop session (compositor, shell, audio). Must stay responsive.
    desktop = {
      IOSchedulingClass = "best-effort";
      IOSchedulingPriority = 3;
    };
    # BE/4 — Default for unclassified services. Most services sit here implicitly.
    service = {
      IOSchedulingClass = "best-effort";
      IOSchedulingPriority = 4;
    };
    # BE/5 — Latency-sensitive databases needing consistent I/O without
    # starving interactive/desktop workloads.
    heavyDB = {
      IOSchedulingClass = "best-effort";
      IOSchedulingPriority = 5;
    };
    # BE/6 — Standard background daemons tolerating I/O latency.
    background = {
      IOSchedulingClass = "best-effort";
      IOSchedulingPriority = 6;
    };
    # BE/7 — Batch builds and CI. Lowest BE priority + CPU Nice=10.
    build = {
      IOSchedulingClass = "best-effort";
      IOSchedulingPriority = 7;
      Nice = 10;
    };
    # idle — Maintenance tasks using I/O only when nothing else needs it.
    # Pairs with CPU Nice=10.
    maintenance = {
      IOSchedulingClass = "idle";
      Nice = 10;
    };
  };

  # wrapWithMemoryLimit: creates a wrapper script that runs a command under a
  # systemd transient user scope with cgroup MemoryMax + I/O scheduling
  # limits. Prevents memory-hungry dev/test commands (cargo test, go test,
  # pnpm) from consuming all system RAM, AND prevents their I/O from
  # starving the desktop (BE/7 yields to desktop BE/3).
  #
  # I/O defaults match ioTier.build: best-effort priority 7 + Nice=10. This
  # is deliberate — NOT idle class, which would stall foreground builds
  # whenever any background I/O runs. BE/7 gives builds the lowest
  # best-effort priority while still making forward progress.
  #
  # Returns a writeShellApplication derivation. NOT for use inside Nix build
  # sandboxes (systemd-run is unavailable there). Use in devShells or
  # system/user packages.
  wrapWithMemoryLimit =
    pkgs:
    {
      name,
      maxMemory,
      command,
      extraArgs ? [ ],
      ioClass ? "best-effort",
      ioPriority ? 7,
      nice ? 10,
    }:
    pkgs.writeShellApplication {
      name = "${name}-memlimit";
      runtimeInputs = [ pkgs.systemd ];
      text = ''
        exec systemd-run \
          --user --collect --wait \
          --same-dir \
          --setenv="*" \
          -p MemoryMax=${maxMemory} \
          -p IOSchedulingClass=${ioClass} \
          -p IOSchedulingPriority=${toString ioPriority} \
          -p Nice=${toString nice} \
          -- ${command} ${lib.escapeShellArgs extraArgs} "$@"
      '';
    };
}
