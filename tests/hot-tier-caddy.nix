# VM test for the hot-tier caddy-logs mount (ported from SystemNix
# tests/test-caddy-logs-hot.nix; drives the collection module through its
# options — including the *Directory= neutralization + ownership heal, the
# VM-test-proven trap that distinguishes this family member).
#
# Verifies the two things eval CANNOT check:
#   1. HAPPY path (hot disk present): caddy's access-log writes land ON the
#      mounted subvolume (curl roundtrip + findmnt -T on the ACTIVE access
#      log + lsattr +C) — the ownership-heal ExecStartPre made the mounted
#      dir writable by caddy despite LogsDirectory being neutralized.
#   2. DEGRADED path (hot disk absent): the failed nofail mount must NOT
#      wedge the boot or kill caddy (wants, not requires — WITH the
#      *Directory= neutralization; an un-neutralized LogsDirectory turns
#      into an implicit RequiresMountsFor and caddy dies with result
#      'dependency') — caddy serves and logs into the shadow dir.
{pkgs}: let
  entry = {
    device = "/dev/disk/by-label/tlc";
    fsType = "btrfs";
    options = [
      "subvol=caddy-logs"
      "noatime"
      "nodiscard"
      "space_cache=v2"
      "nofail"
      "x-systemd.device-timeout=5s"
    ];
  };

  hotTierCaddyLogs = {
    services.hot-tier.enable = true;
    services.hot-tier.mounts.caddy-logs = {
      inherit (entry) device;
      subvol = "caddy-logs";
      mountPoint = "/var/log/caddy";
      tmpfilesMode = "0750";
      tmpfilesUser = "caddy";
      tmpfilesGroup = "caddy";
      services.caddy.dropLogsDirectory = true;
    };
  };

  # Minimal vHost writing a single access file — the mount is the system
  # under test, not the production logging map.
  caddyVm = {
    services.caddy = {
      enable = true;
      globalConfig = "auto_https off";
      virtualHosts."http://localhost" = {
        logFormat = "output file /var/log/caddy/access-localhost.log";
        extraConfig = "respond \"caddy-hot-ok\"";
      };
    };
    environment.systemPackages = [pkgs.curl];
  };

  # Test-only scaffolding (production: the consumer's migrate script creates
  # the subvol BEFORE the first deploy). Same DefaultDependencies=false
  # rationale as tests/hot-tier-journal.nix: with default deps the formatter
  # closes the cycle var-log-caddy.mount → tlc-fmt → sysinit → local-fs →
  # mount and systemd's cycle breaker hangs the guest SILENT.
  tlcFmt = {
    systemd.services.tlc-fmt = {
      description = "Format tlc disk + create caddy-logs subvolume (test-only)";
      unitConfig.DefaultDependencies = false;
      wantedBy = ["var-log-caddy.mount"];
      before = ["var-log-caddy.mount"];
      after = ["systemd-udev-trigger.service"];
      serviceConfig = {
        Type = "oneshot";
        User = "root";
      };
      path = [
        pkgs.btrfs-progs
        pkgs.e2fsprogs
        pkgs.util-linux
      ];
      script = ''
        if ! blkid /dev/vdb | grep -q 'LABEL="tlc"'; then
          mkfs.btrfs -f -L tlc /dev/vdb
        fi
        mkdir -p /tlc-top /var/log/caddy
        mount -t btrfs -o subvolid=5 /dev/vdb /tlc-top
        if ! btrfs subvolume show /tlc-top/caddy-logs >/dev/null 2>&1; then
          btrfs subvolume create /tlc-top/caddy-logs
        fi
        chattr +C /tlc-top/caddy-logs
        umount /tlc-top
      '';
    };
  };
in {
  name = "hot-tier-caddy";

  nodes.machine = {lib, ...}: {
    imports = [../modules/hot-tier hotTierCaddyLogs caddyVm tlcFmt];
    system.stateVersion = lib.mkDefault "26.11";
    boot.supportedFilesystems = ["btrfs"];
    virtualisation.emptyDiskImages = [512];
    virtualisation.fileSystems."/var/log/caddy" = entry;
  };

  nodes.degraded = {lib, ...}: {
    imports = [../modules/hot-tier hotTierCaddyLogs caddyVm];
    system.stateVersion = lib.mkDefault "26.11";
    # NO disk: the by-label device never appears — the mount fails after
    # the 5s device timeout and caddy must proceed degraded (shadow dir).
    virtualisation.fileSystems."/var/log/caddy" = entry;
  };

  testScript = ''
    machine.start()
    machine.wait_for_unit("multi-user.target")
    machine.wait_for_unit("caddy.service")
    machine.wait_for_open_port(80)

    # 1a: the mount came up and is the caddy-logs subvolume.
    fsroot = machine.succeed("findmnt -n -o FSROOT /var/log/caddy").strip()
    assert "caddy-logs" in fsroot, f"unexpected FSROOT on /var/log/caddy: {fsroot}"

    # 1b: nodatacow inherited on the subvol root.
    machine.succeed("lsattr -d /var/log/caddy | grep -q -- --C")

    # 1c: marker roundtrip — caddy accepted the mount and serves through it.
    out = machine.succeed("curl -sf http://localhost/")
    assert "caddy-hot-ok" in out, f"unexpected body: {out!r}"

    # 1d: THE anti-split proof — the ACTIVE access-log file physically lives
    # on the mount. A lost boot race (caddy opening the shadow dir first)
    # would leave the file on the root fs.
    machine.sleep(3)
    target = machine.succeed(
        "findmnt -T /var/log/caddy/access-localhost.log -n -o TARGET"
    ).strip()
    assert target == "/var/log/caddy", (
        f"active access log off-mount (TARGET={target})"
    )

    machine.shutdown()

    # 2: degraded — hot disk absent. The failed mount must not kill caddy
    # (wants, not requires; a regression to requires — or an un-neutralized
    # *Directory= implicit dependency — leaves caddy dead with result
    # 'dependency' and this wait_for_unit fails); logging falls to the
    # shadow dir.
    degraded.start()
    degraded.wait_for_unit("multi-user.target")
    degraded.wait_for_unit("caddy.service")
    degraded.wait_for_open_port(80)
    out = degraded.succeed("curl -sf http://localhost/")
    assert "caddy-hot-ok" in out, f"unexpected body: {out!r}"
    degraded.succeed("test -f /var/log/caddy/access-localhost.log")
    degraded.fail("mountpoint -q /var/log/caddy")
  '';
}
