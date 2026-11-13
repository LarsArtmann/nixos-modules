# Eval-contract check for the mount-gating-audit module: the guard must FLAG
# an ungated ReadWritePaths-under-/mnt/ unit, must PASS both sanctioned
# gating forms, must FLAG the dash-prefix-under-declared-mount class, and
# must stay silent on a clean host and behind allowUnits. The negative legs
# in tests/negative/ neuter the module's detections and strip the offender
# from this fixture — both must break the build.
{
  lib,
  pkgs,
  module,
}: let
  baseModules = [
    module
    {
      fileSystems."/" = {
        device = "/dev/vda1";
        fsType = "ext4";
      };
      fileSystems."/mnt/pool2" = {
        device = "/dev/vdb1";
        fsType = "ext4";
      };
      boot.loader.grub.devices = ["nodev"];
    }
  ];
  auditFailures = modules:
    map (a: a.message)
    (lib.filter
      (a: !a.assertion && lib.hasPrefix "mount-gating-audit:" a.message)
      (lib.nixosSystem {
        system = "x86_64-linux";
        inherit modules;
      })
      .config
      .assertions);
  offenderFailures = auditFailures (
    baseModules
    ++ [
      {
        systemd.services.ungated-writer.serviceConfig.ReadWritePaths = ["/mnt/pool/backups/cv"];
      }
    ]
  );
  rmfGatedFailures = auditFailures (
    baseModules
    ++ [
      {
        systemd.services.loud-writer = {
          serviceConfig.ReadWritePaths = ["/mnt/pool/backups/cv"];
          unitConfig.RequiresMountsFor = ["/mnt/pool"];
        };
      }
    ]
  );
  condGatedFailures = auditFailures (
    baseModules
    ++ [
      {
        systemd.services.skip-writer = {
          serviceConfig = {
            ReadWritePaths = ["/mnt/pool/backups/cv"];
            ConditionPathIsMountPoint = "/mnt/pool";
          };
        };
      }
    ]
  );
  dashFailures = auditFailures (
    baseModules
    ++ [
      {
        systemd.services.dash-writer.serviceConfig.ReadWritePaths = ["-/mnt/pool2/cache"];
      }
    ]
  );
  allowFailures = auditFailures (
    baseModules
    ++ [
      {
        services.mount-gating-audit.allowUnits = ["ungated-writer"];
        systemd.services.ungated-writer.serviceConfig.ReadWritePaths = ["/mnt/pool/backups/cv"];
      }
    ]
  );
  cleanFailures = auditFailures baseModules;
  contract =
    lib.throwIfNot (builtins.length offenderFailures == 1)
    "mount-gating-audit contract: the guard must flag an ungated ReadWritePaths-under-/mnt/ unit (got ${toString (builtins.length offenderFailures)}) — the 226/NAMESPACE + shadow-copy class"
    (lib.throwIfNot (rmfGatedFailures == [])
      "mount-gating-audit contract: RequiresMountsFor must pass: ${lib.concatStringsSep " | " rmfGatedFailures}"
      (lib.throwIfNot (condGatedFailures == [])
        "mount-gating-audit contract: ConditionPathIsMountPoint must pass: ${lib.concatStringsSep " | " condGatedFailures}"
        (lib.throwIfNot (builtins.length dashFailures == 1)
          "mount-gating-audit contract: the dash-under-declared-mount class must flag (got ${toString (builtins.length dashFailures)}) — ENODEV aborts the whole unit"
          (lib.throwIfNot (allowFailures == [])
            "mount-gating-audit contract: allowUnits must silence: ${lib.concatStringsSep " | " allowFailures}"
            (lib.throwIfNot (cleanFailures == [])
              "mount-gating-audit contract: false positive on a clean host: ${lib.concatStringsSep " | " cleanFailures}"
              (builtins.toJSON {
                flagged = builtins.length offenderFailures;
                rmfPasses = true;
                condPasses = true;
                dashFlagged = builtins.length dashFailures;
                allowSilences = true;
                clean = true;
              }))))));
in
  pkgs.runCommand "mount-gating-audit-contract" {
    inherit contract;
    passAsFile = ["contract"];
  } ''
    cp "$contractPath" $out
    echo "mount-gating-audit-contract: offender + dash flagged, gating forms + allow + clean silent" >&2
  ''
