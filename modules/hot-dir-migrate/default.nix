# hot-dir-migrate — relocate per-project session-DB directories off the OS
# disk onto a dedicated hot disk, leaving symlinks behind.
#
# PROBLEM (the origin incident): per-project session DBs (2-5 GB SQLite +
# WALs each, 5+ concurrent sessions) churn seeky IO on the OS-disk snapshot
# subvolume, pinning IO pressure for hours while memory stays pristine —
# and every deleted byte stays pinned by snapshots. This module moves each
# project's session dir (e.g. `.crush/`) onto the hot disk and leaves a
# symlink in its place, so every future session write lands on the fast
# disk.
#
# Convergence: the migrate unit is timer-pulled (OnBootSec boot convergence
# + a daily catch-up; a boot-gated unit would delay the login screen — the
# unit is deliberately NOT wantedBy multi-user). A project is skipped while
# a session is LIVE ON THAT PROJECT (a process with the configured comm
# holding an fd/cwd under its session dir — relocating a directory under a
# running writer would strand it on an unlinked inode) or while its DB was
# written in the last N minutes; the next run converges it. The liveness
# guard is PER-PROJECT: a blanket process-name skip starves convergence on
# a box where sessions are always live (one idle session must not block
# every other project). Failures exit non-zero (wire OnFailure +
# monitoring consumer-side); `<dryRunEnvVar>=1` rehearses a run.
#
# The mount for `mountPoint` is NOT managed here — mount the hot disk
# (e.g. via the hot-tier module or hardware config) separately; this unit
# only RequiresMountsFor it.
{
  config,
  lib,
  options,
  pkgs,
  ...
}: let
  cfg = config.services.hot-dir-migrate;
  inherit (lib) mkEnableOption mkIf mkMerge mkOption types;
  inherit
    (import ../../lib lib)
    harden
    ioTier
    onFailure
    serviceOneshotDefaults
    ;
