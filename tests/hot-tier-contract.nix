# Eval-contract check for the hot-tier module: a fixture host with a journal
# and a caddy-logs mount must (a) evaluate fully (the fs-options guard and
# module assertions travel with it), and (b) render the exact wiring the
# incident history pinned: nofail + device-timeout mounts, after/wants (NOT
# requires) on every declared service, LogsDirectory neutralization + the
# `+`-chown ownership heal on the *Directory= service, and the shadow-dir
# tmpfiles rules. The VM legs (tests/hot-tier-journal.nix,
# tests/hot-tier-caddy.nix) prove the runtime side; this check makes every
# clause eval-observable so the fail-on-bug-shape legs in tests/negative/
# can mutate-and-prove it.
{
  lib,
  pkgs,
  module,
}: let
  eval = lib.nixosSystem {
    system = "x86_64-linux";
    modules = [
      module
      {
        services.hot-tier.enable = true;
        services.hot-tier.mounts = {
          journal = {
            device = "/dev/disk/by-label/hot";
            subvol = "journal";
            mountPoint = "/var/log/journal";
            tmpfilesMode = "02755";
            tmpfilesUser = "root";
            tmpfilesGroup = "systemd-journal";
            services.systemd-journald = {};
          };
          caddy-logs = {
            device = "/dev/disk/by-label/hot";
            subvol = "caddy-logs";
            mountPoint = "/var/log/caddy";
            tmpfilesMode = "0750";
            tmpfilesUser = "caddy";
            tmpfilesGroup = "caddy";
            services.caddy.dropLogsDirectory = true;
          };
        };
        # Upstream shape under test: nixpkgs caddy sets LogsDirectory, which
        # systemd turns into an implicit RequiresMountsFor that defeats
        # wants-not-requires. The stub stands in for the real caddy module
        # (the neutralization is unit-shape, not caddy-specific).
        systemd.services.caddy.serviceConfig.LogsDirectory = ["caddy"];
        users.users.caddy = {
          isSystemUser = true;
          group = "caddy";
        };
        users.groups.caddy = {};
        # Minimal bootable skeleton so the base module set's own assertions
        # pass; irrelevant to the contract under test.
        fileSystems."/" = {
          device = "/dev/vda1";
          fsType = "ext4";
        };
        boot.loader.grub.devices = ["nodev"];
      }
    ];
  };
  inherit (eval.config) systemd;
  # Evaluating config.assertions forces every module assertion here — a
  # violation throws with its own message, not at deploy time. (The earlier
  # variant forced system.build.toplevel.drvPath into the derivation env;
  # a .drv-path env value cannot be realized on a fresh store — the CI
  # first-run failure, run 43336330142.)
  failedAssertions =
    map (a: a.message)
    (lib.filter (a: !a.assertion) eval.config.assertions);
  journald = systemd.services.systemd-journald;
  caddy = systemd.services.caddy;
  pins =
    lib.throwIfNot (lib.elem "var-log-journal.mount" journald.after)
    "hot-tier contract: journald must be ordered after the journal mount (the Before=sysinit landmine)"
    (lib.throwIfNot (lib.elem "var-log-journal.mount" journald.wants)
      "hot-tier contract: journald must want (NOT require) the journal mount — a failed mount job degrades, never kills"
      (lib.throwIfNot (lib.elem "var-log-caddy.mount" caddy.after)
        "hot-tier contract: caddy must be ordered after the caddy-logs mount"
        (lib.throwIfNot (lib.elem "var-log-caddy.mount" caddy.wants)
          "hot-tier contract: caddy must want (NOT require) the caddy-logs mount"
          (lib.throwIfNot (caddy.serviceConfig.LogsDirectory == [])
            "hot-tier contract: dropLogsDirectory must neutralize the upstream LogsDirectory (implicit RequiresMountsFor class)"
            (lib.throwIfNot (caddy.serviceConfig.RequiresMountsFor or null == null)
              "hot-tier contract: the caddy unit must carry NO RequiresMountsFor on the mount (wants-not-requires)"
              (lib.throwIfNot (builtins.length (caddy.serviceConfig.ExecStartPre or []) == 1 && lib.hasPrefix "+" (builtins.head caddy.serviceConfig.ExecStartPre) && builtins.match ".*-caddy-logdir-own" (builtins.head caddy.serviceConfig.ExecStartPre) != null)
                "hot-tier contract: the `+`-privileged ownership-heal chown ExecStartPre must be present"
                (lib.throwIfNot (builtins.any (rule: lib.hasPrefix "d /var/log/journal 02755 root systemd-journal -" rule) eval.config.systemd.tmpfiles.rules)
                  "hot-tier contract: journal shadow-dir tmpfiles rule missing"
                  (lib.throwIfNot (builtins.any (rule: lib.hasPrefix "d /var/log/caddy 0750 caddy caddy -" rule) eval.config.systemd.tmpfiles.rules)
                    "hot-tier contract: caddy shadow-dir tmpfiles rule missing"
                    (lib.throwIfNot (eval.config.fileSystems."/var/log/journal".options == ["subvol=journal" "noatime" "nodiscard" "space_cache=v2" "nofail" "x-systemd.device-timeout=5s"])
                      "hot-tier contract: journal mount options must stay exactly the degradation contract (nofail + 5s timeout)"
                      (lib.throwIfNot (eval.config.fileSystems."/var/log/caddy".options == ["subvol=caddy-logs" "noatime" "nodiscard" "space_cache=v2" "nofail" "x-systemd.device-timeout=5s"])
                        "hot-tier contract: caddy-logs mount options must stay exactly the degradation contract"
                        (builtins.toJSON {
                          journaldOrdering = {
                            inherit (journald) after;
                            inherit (journald) wants;
                          };
                          caddyWiring = {
                            inherit (caddy) after;
                            inherit (caddy) wants;
                            LogsDirectory = caddy.serviceConfig.LogsDirectory;
                            ExecStartPre = caddy.serviceConfig.ExecStartPre or [];
                          };
                          journalOptions = eval.config.fileSystems."/var/log/journal".options;
                          caddyOptions = eval.config.fileSystems."/var/log/caddy".options;
                        })))))))))));
  contract =
    if failedAssertions != []
    then throw "hot-tier contract: module assertions failed:\n${lib.concatStringsSep "\n" failedAssertions}"
    else pins;
in
  pkgs.runCommand "hot-tier-contract" {
    inherit contract;
    passAsFile = ["contract"];
  } ''
    cp "$contractPath" $out
    echo "hot-tier-contract: fixture host evaluates; contract pinned" >&2
  ''
