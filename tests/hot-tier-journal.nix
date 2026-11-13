# VM test for the hot-tier journal mount (ported from SystemNix
# tests/test-journal-hot.nix; drives the collection module through its
# options — production parity by value, not by import path).
#
# Verifies the two things eval CANNOT check:
#   1. HAPPY path (hot disk present): journald's boot-time writes land ON the
#      mounted subvolume — the after/wants wiring beats journald's
#      Before=sysinit.target early start. Proof: marker roundtrip PLUS
#      findmnt -T on the ACTIVE journal file resolving to the mount (a
#      shadow-dir split would leave the active file on the root fs).
#   2. DEGRADED path (hot disk absent): the failed nofail mount must NOT
#      wedge the boot or kill journald (wants, not requires) — logging stays
#      alive in the shadow dir.
#
# qemu-vm replaces the WHOLE fileSystems option (mkVMOverride) — the entry
# is re-declared under virtualisation.fileSystems with the production
# options; the journald after/wants wiring comes from the REAL module.
{pkgs}: let
  entry = {
    device = "/dev/disk/by-label/tlc";
    fsType = "btrfs";
    options = [
      "subvol=journal"
      "noatime"
      "nodiscard"
      "space_cache=v2"
      "nofail"
      "x-systemd.device-timeout=5s"
    ];
  };

  # Runner-race fix (2026-11-13, third flake of the class): the boot
  # transaction's DEVICE job is NOT gated by After=tlc-fmt — it queues
  # with the transaction and carries the mount's device-timeout (5s),
  # while the formatter took 9.1s wall on a loaded runner (device job
  # timed out at 16.6s, formatter finished at 22.1s). Healthy node only:
  # a 90s window; the degraded node keeps the 5s default (its fast-fail
  # story is pinned).
  entrySlow =
    entry
    // {
      options =
        map
        (o:
          if pkgs.lib.hasPrefix "x-systemd.device-timeout" o
          then "x-systemd.device-timeout=90s"
          else o)
        entry.options;
    };

  hotTierJournal = {
    services.hot-tier.enable = true;
    services.hot-tier.mounts.journal = {
      inherit (entry) device;
      subvol = "journal";
      mountPoint = "/var/log/journal";
      tmpfilesMode = "02755";
      tmpfilesUser = "root";
      tmpfilesGroup = "systemd-journal";
      services.systemd-journald = {};
    };
  };

  # Test-only scaffolding (production: the consumer's migrate script creates
  # the subvol BEFORE the first deploy — fstab cannot create subvolumes; the
  # production boot graph has NO pre-mount unit and NO cycle surface).
  # DefaultDependencies=false is LOAD-BEARING here: with default deps (After=
  # sysinit.target) the unit closes the cycle journald → var-log-journal.mount
  # → tlc-fmt → sysinit → local-fs → mount — systemd's cycle breaker deleted
  # a core boot job and the guest hung SILENT (first run). The explicit
  # udev-trigger anchor keeps /dev/vdb visible this early.
  tlcFmt = subvol: {
    systemd.services.tlc-fmt = {
      description = "Format tlc disk + create ${subvol} subvolume (test-only)";
      unitConfig.DefaultDependencies = false;
      wantedBy = ["var-log-journal.mount"];
      before = ["var-log-journal.mount"];
      after = ["systemd-udev-trigger.service"];
      serviceConfig = {
        Type = "oneshot";
        User = "root";
      };
      path = [
        pkgs.btrfs-progs
        pkgs.e2fsprogs
        pkgs.util-linux
      ]; # udevadm (settle + label wait) lives in the systemd package
      script = ''
        if ! blkid /dev/vdb | grep -q 'LABEL="tlc"'; then
          mkfs.btrfs -f -L tlc /dev/vdb
        fi
        mkdir -p /tlc-top /var/log/journal
        mount -t btrfs -o subvolid=5 /dev/vdb /tlc-top
        if ! btrfs subvolume show /tlc-top/${subvol} >/dev/null 2>&1; then
          btrfs subvolume create /tlc-top/${subvol}
        fi
        chattr +C /tlc-top/${subvol}
        umount /tlc-top
        # mkfs can finish before udev publishes the by-label symlink; the
        # mount unit's 5s device-timeout + nofail would then silently SKIP
        # the mount (the 2026-11-13 loaded-runner failure class — caddy's
        # VM proved it; this test shares the scaffolding). Guarantee the
        # label device exists before the mount starts ordering.
        udevadm settle
        for i in $(seq 1 20); do
          [ -e /dev/disk/by-label/tlc ] && break
          sleep 1
        done
      '';
    };
  };
