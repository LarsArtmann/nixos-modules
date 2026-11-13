# Eval-contract check for the timeout-audit module: a minimal host with the
# module imported must carry the global DefaultTimeoutStartSec=3min via
# systemd.settings.Manager, and an explicit per-service TimeoutStartSec must
# still win over the global default (the mkDefault contract). The negative
# legs in tests/negative/ mutate the module's "3min" and the override pin.
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
        systemd.services.override-carrier.serviceConfig.TimeoutStartSec = "10min";
        fileSystems."/" = {
          device = "/dev/vda1";
          fsType = "ext4";
        };
        boot.loader.grub.devices = ["nodev"];
      }
    ];
  };
  globalDefault = eval.config.systemd.settings.Manager.DefaultTimeoutStartSec;
  perService = eval.config.systemd.services.override-carrier.serviceConfig.TimeoutStartSec;
  contract =
    lib.throwIf (globalDefault != "3min")
    "timeout-audit contract: the global DefaultTimeoutStartSec must default to 3min (got ${toString globalDefault}) — the 90s systemd default expires mid-switch under IO contention and deploys die exit-4"
    (lib.throwIf (perService != "10min")
      "timeout-audit contract: an explicit per-service TimeoutStartSec (10min) must beat the global mkDefault — per-service budgets are the sanctioned override path"
      (builtins.toJSON {
        inherit globalDefault perService;
      }));
in
  pkgs.runCommand "timeout-audit-contract" {
    inherit contract;
    passAsFile = ["contract"];
  } ''
    cp "$contractPath" $out
    echo "timeout-audit-contract: global default + override precedence pinned" >&2
  ''
