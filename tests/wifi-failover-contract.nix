# Eval-contract check for the wifi-failover module: a fixture host with the
# service enabled and an explicit gateway must (a) evaluate fully (the
# gateway-resolution and dual-wan-conflict assertions travel with it), and
# (b) render the wiring the failover contract needs: GW/IF environment
# injection into the watch daemon, the fallback interface trusted, and the
# multi-user target pull-in. The VM leg (tests/wifi-failover.nix) proves the
# runtime failover behavior; this check makes the eval-observable clauses
# cheap so the fail-on-bug-shape legs in tests/negative/ can mutate-and-prove
# them (gateway-null, dual-wan-conflict).
{
  lib,
  pkgs,
  module,
}: let
  # Stand-in for the fleet's dual-wan module (which lives SystemNix-side and
  # is NOT part of this collection): declares just enough option surface for
  # the conflict assertion to be exercisable. The negative harness flips
  # dualWanEnabled to true and expects the module assertion to throw.
  dualWanEnabled = false;
  dualWanStub = {
    options.services.dual-wan.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Stub stand-in for the SystemNix dual-wan module's enable flag (conflict-test only).";
    };
    config.services.dual-wan.enable = dualWanEnabled;
  };

  eval = lib.nixosSystem {
    system = "x86_64-linux";
    modules = [
      module
      dualWanStub
      {
        services.wifi-failover = {
          enable = true;
          gateway = "192.168.9.1";
        };
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
  svc = eval.config.systemd.services.wifi-failover;
  env = svc.serviceConfig.Environment;
  # Evaluating config.assertions forces every module assertion — the
  # gateway-resolution and dual-wan-conflict assertions throw here with
  # THEIR messages BEFORE any pin below, so the negative harness greps
  # (gateway-null, dual-wan-conflict) match the module's own words. (The
  # earlier variant forced system.build.toplevel.drvPath into the contract
  # string and derivation env; a .drv-path string context cannot be realized
  # on a fresh store — the CI first-run failure, run 43336330142.)
  failedAssertions =
    map (a: a.message)
    (lib.filter (a: !a.assertion) eval.config.assertions);
  pins =
    lib.throwIfNot (builtins.any (e: lib.hasPrefix "GW=192.168.9.1" e) env)
    "wifi-failover contract: the resolved gateway must be injected as the GW environment variable (the daemon re-adds the primary route via it)"
    (lib.throwIfNot (builtins.any (e: e == "ENO1_IF=eno1") env)
      "wifi-failover contract: the primary interface env var must reflect ethernetInterface"
      (lib.throwIfNot (builtins.any (e: e == "FALLBACK_IF=wlan0") env)
        "wifi-failover contract: the fallback interface env var must reflect fallbackInterface"
        (lib.throwIfNot (builtins.any (e: lib.hasPrefix "POLL_INTERVAL=" e) env)
          "wifi-failover contract: the poll interval env var must be present"
          (lib.throwIfNot (builtins.elem "wlan0" eval.config.networking.firewall.trustedInterfaces)
            "wifi-failover contract: the fallback interface must be trusted by default (LAN-equivalent trust model)"
            (lib.throwIfNot (lib.elem "multi-user.target" svc.wantedBy)
              "wifi-failover contract: the unit must be wanted by multi-user.target"
              (lib.throwIfNot (lib.hasSuffix "bin/wifi-failover-watch" (builtins.toString svc.serviceConfig.ExecStart))
                "wifi-failover contract: ExecStart must run the packaged watch daemon"
                (builtins.toJSON {
                  environment = env;
                  trustedInterfaces = eval.config.networking.firewall.trustedInterfaces;
                  inherit (svc) wantedBy;
                  execStart = builtins.toString svc.serviceConfig.ExecStart;
                })))))));
  contract =
    if failedAssertions != []
    then throw "wifi-failover contract: module assertions failed:\n${lib.concatStringsSep "\n" failedAssertions}"
    else pins;
in
  pkgs.runCommand "wifi-failover-contract" {
    inherit contract;
    passAsFile = ["contract"];
  } ''
    cp "$contractPath" $out
    echo "wifi-failover-contract: fixture host evaluates; contract pinned" >&2
  ''