in {
  name = "hot-tier-journal";

  nodes.machine = {lib, ...}: {
    imports = [../modules/hot-tier hotTierJournal (tlcFmt "journal")];
    system.stateVersion = lib.mkDefault "26.11";
    boot.supportedFilesystems = ["btrfs"];
    virtualisation.emptyDiskImages = [512];
    virtualisation.fileSystems."/var/log/journal" = entrySlow;
  };

  nodes.degraded = {lib, ...}: {
    imports = [../modules/hot-tier hotTierJournal];
    system.stateVersion = lib.mkDefault "26.11";
    # NO disk: the by-label device never appears — the mount fails after
    # the 5s device timeout and journald must proceed degraded.
    virtualisation.fileSystems."/var/log/journal" = entry;
  };

  testScript = ''
    machine.start()
    machine.wait_for_unit("multi-user.target")

    # 1a: the mount came up and is the journal subvolume. Wait for the mount
    # unit EXPLICITLY (journald is After+wants it, never requires — under
    # slow I/O the assert can otherwise race the settling btrfs mount; the
    # 2026-11-13 Ubuntu-26-runner caddy-test race is the same class).
    machine.wait_for_unit("var-log-journal.mount")
    fsroot = machine.succeed("findmnt -n -o FSROOT /var/log/journal").strip()
    assert "journal" in fsroot, f"unexpected FSROOT on /var/log/journal: {fsroot}"

    # 1b: nodatacow inherited on the subvol root (doctrine C — do NOT grep
    # /proc/mounts, btrfs >=6.x omits nodatacow).
    machine.succeed("lsattr -d /var/log/journal | grep -q -- --C")

    # 1c: marker roundtrip — journald accepted the entry and reads it back.
    machine.succeed("systemd-cat -t jhot-verify echo marker-jhot-ok")
    machine.sleep(3)
    machine.succeed("journalctl -t jhot-verify -b --no-pager | grep -q marker-jhot-ok")

    # 1d: THE anti-split proof — the ACTIVE journal file physically lives on
    # the mount. A lost boot race (journald opening the shadow dir first)
    # would leave the active file on the root fs.
    newest = machine.succeed("ls -t /var/log/journal/$(cat /etc/machine-id)/ | head -1").strip()
    target = machine.succeed(
        f"findmnt -T /var/log/journal/$(cat /etc/machine-id)/{newest} -n -o TARGET"
    ).strip()
    assert target == "/var/log/journal", (
        f"active journal file off-mount (TARGET={target})"
    )

    machine.shutdown()

    # 2: degraded — hot disk absent. The failed mount must not kill journald
    # (wants, not requires — a regression to requires leaves journald dead
    # and this section fails on wait_for_unit) nor wedge the boot.
    degraded.start()
    degraded.wait_for_unit("multi-user.target")
    degraded.wait_for_unit("systemd-journald.service")
    degraded.succeed("systemd-cat -t jhot-degraded echo marker-degraded-ok")
    degraded.sleep(3)
    degraded.succeed("journalctl -t jhot-degraded -b --no-pager | grep -q marker-degraded-ok")
    degraded.fail("mountpoint -q /var/log/journal")
  '';
}
