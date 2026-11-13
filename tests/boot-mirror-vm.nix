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
#   3. degradation: with the mirror partition deleted, the sync's
#      RequiresMountsFor dependency-fails the start job (Result=dependency:
#      the script never runs, no partial copy) — a detached mirror degrades
#      boot nothing (multi-user reached with the mirror absent).
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

    # 1. Full sync: mount the formatted mirror (manual mount satisfies the
    # service's ConditionPathIsMountPoint; local-fs skipped it at boot
    # because vdb was still blank — nofail did its job), then sync.
    machine.succeed("mount /dev/vdb1 /boot-mirror")
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

    # 3. Degradation: mirror detached = its kernel partition removed. The
    # sync's RequiresMountsFor pulls the mount unit into every start
    # transaction, so a detached mirror FAILS THE START JOB (dependency):
    # the script never runs — the failed unit never blocks boot (proven
    # above: multi-user was reached mirror-less). (A plain umount is NOT
    # degradation: the pulled mount job would just remount vdb1.)
    machine.succeed("umount /boot-mirror && udevadm settle")
    # Detach the mirror: drop the kernel partition + node. Transient holders
    # right after the umount (mount-unit teardown, udev probing) make the
    # first BLKPG delete race EBUSY — retry until the node is truly gone
    # (sfdisk --delete alone rewrites the table but left the node
    # mountable: the pulled mount job remounted it and bootctl failed
    # exit-code instead of the dependency path).
    machine.succeed(
        "for i in $(seq 1 10); do partx -d --nr 1 /dev/vdb && break; sleep 1; done;"
        " test ! -e /dev/vdb1"
    )
    machine.fail("systemctl restart boot-mirror-sync.service")
    # Empirical systemd semantics (pinned): a detached mirror fails the
    # start JOB through RequiresMountsFor — Result=dependency — so the sync
    # SCRIPT never runs against an absent mirror: no partial copy, no silent
    # success. Boot-level degradation (never a stall) is already proven at
    # the top: multi-user was reached with the mirror absent from boot.
    result = machine.succeed(
        "systemctl show boot-mirror-sync.service -p Result --value"
    ).strip()
    assert result == "dependency", f"expected Result=dependency, got {result!r}"

    # 4. Loud failure: a read-only mirror (partial-copy stand-in) fails the
    # unit — the diff-gate posture: never call a partial mirror current.
    machine.succeed(
        "printf 'label: gpt\\ntype=C12A7328-F81F-11D2-BA4B-00A0C93EC93B\\n'"
        " | sfdisk --wipe always /dev/vdb && udevadm settle"
    )
    machine.succeed(
        "for i in $(seq 1 20); do [ -b /dev/vdb1 ] && break; sleep 1; done;"
        " test -b /dev/vdb1"
    )
    machine.succeed("mkfs.vfat -n MIRRORESP /dev/vdb1 && udevadm settle")
    machine.succeed("mount /dev/vdb1 /boot-mirror")
    machine.succeed("mount -o remount,ro /boot-mirror")
    machine.succeed("touch /boot/loader/entries/trigger-ro.conf")
    machine.fail("systemctl start boot-mirror-sync.service")
    machine.succeed("mount -o remount,rw /boot-mirror")
  '';
}
