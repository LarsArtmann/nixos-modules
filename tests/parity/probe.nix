# tests/parity/probe.nix — semantic parity probe between this collection's
# lib and the SystemNix fork (both are `lib: {...}` functions over the SAME
# nixpkgs lib instance).
#
# WHY semantic, not byte diff: the forked files legitimately diverge in
# comments and formatting (and now in two SHIPPED bug fixes — the ledger in
# lib/README.md). The contract that matters is VALUE parity: every helper,
# called with identical inputs (including the same pkgs), must produce the
# same normalized result. Store paths and derivation identities are
# normalized away so nixpkgs-pin drift cannot fake a divergence.
#
# Skipped by design (documented, not forgotten): `serviceTypes` and `ports`
# return option constructors / surfaces carrying type-function payloads —
# not value-comparable; their behavior is covered by lib-eval contracts on
# both sides (SystemNix's own checks consume them fleet-wide).
{
  lib,
  pkgs,
  collectionLib,
  forkLib,
}: let
  isOverride = v: builtins.isAttrs v && v ? _type && v._type == "override";

  # Replace 32-char store-hash prefixes with <h> so script texts embedding
  # store paths compare across nixpkgs pins.
  stripHash = s:
    lib.concatStringsSep ""
    (map (x:
      if builtins.isList x
      then "<h>-"
      else x)
    (builtins.split "[0-9a-z]{32}-" s));

  norm = x:
    if isOverride x
    # mkOverride wrappers unwrap to content on both sides (priority drift is
    # a separate concern, deliberately out of scope).
    then norm x.content
    else if builtins.isFunction x
    then "<fn>"
    else if lib.isDerivation x
    then "{drv:${x.name or "?"}}"
    else if builtins.isAttrs x
    then lib.mapAttrs (_: norm) x
    else if builtins.isList x
    then map norm x
    else if builtins.isString x
    then stripHash x
    else x;

  eplCorpus = [
    "curl 127.0.0.1:8099"
    "listen=:8100"
    "--port 8100"
    "--port=8100"
    "proxy http://host:8080/x"
    "--port 080"
    "--port 65536"
    "resend.com:587"
    "ollama run qwen3.6-moe:35b-a3b"
    "smtp via localhost 25"
  ];

  # Each probe: name -> function lib -> comparable value. Called against
  # BOTH libs with identical arguments (including pkgs).
  probes = {
    harden-defaults = L: norm (L.harden {});
    harden-args = L:
      norm
      (L.harden {
        MemoryMax = "2G";
        ProtectHome = false;
        ReadWritePaths = ["/var/lib/x"];
        SomePassthrough = "kept";
      });
    harden-bare-bytes = L: norm (L.harden {MemoryMax = "5242880";});
    hardenUser = L: norm (L.hardenUser {});
    serviceDefaults = L: norm (L.serviceDefaults {});
    serviceDefaultsUser = L: norm (L.serviceDefaultsUser {});
    serviceOneshotDefaults = L: norm (L.serviceOneshotDefaults {});
    serviceOneshotDefaultsUser = L: norm (L.serviceOneshotDefaultsUser {});
    onFailure = L: norm L.onFailure;
    onFailureP0 = L: norm L.onFailureP0;
    mkStateDir = L: norm (L.mkStateDir "/var/lib/svc" "0750" "svc" "grp");
    ioTier = L: norm L.ioTier;
    extractPortLiterals = L: norm (map L.extractPortLiterals eplCorpus);
    unitExecText = L:
      norm
      (L.unitExecText {
        serviceConfig = {
          ExecStart = "run-thing --port 1234";
          ExecStartPre = "prep";
          Environment = ["A=1"];
        };
      });
    mkFilesystem-good = L:
      norm
      (L.mkFilesystem {
        device = "/dev/sda1";
        fsType = "btrfs";
        options = ["discard=async" "compress=zstd"];
      });
    mkFilesystem-contamination = L:
      norm
      (!(builtins.tryEval
        (L.mkFilesystem {
          device = "/dev/sda1";
          fsType = "ext4";
          options = ["discard=async"];
        }))
        .success);
    mkPoolDirUnit = L:
      norm
      (L.mkPoolDirUnit {
        description = "parity probe";
        directory = "/mnt/hot/parity";
        owner = "parity";
        group = "parity";
      });
    mkSqliteBackupUnit = L:
      norm
      (L.mkSqliteBackupUnit {
        inherit pkgs;
        name = "parity-db";
        description = "parity probe";
        dbPath = "/var/lib/parity/db.sqlite";
        backupDir = "/mnt/backup/parity";
        prefix = "parity-";
        retentionDays = 7;
        startAt = {OnCalendar = "daily";};
      });
    mkSecretCheck = L:
      norm
      (L.mkSecretCheck pkgs {
        name = "parity-secret";
        secretPath = "/run/secrets/parity";
        message = "parity secret missing";
        extraCheck = "true";
      });
    mkDesktopNotifyService = L:
      norm
      (L.mkDesktopNotifyService pkgs {
        name = "parity-notify";
        description = "parity probe";
        checkScript = "true";
        runtimeInputs = [pkgs.coreutils];
        user = "parity";
        uid = "1000";
      });
    wrapWithMemoryLimit = L:
      norm
      (L.wrapWithMemoryLimit pkgs {
        name = "parity-cmd";
        maxMemory = "1G";
        command = "parity";
        extraArgs = ["--flag"];
      });
    mkPortGuard = L:
      norm
      (L.mkPortGuard {
        inherit pkgs;
        name = "parity-guard";
        logTag = "parityguard";
        ownerUnits = ["parity-owner.service"];
      });
  };

  results =
    lib.mapAttrs
    (_name: probe: {
      collection = probe collectionLib;
      fork = probe forkLib;
    })
    probes;

  mismatches =
    lib.filterAttrs
    (_: r: builtins.toJSON r.collection != builtins.toJSON r.fork)
    results;
in
  if mismatches == {}
  then {
    ok = true;
    probes = builtins.attrNames probes;
  }
  else
    throw ''
      parity-diff: semantic drift between the collection lib and the SystemNix fork:
        ${
        lib.concatStringsSep "\n        " (
          lib.mapAttrsToList
          (name: r: "${name}:\n          collection: ${builtins.toJSON r.collection}\n          fork:         ${builtins.toJSON r.fork}")
          mismatches
        )
      }
      Absorb the change on the drifting side (or, if the drift is a shipped
      divergence, record it in lib/README.md's divergence ledger).''
