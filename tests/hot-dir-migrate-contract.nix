# Eval-contract check for the hot-dir-migrate module: a fixture host with
# the engine enabled must (a) evaluate fully, and (b) render the exact
# unit/script contract four review rounds pinned: RequiresMountsFor the
# MOUNT ROOT (226/NAMESPACE class), flock in the unit path (phantom-binary
# class), ProtectHome=read-only (NOT true — the empty-/home phantom-green
# class), the /proc liveness sweep with per-project skip (the blanket-skip
# starvation class), the depth tripwire, and the timer-pulled (never
# boot-gated) shape. Expectations are HARDCODED against default option
# values so mutations trip them (never rendered from the same expression —
# the phantom-leg class). The VM leg (tests/hot-dir-migrate.nix) proves the
# behaviors at runtime.
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
        services.hot-dir-migrate = {
          enable = true;
          projectsDir = "/home/lars/projects";
          ownerUser = "lars";
        };
        users.users.lars.isNormalUser = true;
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
  svc = eval.config.systemd.services.hot-dir-migrate;
  timer = eval.config.systemd.timers.hot-dir-migrate;
  script = svc.script or "";
  contract =
    lib.throwIfNot (svc.unitConfig.RequiresMountsFor or null == ["/mnt/hot"])
    "hot-dir-migrate contract: RequiresMountsFor must pin the MOUNT ROOT (226/NAMESPACE class)"
    (lib.throwIfNot (lib.hasInfix "util-linux" (lib.concatStringsSep " " (map toString svc.path)))
      "hot-dir-migrate contract: unit path must carry util-linux (flock — the phantom-binary class)"
      (lib.throwIfNot (lib.hasInfix "CAP_SYS_PTRACE" (svc.serviceConfig.CapabilityBoundingSet or ""))
        "hot-dir-migrate contract: CapabilityBoundingSet must carry CAP_SYS_PTRACE (yama ptrace_scope=1 readlink class — without it the liveness guard is blind)"
        (lib.throwIfNot (svc.serviceConfig.ProtectHome == "read-only")
          "hot-dir-migrate contract: ProtectHome must be read-only (true = inaccessible-and-EMPTY /home, every find ENOENTs)"
          (lib.throwIfNot (svc.serviceConfig.ReadWritePaths == ["/mnt/hot" "/home/lars/projects"])
            "hot-dir-migrate contract: ReadWritePaths must be exactly mount root + projects dir"
            (lib.throwIfNot (svc.wantedBy == [] || svc.wantedBy == null)
              "hot-dir-migrate contract: the migrate unit must NOT be boot-gated (wantedBy empty; timer owns convergence)"
              (lib.throwIfNot (lib.hasInfix "for pidDir in /proc/[0-9]*" script)
                "hot-dir-migrate contract: the /proc liveness sweep must be present (per-project live-writer guard)"
                (lib.throwIfNot (lib.hasInfix "live crush session holds it open" script)
                  "hot-dir-migrate contract: the per-project live-session skip message must be present (blanket-skip starvation class)"
                  (lib.throwIfNot (lib.hasInfix "flock -n 9" script)
                    "hot-dir-migrate contract: single-flight flock must be present"
                    (lib.throwIfNot (lib.hasInfix "deeper than discovery depth 3" script)
                      "hot-dir-migrate contract: the depth tripwire WARN must be present"
                      (lib.throwIfNot (lib.hasInfix "exit 1" script)
                        "hot-dir-migrate contract: per-dir failures must exit non-zero (the log-and-exit-0 green-forever class)"
                        (lib.throwIfNot (timer.timerConfig.OnBootSec == "2min" && timer.timerConfig.Persistent or false == true)
                          "hot-dir-migrate contract: timer must keep OnBootSec boot convergence + Persistent catch-up"
                          (lib.throwIfNot (lib.elem "timers.target" timer.wantedBy)
                            "hot-dir-migrate contract: timer must be wantedBy timers.target"
                            (builtins.toJSON {
                              RequiresMountsFor = svc.unitConfig.RequiresMountsFor or null;
                              ProtectHome = svc.serviceConfig.ProtectHome;
                              ReadWritePaths = svc.serviceConfig.ReadWritePaths;
                              wantedBy = svc.wantedBy;
                              timerOnBootSec = timer.timerConfig.OnBootSec;
                              timerPersistent = timer.timerConfig.Persistent or null;
                            })))))))))))));
in
  pkgs.runCommand "hot-dir-migrate-contract" {
    # Force the full eval (assertions included) at build-input time.
    drv = eval.config.system.build.toplevel.drvPath;
    inherit contract;
    passAsFile = ["contract"];
  } ''
    cp "$contractPath" $out
    echo "hot-dir-migrate-contract: fixture host evaluates; contract pinned" >&2
  ''
