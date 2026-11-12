# Hot-tier mounts — relocate always-churning log/data directories onto a
# dedicated fast disk as unsnapshotted, nodatacow subvolume mounts.
#
# PROBLEM: log writers pinned inside the OS-disk snapshot set (journald, web
# server access logs) both ride every IO storm on that disk AND pin every
# written byte into snapshots/backups forever — journal reads timing out
# during the very storm the journal was supposed to diagnose, multi-GB access
# logs pinned by snapshot windows long after deletion.
#
# SOLUTION: declare each hot directory as a mount of an unsnapshotted
# subvolume on the hot disk (create the subvolume + copy existing data
# BEFORE the first deploy carrying the mount — fstab cannot create
# subvolumes, and mounting an empty subvol over live data is a split brain;
# subvolume creation stays consumer-side). The family carries the three
# doctrines a plain fstab entry misses:
#
#   1. ORDERING: services that either start early (journald starts Before=
#      sysinit.target — BEFORE local-fs mounts) or read the mounted dir are
#      wired after + wants the mount unit. `wants` (NOT requires) survives a
#      failed mount job: with the hot disk detached the service degrades to
#      the shadow dir on the OS disk — the pre-migration behavior, never a
#      dead service. nofail + the 5s device-timeout default bound the
#      degraded boot (the default 90s timeout would stall every boot on a
#      dead disk for services ordered After= the mount).
#
#   2. *Directory= TRAP (VM-test-proven): systemd turns ANY *Directory= path
#      into an implicit RequiresMountsFor (Automatic Dependencies), which
#      DEFEATS wants-not-requires — with the disk detached the service dies
#      with result 'dependency' instead of degrading. dropLogsDirectory
#      neutralizes the upstream setting (mkForce []: no plain-priority lever
#      exists for shrinking an upstream list; the force targets the upstream
#      nixpkgs setting, never consumer config — a consumer mkForce still
#      wins at equal priority, later module order).
#
#   3. OWNERSHIP HEAL: with *Directory= gone, nothing chowns the mounted
#      dir after the mount lands — tmpfiles runs in early sysinit BEFORE
#      hot-tier mounts (it only ever fixes the shadow dir), and plain
#      ExecStartPre runs as the SERVICE USER (chown EPERMs). healOwnership
#      adds a `+`-prefixed ExecStartPre chown: full privileges at service
#      start, correctly ordered after the mount. The tmpfiles rule keeps
#      guaranteeing the SHADOW dir's existence for degraded boots.
#
# Fleet failure routing / health monitoring are consumer-side: import this
# module and layer them at the delegation site.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.hot-tier;
  inherit (lib) mkEnableOption mkIf mkMerge mkOption types;
  inherit (import ../../lib lib) mkFilesystem;

  # "/var/log/journal" -> "var-log-journal.mount" (systemd unit escape for
  # the plain-path mounts this module declares; the production instances have
  # no escapes-needing characters).
  mountUnit = mp: "${lib.replaceStrings ["/"] ["-"] (lib.removePrefix "/" mp)}.mount";

  serviceOptions = {
    dropLogsDirectory = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Neutralize the service's upstream LogsDirectory setting (mkForce
        []). Only for services whose upstream module sets a *Directory=
        under the mount point: systemd turns it into an implicit
        RequiresMountsFor that defeats the wants-not-requires degradation
        (a detached hot disk would kill the service instead of degrading
        it to the shadow dir).
      '';
    };
    healOwnership = mkOption {
      type = types.bool;
      default = true;
      description = ''
        With dropLogsDirectory, add a `+`-privileged ExecStartPre chown of
        the mount point to the tmpfiles user/group (full privileges at
        service start, ordered after the mount — the *Directory= machinery
        was doing this job; tmpfiles cannot, it runs before the mount
        lands).
      '';
    };
  };

  mountOptions = {
    device = mkOption {
      type = types.str;
      description = "Source device of the hot-tier mount (stable /dev/disk/by-* path preferred).";
    };
    subvol = mkOption {
      type = types.str;
      description = "BTRFS subvolume name on the hot disk (unsnapshotted + nodatacow — create with chattr +C BEFORE the first deploy carrying this mount).";
    };
    mountPoint = mkOption {
      type = types.str;
      description = "Mount path (the hot directory itself, e.g. /var/log/journal).";
    };
    fsType = mkOption {
      type = types.str;
      default = "btrfs";
      description = "Filesystem type of the hot-tier mount.";
    };
    mountOptions = mkOption {
      type = types.listOf types.str;
      default = [
        "noatime"
        "nodiscard"
        "space_cache=v2"
        "nofail"
        "x-systemd.device-timeout=5s"
      ];
      description = ''
        Mount options; subvol= is prepended automatically. Defaults encode
        the degradation contract: nofail + 5s device-timeout bound the
        detached-disk boot, everything else is BTRFS hot-tier hygiene.
      '';
    };
    tmpfilesMode = mkOption {
      type = types.str;
      default = "0755";
      description = "Mode of the tmpfiles rule guaranteeing the (shadow) mount-point dir exists.";
    };
    tmpfilesUser = mkOption {
      type = types.str;
      default = "root";
      description = "Owner of the tmpfiles rule (and of the ownership-heal chown).";
    };
    tmpfilesGroup = mkOption {
      type = types.str;
      default = "root";
      description = "Group of the tmpfiles rule (and of the ownership-heal chown).";
    };
    services = mkOption {
      type = types.attrsOf (types.submodule {options = serviceOptions;});
      default = {};
      description = ''
        Services reading/writing the mounted directory. Each gets
        after + wants the mount unit (wants, NOT requires — a failed mount
        job degrades the service to the shadow dir, never kills it).
      '';
    };
  };

  mounts = lib.attrValues cfg.mounts;
