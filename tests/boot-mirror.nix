# Eval-contract check for the boot-mirror module: a fixture host with the
# module enabled must (a) evaluate fully (module assertions travel with it and
# throw here if violated), and (b) render the exact sync contract the
# stale-boot fix pinned: path unit watching <sourceEsp>/loader/entries →
# boot-mirror-sync.service, mount condition, nofail mount, background IO tier.
# A VM is not needed: the contract is entirely eval-observable. The
# fail-on-bug-shape legs (mutate module → expect throw) live in
# tests/negative/ and drive the same fixture.
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
        services.boot-mirror.enable = true;
        services.boot-mirror.device = "/dev/disk/by-uuid/0000-C0NTRACT";
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
  # Forcing the toplevel drvPath forces the full config merge — any module
  # assertion violation throws here, not at deploy time.
  inherit (eval.config) systemd fileSystems;
  pathUnit = systemd.paths.boot-mirror-sync;
  svc = systemd.services.boot-mirror-sync;
  contract =
    lib.throwIfNot (pathUnit.pathConfig.PathChanged or null == ["/boot/loader/entries"])
    "boot-mirror contract: PathChanged must watch /boot/loader/entries"
    (lib.throwIfNot (pathUnit.pathConfig.Unit or null == "boot-mirror-sync.service")
      "boot-mirror contract: path unit must trigger boot-mirror-sync.service"
      (lib.throwIfNot (lib.elem "multi-user.target" pathUnit.wantedBy)
        "boot-mirror contract: path unit must be wantedBy multi-user.target"
        (lib.throwIfNot (svc.unitConfig.ConditionPathIsMountPoint or null == "/boot-mirror")
          "boot-mirror contract: service must keep ConditionPathIsMountPoint (condition-skip, never fail)"
          (lib.throwIfNot (lib.elem "nofail" fileSystems."/boot-mirror".options)
            "boot-mirror contract: mirror filesystem must stay nofail"
            (lib.throwIfNot (svc.serviceConfig.IOSchedulingPriority or null == 6)
              "boot-mirror contract: sync must keep the background IO tier"
              (lib.throwIfNot (svc.serviceConfig.ProtectSystem == false)
                "boot-mirror contract: ProtectSystem=false is load-bearing (EROFS class on the read source)"
                (lib.throwIfNot (builtins.match ".*/boot-mirror-sync" svc.serviceConfig.ExecStart != null)
                  "boot-mirror contract: ExecStart must run the sync script"
                  (builtins.toJSON {
                    PathChanged = pathUnit.pathConfig.PathChanged or null;
                    Unit = pathUnit.pathConfig.Unit or null;
                    inherit (pathUnit) wantedBy;
                    ConditionPathIsMountPoint = svc.unitConfig.ConditionPathIsMountPoint or null;
                    mountOptions = fileSystems."/boot-mirror".options;
                    IOSchedulingPriority = svc.serviceConfig.IOSchedulingPriority or null;
                    ProtectSystem = svc.serviceConfig.ProtectSystem;
                  }))))))));
in
  pkgs.runCommand "boot-mirror-contract" {
    # Force the full eval (assertions included) at build-input time.
    drv = eval.config.system.build.toplevel.drvPath;
    inherit contract;
    passAsFile = ["contract"];
  } ''
    cp "$contractPath" $out
    echo "boot-mirror-contract: fixture host evaluates; contract pinned" >&2
  ''
