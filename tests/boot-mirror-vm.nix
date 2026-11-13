# Runtime VM leg for boot-mirror (SUPERB T12): the sync script's
# bootctl/rsync/diff path has never executed inside this repo's test net —
# the eval contract pins the unit SHAPE, this test proves the BEHAVIORS:
#
#   1. full sync: bootctl installs on the mirror, rsync copies the loader
#      tree, the diff -r gate passes (unit success = tree-identical).
#   2. reverse-propagation: a loader-side boot-count rename on the source
#      is matched to the mirror's counter BEFORE the forward copy (the
#      counters-survive-the-mirror contract), and a blessed entry drops its
#      stale counting twin.
#   3. degradation: with the mirror's fs zeroed (disk attached,
#      filesystem unreadable), the sync's start job dies on its
#      RequiresMountsFor dependency (the mount carries exit-code; the
#      script never runs, no partial copy) — a detached mirror degrades
#      boot nothing (multi-user was reached with the mirror absent).
#   4. loud failure: a read-only mirror fails the unit (partial copy must
#      never be called a success — the diff-gate posture).
#
# Test-only scaffolding (production: the real ESP carries loader/entries and
# the consumer formats the mirror ESP at install time): a scaffold unit
# formats vdb as vfat after boot and seeds the loader tree the production
# builder would own. The VM machinery REPLACES config.fileSystems with
# virtualisation.fileSystems (qemu-vm.nix mkVMOverride), so the mirror
# mount is declared the VM way with the module's exact default options:
# nofail makes the pre-format boot mount fail soft, the test mounts by hand.
_: {
  name = "boot-mirror";

  nodes.machine = {
    lib,
    pkgs,
    ...
  }: let
    entryStem = "nixos-vmtest";
  in {
    imports = [../modules/boot-mirror];

    system.stateVersion = lib.mkDefault "26.11";

    # 2nd disk = the mirror ESP (raw /dev/vdb: a test cannot know a by-uuid
    # path at eval time; the option accepts any device string).
    virtualisation.emptyDiskImages = [64];

    # VM-way mirror mount (see header): the module's own
    # fileSystems."/boot-mirror" definition is discarded wholesale by the
    # VM's mkVMOverride, so declare the SAME shape here — or the module's
    # nofail self-assertion evals against a missing attribute.
    virtualisation.fileSystems."/boot-mirror" = {
      device = "/dev/vdb1";
      fsType = "vfat";
      # Module-default options + a fixture-only short device-timeout: the
      # partition exists only AFTER the scaffold runs, so the boot-time
      # mount must give up in 1s (nofail soft-fail), not stall 90s.
      options = ["fmask=0077" "dmask=0077" "nofail" "x-systemd.device-timeout=1s"];
    };

    services.boot-mirror = {
      enable = true;
      device = "/dev/vdb1";
    };

    # Format the mirror ESP + seed a loader-shaped /boot tree. Runs after
    # multi-user: the boot-time mount of blank vdb has already failed soft
    # (nofail), and early path-triggered syncs dependency-fail harmlessly.
    systemd.services.boot-mirror-scaffold = {
      description = "Format mirror ESP + seed loader tree (test-only)";
      wantedBy = ["multi-user.target"];
      after = ["multi-user.target" "systemd-udev-settle.service"];
      serviceConfig = {
        Type = "oneshot";
        # wait_for_unit below must observe an active unit.
        RemainAfterExit = true;
      };
      path = [pkgs.dosfstools pkgs.e2fsprogs pkgs.util-linux];
      script = ''
        # One ESP-typed GPT partition (bootctl refuses a filesystem on a
        # raw, unpartitioned device): this stands in for the consumer's
        # install-time partitioning, then formats the ESP.
        if [ ! -b /dev/vdb1 ]; then
          printf 'label: gpt\ntype=C12A7328-F81F-11D2-BA4B-00A0C93EC93B\n' \
            | sfdisk --wipe always /dev/vdb
        fi
        udevadm settle
        for i in $(seq 1 20); do [ -b /dev/vdb1 ] && break; sleep 1; done
        if ! blkid /dev/vdb1 | grep -q 'TYPE="vfat"'; then
          mkfs.vfat -n MIRRORESP /dev/vdb1
        fi
        udevadm settle
        mkdir -p /boot/loader/entries
        printf 'timeout 3\n' > /boot/loader/loader.conf
        printf 'title NixOS VM test\nlinux /nixos-kernel\ninitrd /nixos-initrd\n' \
          > "/boot/loader/entries/${entryStem}+2-1.conf"
        printf 'FAKE KERNEL\n' > /boot/nixos-kernel
        printf 'FAKE INITRD\n' > /boot/nixos-initrd
      '';
    };

    environment.systemPackages = [pkgs.rsync pkgs.diffutils pkgs.dosfstools pkgs.util-linux];
  };

  testScript = ''
    machine.start()
    machine.wait_for_unit("multi-user.target")
    machine.wait_for_unit("boot-mirror-scaffold.service")

    # 1. Full sync: mount the formatted mirror THROUGH the mount unit
    # (never `mount` by hand: the path-triggered syncs after the scaffold
    # already mounted it via RequiresMountsFor — a manual mount STACKS a
    # second mount and a later umount only removes the top one, leaving the
    # unit active under it). local-fs skipped the boot mount because vdb
    # was still blank — nofail did its job.
    machine.succeed("systemctl start 'boot\\x2dmirror.mount'")
    machine.succeed("systemctl start boot-mirror-sync.service")
    machine.wait_for_unit("boot-mirror-sync.service")
    mirror_entries = machine.succeed("ls /boot-mirror/loader/entries/").strip()
    assert "nixos-vmtest" in mirror_entries, f"mirror missing entry: {mirror_entries!r}"
    # The diff gate ran: unit success IS tree-identity (random-seed excluded,
    # per-ESP by design).
    assert "loader.conf" in machine.succeed("ls /boot-mirror/loader/"), "mirror missing loader.conf"

    # 2. Reverse-propagation: a loader-side boot-count rename on the SOURCE
    # (booted-side state) converges to the mirror's counter name. The mirror
    # holds nixos-vmtest+2-1.conf; rename the source's copy to +5 (the loader
    # bumped it) — the sync must move the source entry to the MIRROR's name
    # (counters survive; the diff gate stays green).
    machine.succeed("mv '/boot/loader/entries/nixos-vmtest+2-1.conf' '/boot/loader/entries/nixos-vmtest+5.conf'")
    machine.succeed("systemctl restart boot-mirror-sync.service")
    src_after = machine.succeed("ls /boot/loader/entries/").strip()
    assert "+2-1" in src_after and "+5" not in src_after, \
      f"reverse-propagation did not converge the counter: {src_after!r}"
    diff_out = machine.succeed("diff -r -x random-seed /boot /boot-mirror")
    assert diff_out == "", f"mirror diverged after counter convergence: {diff_out!r}"

    # 2b. Blessing: a blessed entry (counter stripped on the booted side,
    # twin still counting on the managed side) drops its stale twin BEFORE
    # the forward copy.
    machine.succeed("mv '/boot/loader/entries/nixos-vmtest+2-1.conf' '/boot/loader/entries/nixos-vmtest.conf'")
    machine.succeed("mv '/boot-mirror/loader/entries/nixos-vmtest+2-1.conf' '/boot-mirror/loader/entries/nixos-vmtest+3.conf'")
    machine.succeed("systemctl restart boot-mirror-sync.service")
    src_blessed = machine.succeed("ls /boot/loader/entries/").strip()
    assert "nixos-vmtest.conf" in src_blessed and "+3" not in machine.succeed("ls /boot-mirror/loader/entries/"), \
      "blessed entry did not converge"

    # 3. Degradation: the mirror goes unusable. Unmount through the unit
    # (systemctl stop: synchronous, no stacked-mount hazard, no
    # mount-monitor lag), then zero the vfat superblock — the disk still
    # attaches, its filesystem is unreadable: the realistic degraded state
    # a consumer's disk develops. Kernel-level unplug proved RACY here
    # (sfdisk --delete left the node mountable — the pulled mount job
    # remounted it; partx BLKPG delete returned EBUSY 10/10 on the virtio
    # disk), and systemctl mask cannot write into NixOS's store-backed
    # /etc. (A plain umount is NOT degradation either: the pulled mount
    # job would just remount vdb1.)
    machine.succeed("systemctl stop 'boot\\x2dmirror.mount' && udevadm settle")
    machine.succeed(
        "dd if=/dev/zero of=/dev/vdb1 bs=512 count=4 && udevadm settle"
    )
    machine.fail("systemctl restart boot-mirror-sync.service")
    # Empirical systemd semantics (pinned): the start JOB dies on the
    # RequiresMountsFor dependency ("dependency" is the JOB result, never
    # written to the service — its Result stays 'success' from the last
    # run); the MOUNT unit carries the failure, the service ends up
    # inactive (deactivated by the restart's stop half, never re-run:
    # no bootctl/rsync output above). No partial copy, no silent success.
    # Boot-level degradation (never a stall) is already proven at the top:
    # multi-user was reached with the mirror absent from boot.
    mount_result = machine.succeed(
        "systemctl show 'boot\\x2dmirror.mount' -p Result --value"
    ).strip()
    assert mount_result == "exit-code", f"expected the mount to carry the failure, got {mount_result!r}"
    svc_state = machine.succeed(
        "systemctl show boot-mirror-sync.service -p ActiveState --value"
    ).strip()
    assert svc_state == "inactive", f"the sync must not run against an unusable mirror: {svc_state!r}"

    # 4. Loud failure: a read-only mirror (partial-copy stand-in) fails the
    # unit — the diff-gate posture: never call a partial mirror current.
    machine.succeed("mkfs.vfat -n MIRRORESP /dev/vdb1 && udevadm settle")
    machine.succeed("systemctl start 'boot\\x2dmirror.mount'")
    machine.succeed("mount -o remount,ro /boot-mirror")
    machine.succeed("touch /boot/loader/entries/trigger-ro.conf")
    machine.fail("systemctl start boot-mirror-sync.service")
    machine.succeed("mount -o remount,rw /boot-mirror")
  '';
}