in {
  options.services.hot-tier = {
    enable = mkEnableOption "hot-tier mounts (unsnapshotted fast-disk subvolume mounts for always-churning directories)";
    mounts = mkOption {
      type = types.attrsOf (types.submodule {options = mountOptions;});
      default = {};
      description = "Hot-tier mount instances keyed by name.";
    };
  };

  # All dynamic structure lives INSIDE static top-level keys: config keys
  # computed from option values (fileSystems.${m.mountPoint}) at the
  # top level would force cfg.mounts during the module system's key
  # distribution — an infinite recursion (the dynamic-key-from-cfg trap).
  # Static keys + mkIf inside the value is the canonical shape.
  config = {
    fileSystems = mkIf cfg.enable (mkMerge (
      map (m: {
        ${m.mountPoint} = mkFilesystem {
          inherit (m) device fsType;
          options = ["subvol=${m.subvol}"] ++ m.mountOptions;
        };
      }) mounts
    ));

    # Existence guarantee for the (shadow) mount-point dir — tmpfiles runs
    # in sysinit; on a healthy boot the mount shadows it, on a degraded
    # boot the service falls back INTO it.
    systemd.tmpfiles.rules = mkIf cfg.enable (
      map
      (m: "d ${m.mountPoint} ${m.tmpfilesMode} ${m.tmpfilesUser} ${m.tmpfilesGroup} -")
      mounts
    );

    systemd.services = mkIf cfg.enable (mkMerge (
      lib.concatMap
      (m:
        lib.mapAttrsToList (svc: w: {
          ${svc} = {
            after = [(mountUnit m.mountPoint)];
            wants = [(mountUnit m.mountPoint)];
            serviceConfig =
              lib.optionalAttrs w.dropLogsDirectory {
                LogsDirectory = lib.mkForce [];
              }
              // lib.optionalAttrs (w.dropLogsDirectory && w.healOwnership) {
                # `+` prefix: full privileges, sandbox dropped (plain
                # ExecStartPre runs as the service user and chown EPERMs).
                ExecStartPre = [
                  "+${pkgs.writeShellScript "${svc}-logdir-own" "chown ${m.tmpfilesUser}:${m.tmpfilesGroup} ${m.mountPoint}"}"
                ];
              };
          };
        })
        m.services)
      mounts
    ));
  };
}
