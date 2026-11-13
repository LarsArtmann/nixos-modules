# Eval-contract check for the memory-watermark-audit module: the guard must
# FLAG a sub-50% MemoryHigh-under-MemoryMax system unit, must PASS coherent,
# percent, high-only, and max-only shapes, and must stay silent on a clean
# host. The negative legs in tests/negative/ neuter the module's threshold
# and strip the offender from this fixture — both must break the build.
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
      boot.loader.grub.devices = ["nodev"];
    }
  ];
  auditFailures = modules:
    map (a: a.message)
    (lib.filter
      (a: !a.assertion && lib.hasPrefix "memory-watermark-audit:" a.message)
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
        systemd.services.throttle-trap.serviceConfig = {
          MemoryHigh = "512M";
          MemoryMax = "2G";
        };
      }
    ]
  );
  coherentFailures = auditFailures (
    baseModules
    ++ [
      {
        systemd.services.honest-unit.serviceConfig = {
          MemoryHigh = "4G";
          MemoryMax = "5G";
        };
      }
    ]
  );
  percentFailures = auditFailures (
    baseModules
    ++ [
      {
        systemd.services.percent-unit.serviceConfig = {
          MemoryHigh = "10%";
          MemoryMax = "8G";
        };
      }
    ]
  );
  halfOnlyFailures = auditFailures (
    baseModules
    ++ [
      {
        systemd.services.high-only.serviceConfig.MemoryHigh = "4G";
      }
      {
        systemd.services.max-only.serviceConfig.MemoryMax = "16G";
      }
    ]
  );
  cleanFailures = auditFailures baseModules;
  contract =
    lib.throwIfNot (builtins.length offenderFailures == 1)
    "memory-watermark-audit contract: the guard must flag a sub-50% watermark under a byte MemoryMax (got ${toString (builtins.length offenderFailures)}) — the llama-chat silent-throttle shape"
    (lib.throwIfNot (coherentFailures == [])
      "memory-watermark-audit contract: a coherent 80%-style pair must pass: ${lib.concatStringsSep " | " coherentFailures}"
      (lib.throwIfNot (percentFailures == [])
        "memory-watermark-audit contract: percent watermarks resolve against total RAM and must pass: ${lib.concatStringsSep " | " percentFailures}"
        (lib.throwIfNot (halfOnlyFailures == [])
          "memory-watermark-audit contract: high-only and max-only units are visible, different failure modes and must pass: ${lib.concatStringsSep " | " halfOnlyFailures}"
          (lib.throwIfNot (cleanFailures == [])
            "memory-watermark-audit contract: false positive on a clean host: ${lib.concatStringsSep " | " cleanFailures}"
            (builtins.toJSON {
              flagged = builtins.length offenderFailures;
              coherentPasses = true;
              percentPasses = true;
              halfOnlyPasses = true;
              clean = true;
            })))));
in
  pkgs.runCommand "memory-watermark-audit-contract" {
    inherit contract;
    passAsFile = ["contract"];
  } ''
    cp "$contractPath" $out
    echo "memory-watermark-audit-contract: trap flagged, coherent/percent/half-only/clean silent" >&2
  ''
