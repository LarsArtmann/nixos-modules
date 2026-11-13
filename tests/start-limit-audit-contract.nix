# Eval-contract check for the start-limit-audit module: the guard must FLAG
# a service carrying StartLimitBurst inside serviceConfig (the silently-
# ignored-directive class) and must stay silent on a clean host. The negative
# legs in tests/negative/ neuter the module's detection and strip the
# offender from this fixture — both must break the build.
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
  shapeFailures = modules:
    map (a: a.message)
    (lib.filter
      (a: !a.assertion && lib.hasPrefix "start-limit-audit:" a.message)
      (lib.nixosSystem {
        system = "x86_64-linux";
        inherit modules;
      })
      .config
      .assertions);
  offenderFailures = shapeFailures (
    baseModules
    ++ [
      {
        systemd.services.start-limit-offender.serviceConfig.StartLimitBurst = 5;
      }
    ]
  );
  cleanFailures = shapeFailures baseModules;
  contract =
    lib.throwIfNot (builtins.length offenderFailures == 1)
    "start-limit-audit contract: the guard must flag a StartLimitBurst-in-serviceConfig offender exactly once (got ${toString (builtins.length offenderFailures)}: ${lib.concatStringsSep " | " offenderFailures}) — systemd 261+ silently ignores it there and the service restarts infinitely"
    (lib.throwIfNot (cleanFailures == [])
      "start-limit-audit contract: false positive on a clean host: ${lib.concatStringsSep " | " cleanFailures}"
      (builtins.toJSON {
        flagged = builtins.length offenderFailures;
        clean = true;
      }));
in
  pkgs.runCommand "start-limit-audit-contract" {
    inherit contract;
    passAsFile = ["contract"];
  } ''
    cp "$contractPath" $out
    echo "start-limit-audit-contract: offender flagged, clean host silent" >&2
  ''
