# 2nd boot disk — verified byte-mirror of the primary ESP.
#
# PROBLEM: a single ESP is a single point of failure for the whole boot chain.
# nixpkgs `mirroredBoots` is grub/generic-extlinux-only (verified 2026-09-18) —
# systemd-boot has no declarative mirror; the builder writes the primary ESP
# only.
#
# SOLUTION: this module mounts a second ESP and keeps it a verified byte-mirror
# of the primary: a oneshot `boot-mirror-sync` unit runs at boot, on every
# loader-entries change (a path unit — covers raw `switch-to-configuration`
# gen-installs, not just deploy flows), and can be restarted by any provisioner.
# The mirror install keeps loader-owned boot-counting state intact by
# reverse-propagating the BOOTED ESP's entry renames back to the managed ESP
# before the forward rsync — a plain forward mirror would `--delete` the
# renames, silently resetting a converging boot counter or un-blessing a good
# entry. NixOS content still flows primary -> mirror only; filenames are
# content-hashed, so the two flows never collide.
#
# The FIRMWARE switch (EFI entry + BootOrder) is deliberately NOT automatic:
# it is an operator decision (a one-shot activation command at the consumer).
# Reboots are deliberate events; NVRAM order must not fight the operator.
#
# Boot counting contract (tries/timeout) is consumer-owned; this module only
# requires that whatever the loader does to the booted ESP survives the sync.
#
# Fleet integrations (failure routing, service monitoring) are consumer-side:
# import this module and layer them at the delegation site.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.boot-mirror;
  inherit (lib) mkEnableOption mkIf mkMerge mkOption types;
  inherit
    (import ../../lib lib)
    harden
    ioTier
    onFailure
    serviceOneshotDefaults
    ;

  src = cfg.sourceEsp;
  mirror = cfg.mountPoint;

  # rsync to vfat: --no-owner/--no-group/--no-perms because FAT cannot store
  # unix ownership (chown would EPERM under harden{}'s empty cap set) and the
  # mount's fmask/dmask already present everything as 0700. --modify-window=2
  # covers FAT's 2-second mtime granularity so unchanged files are skipped.
  # /loader/random-seed is deliberately PER-ESP (systemd-boot derives the
  # ERSP from it): excluded from copy AND protected receiver-side from
  # --delete (rsync protects excluded files on the receiver by default).
  # Hoisted out of the writeShellApplication so the eval-time self-assertion
  # below can pin the verification gate: the `diff -r` leg is runtime-only
  # (a regression syncs fine and arms a stale boot silently) unless its
  # shape is contract-pinned at eval time.
  syncText = ''
    set -euo pipefail

    # 1. Install/refresh systemd-boot on the mirror ESP: loader binary +
    #    EFI/BOOT fallback + per-ESP random seed. --variables=no: this unit
    #    never touches EFI variables — NVRAM is owned by the consumer's
    #    activation command. --make-entry-directory=no: the auto
    #    entry-token dir would exist ONLY on the mirror and trip the diff
    #    gate below (NixOS's builder writes entries straight into
    #    loader/entries/, no token dir).
    bootctl --esp-path="${mirror}" --variables=no --make-entry-directory=no install

    # 2. Reverse-propagate loader-owned state (booted ESP -> managed ESP)
    #    BEFORE the forward mirror. The loader mutates the ESP it BOOTS, so
    #    its boot counting renames (nixos-<hash>+T.conf -> +T-K.conf per
    #    attempt) and blessings (suffix stripped once boot-complete.target
    #    is reached) land ONLY there. Matching the managed twin to the
    #    booted ESP's state makes rsync see identical filenames: counters
    #    survive the mirror, the diff gate stays green, and a partial-hang
    #    boot (multi-user reached, boot-complete never) still converges to
    #    fallback instead of being counter-reset by this very sync.
    find ${src}/loader/entries -maxdepth 1 -type f -name '*+*.conf' -printf '%f\n' |
      while IFS= read -r entry; do
        if ! [[ $entry =~ ^(.*)\+[0-9]+(-[0-9]+)?\.conf$ ]]; then
          continue # not a boot-counting entry — builder only writes +T names
        fi
        stem=''${BASH_REMATCH[1]}
        if [ -e "${mirror}/loader/entries/''${stem}.conf" ]; then
          rm -f "${src}/loader/entries/''${entry}" # blessed on the booted ESP: drop the stale counting twin
        else
          matched=$(find "${mirror}/loader/entries" -maxdepth 1 -type f -name "''${stem}+*.conf" -printf '%f\n' | head -n 1)
          # A converged twin is a correct NO-OP: on case-insensitive vfat,
          # byte-different names can resolve to the SAME file and GNU mv
          # dies "are the same file", aborting the sync BEFORE the rsync
          # leg and leaving the mirror stale. The -ef inode test is
          # exactly mv's own same-file predicate — skip instead of crash.
          if
            [ -n "$matched" ] && [ "$matched" != "''${entry}" ] \
              && ! [ "${src}/loader/entries/''${entry}" -ef "${src}/loader/entries/''${matched}" ]
          then
            mv -f "${src}/loader/entries/''${entry}" "${src}/loader/entries/''${matched}"
          fi
        fi
      done

    # 3. Full tree mirror (entries, kernels, initrds, loader.conf).
    rsync \
      --archive --no-owner --no-group --no-perms --modify-window=2 \
      --delete \
      --exclude=/loader/random-seed \
      ${src}/ "${mirror}/"

    # 4. Verification gate — the 2nd boot disk must be tree-identical to
    #    the ESP the system actually manages, or it is a lie. Any drift
    #    (failed copy, partial write, manual edit) fails the unit loudly
    #    instead of arming a stale-boot trap. "System Volume Information"
    #    is FAT-tooling noise, never mirrored.
    if ! diff -r -x random-seed -x "System Volume Information" ${src} "${mirror}"; then
      echo "boot-mirror-sync: mirror diverges from ${src} (diff above) — refusing to call the 2nd boot disk current" >&2
      exit 1
    fi

    counters=$(find ${mirror}/loader/entries -maxdepth 1 -name '*+*.conf' -type f -printf '%f\n' | tr '\n' ' ')
    echo "boot-mirror-sync: OK — $(find ${mirror}/loader/entries -maxdepth 1 -name 'nixos-*.conf' -type f | wc -l) entries, counters[''${counters:-none}], $(du -sh ${mirror} 2>/dev/null | cut -f1) mirrored"
  '';
  syncScript = pkgs.writeShellApplication {
    name = "boot-mirror-sync";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.diffutils
      pkgs.findutils # entry count (shellcheck SC2012: ls|wc is uncountable)
      pkgs.rsync
      pkgs.systemd # bootctl
    ];
    text = syncText;
  };
