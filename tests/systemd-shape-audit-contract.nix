# Eval-contract check for the systemd-shape-audit module: every one of the
# ten bug classes must be FLAGGED on an offending host (each with its live
# incident history), and the audit must stay silent on a clean host. The
# negative legs in tests/negative/ neuter individual class detectors in the
# module — each must break this build, proving the classes are still armed.
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
      # Class 7 deliberately includes nixpkgs-generated units in scope, and
      # the floating unstable base set carries unbounded boot-blocking
      # oneshots (linger-users, logrotate-checkconf, post-boot, resolvconf —
      # the same units the SystemNix fleet floors via its house defaults).
      # A correct consumer either floors them (as here) or allowlists them;
      # when unstable grows a NEW unbounded oneshot this check goes red on
      # purpose — that is the audit surfacing a real base-set regression.
      systemd.services = {
        linger-users.serviceConfig.TimeoutStartSec = "5min";
        logrotate-checkconf.serviceConfig.TimeoutStartSec = "5min";
        post-boot.serviceConfig.TimeoutStartSec = "5min";
        resolvconf.serviceConfig.TimeoutStartSec = "5min";
      };
    }
  ];
  auditFailures = modules:
    map (a: a.message)
    (lib.filter
      (a: !a.assertion && lib.hasPrefix "systemd-shape-audit:" a.message)
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
        # class 1: oneshot + Restart=always (unloadable unit)
        systemd.services.shape-c1.serviceConfig = {
          Type = "oneshot";
          Restart = "always";
        };
        # class 2: matching timer + Restart != no (start-limit cascade)
        systemd.services.shape-c2.serviceConfig.Restart = "on-failure";
        systemd.timers.shape-c2 = {
          wantedBy = ["timers.target"];
          timerConfig.OnCalendar = "daily";
        };
        # class 5: script option nested inside serviceConfig (no ExecStart,
        # unit refuses to load — crm-backup class)
        systemd.services.shape-c5.serviceConfig.script = "echo garbage keys";
        # class 6: two units declaring the same RuntimeDirectory
        systemd.services.shape-c6a.serviceConfig.RuntimeDirectory = "shape-shared-rt";
        systemd.services.shape-c6b.serviceConfig.RuntimeDirectory = "shape-shared-rt";
        # class 7: boot-blocking oneshot with unbounded TimeoutStartSec
        systemd.services.shape-c7 = {
          wantedBy = ["multi-user.target"];
          serviceConfig.Type = "oneshot";
        };
        # class 8: OnFailure nested inside serviceConfig (never arms)
        systemd.services.shape-c8.serviceConfig.OnFailure = "notify-failure@%n.service";
        # class 9: [Service] key nested inside unitConfig (silently ignored)
        systemd.services.shape-c9.unitConfig.TimeoutStartSec = "10min";
        # class 10: is-active probe against a oneshot without RemainAfterExit
        systemd.services.shape-c10-target.serviceConfig.Type = "oneshot";
        systemd.services.shape-c10-probe.script = "systemctl is-active shape-c10-target.service";
        # class 3: path unit triggered by PathExists (re-fire loop)
        systemd.paths.shape-c3.pathConfig.PathExists = "/tmp/shape-c3";
        # class 4: literal $HOME in a USER unit Exec line
        systemd.user.services.shape-c4.serviceConfig.ExecStart = "/bin/app --config $HOME/.config/app";
      }
    ]
  );
  cleanFailures = auditFailures baseModules;
  flagged = fragment: builtins.any (m: lib.hasInfix fragment m) offenderFailures;
  expect = fragment:
    lib.throwIfNot (flagged fragment)
    "systemd-shape-audit contract: class marker missing from the failing assertions: '${fragment}' — a documented bug shape went undetected (got: ${lib.concatStringsSep " | " offenderFailures})";
  contract =
    lib.throwIfNot (cleanFailures == [])
    "systemd-shape-audit contract: false positives on a clean host: ${lib.concatStringsSep " | " cleanFailures}"
    (expect "Type=oneshot combined with an invalid Restart"
      (expect "timer-driven unit(s) with Restart != no"
        (expect "triggered by PathExists/PathExistsGlob"
          (expect "literal $HOME in Exec lines"
            (expect "nested inside serviceConfig"
              (expect "RuntimeDirectory declared by more than one unit"
                (expect "unbounded TimeoutStartSec"
                  (expect "OnFailure nested inside serviceConfig"
                    (expect "nested inside unitConfig"
                      (expect "probe(s) against Type=oneshot"
                        (builtins.toJSON {
                          flaggedClasses = 10;
                          clean = true;
                        })))))))))));
in
  pkgs.runCommand "systemd-shape-audit-contract" {
    inherit contract;
    passAsFile = ["contract"];
  } ''
    cp "$contractPath" $out
    echo "systemd-shape-audit-contract: 10 classes flagged, clean host silent" >&2
  ''