in {
  options.services.hot-dir-migrate = {
    enable = mkEnableOption "relocate per-project session DB dirs to the hot disk";
    unitName = mkOption {
      type = types.str;
      default = "hot-dir-migrate";
      description = "Name of the migrate service AND timer unit (consumers keep their historical unit names for deploy restart blocks and audits).";
    };
    dirName = mkOption {
      type = types.str;
      default = ".crush";
      description = "Session-dir basename to discover and relocate (e.g. `.crush`).";
    };
    dbName = mkOption {
      type = types.str;
      default = "crush.db";
      description = "Database-file basename inside a session dir (drives the fresh-write skip window).";
    };
    matchComm = mkOption {
      type = types.str;
      default = "crush";
      description = "Process comm (kernel-truncated basename) marking a LIVE session writer; processes with this comm holding an fd/cwd under a project's session dir block relocating THAT project only.";
    };
    projectsDir = mkOption {
      type = types.str;
      description = "Directory tree scanned for session dirs (any checkout down to discoveryDepth, e.g. <dir>/group/repo).";
    };
    mountPoint = mkOption {
      type = types.str;
      default = "/mnt/hot";
      description = "Hot-disk mount point (mounted elsewhere; this unit only RequiresMountsFor it).";
    };
    destName = mkOption {
      type = types.str;
      default = "crush";
      description = "Destination directory name under the mount point (final target: <mountPoint>/<destName>/<project>).";
    };
    ownerUser = mkOption {
      type = types.str;
      default = "root";
      description = "User the migrated tree is chowned to (the sessions run as this user; intermediate parents too).";
    };
    ownerGroup = mkOption {
      type = types.str;
      default = "users";
      description = "Group the migrated tree is chowned to.";
    };
    dryRunEnvVar = mkOption {
      type = types.str;
      default = "HOT_DIR_MIGRATE_DRY_RUN";
      description = "Environment variable enabling dry-run rehearsal (reports, never moves).";
    };
    discoveryDepth = mkOption {
      type = types.int;
      default = 3;
      description = "Max checkout depth scanned for session dirs; a dir exactly one level deeper surfaces a WARN tripwire instead of silently staying on the OS disk.";
    };
    freshWriteMinutes = mkOption {
      type = types.int;
      default = 10;
      description = "Skip window: a session dir whose DB was written within this many minutes is left for the next run (a session may have just ended or be about to checkpoint).";
    };
    timerOnBootSec = mkOption {
      type = types.str;
      default = "2min";
      description = "Boot-time convergence delay (timer-pulled, never boot-gated).";
    };
    timerOnCalendar = mkOption {
      type = types.str;
      default = "*-*-* 04:10:00";
      description = "Daily catch-up calendar (Persistent=true catches missed boots).";
    };
  };

  config = mkMerge [
    (mkIf cfg.enable {
      systemd.services.${cfg.unitName} = {
        description = "Relocate per-project ${cfg.matchComm} session dirs to the hot disk";
        # Timer-pulled, NOT boot-gated: the migrate run must not delay the
        # login screen. OnBootSec preserves every-boot convergence; the
        # consumer's deploy flow restarts the unit explicitly for
        # deploy-time convergence.
        unitConfig.RequiresMountsFor = [cfg.mountPoint];
        # List EVERY binary the script execs: the default unit PATH
        # (coreutils/findutils/gnugrep/gnused/systemd) has NO flock
        # (util-linux) — the awk phantom-binary class. pgrep is GONE:
        # the liveness guard reads /proc comm + fd links directly.
        path = [
          pkgs.coreutils
          pkgs.findutils
          pkgs.util-linux
        ];
        serviceConfig = mkMerge [
          {
            Type = "oneshot";
            User = "root";
            # Stays "active (exited)": deploy restart semantics apply
            # (stc never restarts a oneshot on change).
            RemainAfterExit = true;
          }
          (harden {
            # chown for the migrated tree, CAP_FOWNER/CAP_DAC_OVERRIDE for
            # the rename over the project's dir + symlink swap (harden{}'s
            # empty bounding set would EPERM both).
            # CAP_SYS_PTRACE (2026-11-12 regression fix): the liveness
            # guard reads /proc/<pid>/fd symlink TARGETS of foreign
            # processes — under yama ptrace_scope=1 that readlink returns
            # EACCES for every fd even for root without this capability,
            # silently blinding the guard (the unit relocates a live
            # writer's dir). Kernels/nixpkgs now ship scope=1 where the
            # original host ran scope=0.
            CapabilityBoundingSet = "CAP_CHOWN CAP_FOWNER CAP_DAC_OVERRIDE CAP_SYS_PTRACE";
            # MUST override harden{}'s ProtectHome default (`true`): systemd
            # maps yes/true to INACCESSIBLE-AND-EMPTY (/home becomes an
            # empty tmpfs inside the unit), so `find $projects` ENOENTs
            # every run (0 relocated, exit 0 — the phantom-green shape).
            # Only a booting unit exposes it; transient replicas that probe
            # read-only pass and hide it.
            ProtectHome = "read-only";
            # The MOUNT ROOT — never the <mountPoint>/<destName> subdir:
            # ReadWritePaths paths must exist BEFORE the unit starts
            # (systemd builds the mount namespace before any ExecStart; a
            # missing entry aborts 226/NAMESPACE and the script's own mkdir
            # can never create it). RequiresMountsFor guarantees the root;
            # the script's mkdir -p creates the subdir inside it.
            ReadWritePaths = [
              cfg.mountPoint
              cfg.projectsDir
            ];
          })
          # Bulk OS-disk reads + SQLite churn — never contend with the
          # interactive tiers that motivated the move.
          ioTier.background
          (serviceOneshotDefaults {})
        ];
        # A per-dir migration failure must PAGE, not log-and-exit-0.
        inherit onFailure;
        script = ''
          projects=${cfg.projectsDir}
          dest=${cfg.mountPoint}/${cfg.destName}
          dryRun=''${${cfg.dryRunEnvVar}:-}

          # Single-flight: the daily timer and a deploy can overlap.
          if ! exec 9>/run/${cfg.unitName}.lock; then
            echo "skip: cannot open lock file" >&2
            exit 0
          fi
          if ! flock -n 9; then
            echo "skip: another migration run holds the lock"
            exit 0
          fi

          if [ -z "$dryRun" ]; then
            mkdir -p "$dest"
            chown ${cfg.ownerUser}:${cfg.ownerGroup} "$dest"
          fi

          # Bounded-depth find covers NESTED checkouts too
          # ($projects/<group>/<repo>/<sessiondir>). -prune: never descend
          # into a matched session dir (session DBs are huge; nothing nests
          # inside). -type d does not match the already-migrated symlinks.
          # NUL-delimited mapfile: checkout names may contain spaces.
          mapfile -d "" -t sessionDirs < <(
            find "$projects" -mindepth 1 -maxdepth ${toString cfg.discoveryDepth} -type d -name ${cfg.dirName} -prune -print0 | sort -z
          )

          # Depth tripwire: a session dir one level below the discovery cap
          # would silently stay on the OS disk forever. Bounded to exactly
          # discoveryDepth+1 (the "one level down" silent-miss class) so
          # the walk stays a metadata-cheap extension of the main find.
          deep="$(find "$projects" -mindepth ${toString (cfg.discoveryDepth + 1)} -maxdepth ${toString (cfg.discoveryDepth + 1)} -name ${cfg.dirName} -print -quit 2>/dev/null || true)"
          if [ -n "$deep" ]; then
            echo "WARN: ${cfg.dirName} deeper than discovery depth ${toString cfg.discoveryDepth} (stays on the OS disk): $deep" >&2
          fi

          # Never relocate a directory out from under a LIVE WRITER: the
          # writer would keep writing to the moved-away inode. PER-PROJECT
          # liveness: a blanket process-name skip starves convergence — on
          # a box where sessions are ALWAYS live, one idle session blocked
          # every project for days. A session is live on a project iff a
          # comm=<matchComm> process holds an fd or its cwd under that
          # project's session dir; post-migration sessions hold fds on the
          # hot-disk targets and correctly never match (their dirs are
          # already symlinks). Sweep AFTER the find to keep the
          # start-to-mv race minimal.
          declare -A liveSessionDirs=()
          for pidDir in /proc/[0-9]*; do
            [ "$(cat "$pidDir/comm" 2>/dev/null)" = "${cfg.matchComm}" ] || continue
            echo "DBG: scanning ${cfg.matchComm} pid $pidDir yama=$(cat /proc/sys/kernel/yama/ptrace_scope 2>/dev/null) fdls=[$(ls "$pidDir/fd" 2>&1 | head -8 | tr '\n' ' ')]" >&2
            for link in "$pidDir"/fd/* "$pidDir"/cwd; do
              openPath="$(readlink "$link" 2>/dev/null)" || { echo "DBG: readlink FAILED: $link" >&2; continue; }
              case "$openPath" in
                "$projects"/${cfg.dirName}|"$projects"/${cfg.dirName}/*|"$projects"/*/${cfg.dirName}|"$projects"/*/${cfg.dirName}/*)
                  liveSessionDirs["''${openPath%%/${cfg.dirName}*}/${cfg.dirName}"]=1
                  ;;
              esac
            done
          done

          migrated=0
          failed=0
          for d in "''${sessionDirs[@]}"; do
            # -d follows symlinks: an already-migrated project matches and
            # is skipped; the -L guard is belt-and-suspenders for a race
            # between find and the loop.
            if [ ! -d "$d" ] || [ -L "$d" ]; then
              continue
            fi
            name="''${d#"$projects"/}"
            name="''${name%/${cfg.dirName}}"
            if [ "$name" = "${cfg.dirName}" ]; then
              name="projects-root"
            fi
            target="$dest/$name"

            if [ -n "''${liveSessionDirs["$d"]:-}" ]; then
              echo "skip $name: live ${cfg.matchComm} session holds it open"
              continue
            fi
            # Fresh writes = a session may have JUST ended (or about to
            # checkpoint) — leave it one more cycle.
            if [ -n "$(find "$d" -maxdepth 1 -name '${cfg.dbName}*' -mmin -${toString cfg.freshWriteMinutes} -print -quit)" ]; then
              echo "skip $name: ${cfg.dbName} written in the last ${toString cfg.freshWriteMinutes} minutes"
              continue
            fi
            if [ -e "$target" ]; then
              # Empty-target auto-heal: a target dir with NOTHING inside is
              # interrupted-run residue (root-owned 0700, left by a
              # freeze-hit first run) — nothing to merge, safe to rmdir and
              # migrate into. A POPULATED target (or a non-dir/symlink)
              # keeps the manual-merge refusal: it may hold real session
              # data.
              if [ -d "$target" ] && [ ! -L "$target" ] && [ -z "$(find "$target" -mindepth 1 -print -quit 2>/dev/null)" ]; then
                if [ -n "$dryRun" ]; then
                  echo "dry-run: would heal empty target $target and migrate $name"
                  migrated=$((migrated + 1))
                  continue
                fi
                if rmdir "$target"; then
                  echo "healed empty target $target"
                else
                  echo "FAILED to heal empty target $target" >&2
                  failed=$((failed + 1))
                  continue
                fi
              else
                echo "skip $name: target $target already exists (manual merge needed)"
                continue
              fi
            fi
            if [ -n "$dryRun" ]; then
              echo "dry-run: would migrate $name → $target"
              migrated=$((migrated + 1))
              continue
            fi
            # Nested names carry slashes (group/repo): the parent hierarchy
            # must exist before mv (root-owned intermediates stay
            # traversable).
            parent="$(dirname "$target")"
            if [ ! -d "$parent" ]; then
              mkdir -p "$parent"
              chown ${cfg.ownerUser}:${cfg.ownerGroup} "$parent"
            fi
            if mv "$d" "$target" && ln -s "$target" "$d"; then
              echo "migrated $name → $target"
              migrated=$((migrated + 1))
            else
              echo "FAILED to migrate $name" >&2
              failed=$((failed + 1))
            fi
          done
          if [ -n "$dryRun" ]; then
            echo "dry-run: would relocate $migrated project(s)"
          else
            echo "${cfg.unitName}: $migrated project(s) relocated"
          fi
          # Per-dir mv failures must be VISIBLE — the old log-and-exit-0
          # shape kept the unit green forever.
          if [ "$failed" -gt 0 ]; then
            echo "${cfg.unitName}: $failed migration failure(s)" >&2
            exit 1
          fi
        '';
      };

      systemd.timers.${cfg.unitName} = {
        description = "Periodically converge per-project ${cfg.matchComm} session dirs onto the hot disk";
        wantedBy = ["timers.target"];
        timerConfig = {
          # OnBootSec replaces a boot-gating wantedBy=multi-user (boot
          # convergence without boot gating). The service is
          # RemainAfterExit=true, so the boot fire is the one effective run
          # per boot. Note the window: a session live at boot convergence
          # time makes the unit self-skip (by design), converging on the
          # next run.
          OnBootSec = cfg.timerOnBootSec;
          # Quiet window; Persistent catches up missed boots.
          OnCalendar = cfg.timerOnCalendar;
          Persistent = true;
        };
      };
    })

    # Monitoring wiring: OnFailure lands consumer-side, but a system-health
    # attrpath, when the consumer fleet declares one, should carry the
    # migrate unit. Guarded — this module must stay importable standalone
    # in tests: optionalAttrs keeps the attrpath absent there, so an
    # undeclared-option error can never fire (the mkIf-wrapped-empty-def
    # trap only bites when the KEY is present).
    (mkIf cfg.enable (
      lib.optionalAttrs (options ? services.system-health) {
        services.system-health.extraMonitoredServices = lib.mkAfter [
          cfg.unitName
        ];
      }
    ))
  ];
}