in {
  options.services.boot-mirror = {
    enable = mkEnableOption "a verified byte-mirror of the primary ESP on a 2nd boot disk";

    device = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = ''
        Source path of the mirror ESP (a /dev/disk/by-uuid/… or by-id/… path
        is strongly preferred — enumeration order flips across boots).
        Enabling without a device fails at eval time.
      '';
    };

    mountPoint = mkOption {
      type = types.nonEmptyStr;
      default = "/boot-mirror";
      description = "Mountpoint for the mirror ESP (nofail; a detached mirror degrades, never blocks boot)";
    };

    sourceEsp = mkOption {
      type = types.nonEmptyStr;
      default = "/boot";
      description = "Mountpoint of the managed primary ESP (the sync source and diff-gate reference)";
    };

    fsType = mkOption {
      type = types.nonEmptyStr;
      default = "vfat";
      description = "Filesystem type of the mirror ESP";
    };

    mountOptions = mkOption {
      type = types.listOf types.str;
      default = [
        "fmask=0077"
        "dmask=0077"
        "nofail"
      ];
      description = ''
        Mount options for the mirror ESP. The default set is vfat-shaped
        (ownership cannot be stored) and MUST keep "nofail" — the module
        asserts it (wants-not-requires: a detached mirror condition-skips the
        sync instead of failing boot).
      '';
    };
  };

  config = mkIf cfg.enable (mkMerge [
    {
      assertions = [
        {
          assertion = cfg.device != null;
          message = ''
            services.boot-mirror needs the mirror ESP device: set
            services.boot-mirror.device to its /dev/disk/by-uuid/… path.
          '';
        }
        {
          # Self-pinned contract: the path trigger + the wants-not-requires
          # posture are the two halves of the stale-boot fix — a regression
          # of either must fail eval, not wait for the next stale boot.
          assertion =
            (config.systemd.paths.boot-mirror-sync.pathConfig.PathChanged or null)
            == ["${src}/loader/entries"];
          message = "boot-mirror-sync.path: must watch ${src}/loader/entries (PathChanged) — without it, non-deploy gen-installs leave the mirror ESP stale";
        }
        {
          assertion =
            (config.systemd.paths.boot-mirror-sync.pathConfig.Unit or null)
            == "boot-mirror-sync.service";
          message = "boot-mirror-sync.path: must trigger boot-mirror-sync.service";
        }
        {
          assertion = builtins.elem "multi-user.target" config.systemd.paths.boot-mirror-sync.wantedBy;
          message = "boot-mirror-sync.path: must be wantedBy multi-user.target so the watch arms at boot";
        }
        {
          assertion =
            (config.systemd.services.boot-mirror-sync.unitConfig.ConditionPathIsMountPoint or null)
            == mirror;
          message = "boot-mirror-sync.service: the mount condition must stay — a path-unit trigger with an unmounted mirror must condition-skip, never fail";
        }
        {
          # Self-pinned contract: the post-rsync `diff -r` verification gate
          # (step 4 of the sync script) is the "the 2nd boot disk must be
          # tree-identical or it is a lie" half. It is runtime-only by
          # nature — a regression (gate stripped or neutered) syncs green
          # and arms the NEXT stale boot — so pin its two load-bearing
          # fragments at eval: the diff invocation shape and the loud
          # refusal message. The negative-harness diffgate-stripped leg
          # proves this assertion bites.
          assertion =
            lib.hasInfix ''if ! diff -r -x random-seed -x "System Volume Information"'' syncText
            && lib.hasInfix "refusing to call the 2nd boot disk current" syncText;
          message = "boot-mirror-sync: the diff -r verification gate must stay — a mirror allowed to silently diverge is a stale-boot trap";
        }
      ];
    }

    (mkIf (cfg.device != null) {
      # nofail is asserted above: a dead/absent mirror skips the mount, the
      # sync unit condition-skips, and the primary boot chain stays fully
      # functional — the mirror is purely additive redundancy. NOT
      # neededForBoot: stage 1 never mounts it (the firmware consumes the
      # ESP contents directly).
      fileSystems.${mirror} = {
        inherit (cfg) device fsType;
        options = cfg.mountOptions;
      };

      assertions = [
        {
          assertion = builtins.elem "nofail" config.fileSystems.${mirror}.options;
          message = "boot-mirror: the mirror filesystem must stay nofail (wants-not-requires: a detached mirror degrades, never blocks boot)";
        }
      ];

      systemd.services.boot-mirror-sync = {
        description = "Mirror ${src} (managed ESP) to the 2nd-boot-disk ESP at ${mirror}";
        wantedBy = ["multi-user.target"];
        # NO explicit after= on the mount unit: systemd escapes the dash, so
        # a mountpoint like /boot-mirror becomes boot\x2dmirror.mount — a
        # literal name would name a nonexistent unit. unitConfig.
        # RequiresMountsFor below already implies Requires=+After= on the
        # real mount(s).
        unitConfig = {
          # Gate BOTH ESPs: without the source mounted, a pre-mount
          # namespace view (the empty rootfs shadow dir under the
          # mountpoint) would be rsync --delete'd onto the mirror — wiping
          # the mirror ESP. Mount-gating applies to the READ source, not
          # just write targets.
          RequiresMountsFor = [
            src
            mirror
          ];
          ConditionPathIsMountPoint = mirror;
        };
        startLimitBurst = 5;
        startLimitIntervalSec = 300;
        serviceConfig = lib.mkMerge [
          # ProtectSystem=false (EROFS class, 2026-10-18): every ProtectSystem
          # level below "strict" RO-binds the source ESP ("true" already
          # includes it), and the ReadWritePaths rw-remount of that bind left
          # source-ESP RENAMES failing "Read-only file system" while
          # non-namespaced bootctl wrote it seconds earlier; the bind-remount
          # was read-only, not the fs. The unit is a config-pinned root
          # oneshot; /usr write exposure is not in its threat model.
          (harden {ProtectSystem = false;})
          (serviceOneshotDefaults {})
          # Background tier: the sync is a bulk copy (rsync + diff -r verify)
          # that must finish but never contends with interactive I/O — fires
          # at boot, on entry-tree changes, and on deploy restarts.
          ioTier.background
          {
            Type = "oneshot";
            RemainAfterExit = true;
            ExecStart = lib.getExe syncScript;
            TimeoutStartSec = "5min";
          }
        ];
        inherit onFailure;
      };

      # Stale-boot class (2026-10-17): the sync only running on provisioner
      # restart and at boot left ANY other gen-install path (raw
      # switch-to-configuration, a manual bootctl call) serving yesterday's
      # generation while NVRAM pointed at the mirror. A path unit on the
      # entries dir closes the class for every writer: inotify sees
      # new/removed .conf files and re-triggers the (RemainAfterExit)
      # service. restartTriggers would NOT do — that fires on NIX config
      # changes, not runtime ESP writes. The sync's own reverse-propagation
      # writes into the same dir and can re-arm the trigger once; the second
      # run converges (no further source writes), so there is no loop. An
      # unmounted mirror stays a clean condition-skip: the path unit
      # activates the service, the service's ConditionPathIsMountPoint skips
      # it — wants-not-requires preserved.
      systemd.paths.boot-mirror-sync = {
        description = "Re-mirror ${src} when loader entries change (any gen-install path)";
        wantedBy = ["multi-user.target"];
        pathConfig = {
          PathChanged = ["${src}/loader/entries"];
          Unit = "boot-mirror-sync.service";
        };
      };
    })
  ]);
}
