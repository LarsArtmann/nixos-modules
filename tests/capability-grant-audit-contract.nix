# Eval-contract check for the capability-grant-audit module: the guard must
# FLAG a non-root unit whose CapabilityBoundingSet carries DAC-class caps
# that AmbientCapabilities never grants, must PASS the granted, root-run,
# and non-DAC shapes, must silence behind the allow option, and must stay
# silent on a clean host. The negative legs in tests/negative/ neuter the
# module's detection and strip the offender from this fixture — both must
# break the build.
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
      (a: !a.assertion && lib.hasPrefix "capability-grant-audit:" a.message)
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
        systemd.services.blind-reader = {
          serviceConfig = {
            User = "app";
            CapabilityBoundingSet = ["CAP_DAC_READ_SEARCH"];
          };
        };
      }
    ]
  );
  grantedFailures = auditFailures (
    baseModules
    ++ [
      {
        systemd.services.sighted-reader = {
          serviceConfig = {
            User = "app";
            CapabilityBoundingSet = ["CAP_DAC_READ_SEARCH"];
            AmbientCapabilities = ["CAP_DAC_READ_SEARCH"];
          };
        };
      }
    ]
  );
  rootFailures = auditFailures (
    baseModules
    ++ [
      {
        systemd.services.root-reader.serviceConfig.CapabilityBoundingSet = ["CAP_DAC_READ_SEARCH"];
      }
    ]
  );
  nonDacFailures = auditFailures (
    baseModules
    ++ [
      {
        systemd.services.net-prober = {
          serviceConfig = {
            User = "app";
            CapabilityBoundingSet = ["CAP_NET_RAW"];
          };
        };
      }
    ]
  );
  allowFailures = auditFailures (
    baseModules
    ++ [
      {
        services.capability-grant-audit.allow = ["blind-reader"];
        systemd.services.blind-reader = {
          serviceConfig = {
            User = "app";
            CapabilityBoundingSet = ["CAP_DAC_READ_SEARCH"];
          };
        };
      }
    ]
  );
  cleanFailures = auditFailures baseModules;
  contract =
    lib.throwIfNot (builtins.length offenderFailures == 1)
    "capability-grant-audit contract: the guard must flag ungranted DAC caps on a non-root unit (got ${toString (builtins.length offenderFailures)}) — the bounding set LIMITS, only ambient GRANTS"
    (lib.throwIfNot (grantedFailures == [])
      "capability-grant-audit contract: the granted form must pass: ${lib.concatStringsSep " | " grantedFailures}"
      (lib.throwIfNot (rootFailures == [])
        "capability-grant-audit contract: root-run units acquire bounding caps on their own and must pass: ${lib.concatStringsSep " | " rootFailures}"
        (lib.throwIfNot (nonDacFailures == [])
          "capability-grant-audit contract: non-DAC caps are out of scope and must pass: ${lib.concatStringsSep " | " nonDacFailures}"
          (lib.throwIfNot (allowFailures == [])
            "capability-grant-audit contract: allow must silence: ${lib.concatStringsSep " | " allowFailures}"
            (lib.throwIfNot (cleanFailures == [])
              "capability-grant-audit contract: false positive on a clean host: ${lib.concatStringsSep " | " cleanFailures}"
              (builtins.toJSON {
                flagged = builtins.length offenderFailures;
                grantedPasses = true;
                rootPasses = true;
                nonDacPasses = true;
                allowSilences = true;
                clean = true;
              }))))));
in
  pkgs.runCommand "capability-grant-audit-contract" {
    inherit contract;
    passAsFile = ["contract"];
  } ''
    cp "$contractPath" $out
    echo "capability-grant-audit-contract: ungranted DAC flagged, granted/root/non-DAC/allow/clean silent" >&2
  ''
