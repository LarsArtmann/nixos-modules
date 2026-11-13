# Eval-contract check for the tmp-cleaner-audit module: the guard must FLAG
# an inline `rm` + `/tmp/*` glob unit script WITHOUT a systemd-private
# exclusion (the 12-day forgejo mirror-outage class), must PASS the same
# cleaner WITH the exclusion, and must stay silent on a clean host. The
# negative legs in tests/negative/ neuter the module's detection and strip
# the offender from this fixture — both must break the build.
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
      (a: !a.assertion && lib.hasPrefix "tmp-cleaner-audit:" a.message)
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
        systemd.services.evil-cleaner.script = ''
          for f in /tmp/*; do rm -rf "$f"; done
        '';
      }
    ]
  );
  exemptFailures = auditFailures (
    baseModules
    ++ [
      {
        systemd.services.exempt-cleaner.script = ''
          for f in /tmp/*; do case "$f" in *systemd-private-*) continue;; esac; rm -rf "$f"; done
        '';
      }
    ]
  );
  cleanFailures = auditFailures baseModules;
  contract =
    lib.throwIfNot (builtins.length offenderFailures == 1)
    "tmp-cleaner-audit contract: the guard must flag an inline /tmp/* rm sweeper without a systemd-private exclusion (got ${toString (builtins.length offenderFailures)}) — deleting PrivateTmp backing dirs kills every file creation in the unit's private /tmp (forgejo mirrors dead 12 days)"
    (lib.throwIfNot (exemptFailures == [])
      "tmp-cleaner-audit contract: the systemd-private exclusion form must pass: ${lib.concatStringsSep " | " exemptFailures}"
      (lib.throwIfNot (cleanFailures == [])
        "tmp-cleaner-audit contract: false positive on a clean host: ${lib.concatStringsSep " | " cleanFailures}"
        (builtins.toJSON {
          flagged = builtins.length offenderFailures;
          exemptPasses = true;
          clean = true;
        })));
in
  pkgs.runCommand "tmp-cleaner-audit-contract" {
    inherit contract;
    passAsFile = ["contract"];
  } ''
    cp "$contractPath" $out
    echo "tmp-cleaner-audit-contract: offender flagged, exempt + clean hosts silent" >&2
  ''
