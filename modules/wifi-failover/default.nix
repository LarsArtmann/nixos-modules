# WiFi standby failover — carrier-based default-route guard for a static-IP
# ethernet interface.
#
# PROBLEM (why a desktop with connected WiFi still loses connectivity when the
# ethernet cable is pulled): the ethernet default route is STATIC (metric 0,
# set by networking.interfaces). The kernel does NOT remove routes on carrier
# loss — only on admin down. With the cable out, the metric-0 default stays in
# the table and blackholes ALL traffic while the NetworkManager WiFi route
# (metric 100) sits idle. NetworkManager cannot help: the primary interface is
# deliberately unmanaged (static IP stability for services).
#
# SOLUTION: a tiny daemon watches /sys/class/net/<primary>/carrier. On carrier
# loss it deletes the pinned ethernet default routes (v4+v6) — the NM fallback
# route takes over instantly. On carrier return it re-adds `default via
# <gateway> dev <primary>` (metric 0 beats the fallback's metric 100 again).
# The fallback route is NEVER touched — it stays up as hot standby.
#
# Fleet integrations (service registry entries, monitoring wiring) are
# consumer-side: import this module and layer them at the delegation site.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.wifi-failover;
  inherit (lib) mkEnableOption mkOption types;
  inherit (import ../../lib lib)
    harden
    serviceDefaults
    onFailure
    ;

  # Gateway resolution order: explicit option → networking.defaultGateway
  # (string or { address = ...; } form) → null (assertion fails at eval).
  resolvedGateway =
    if cfg.gateway != null then
      cfg.gateway
    else if config.networking.defaultGateway == null then
      null
    else if builtins.isString config.networking.defaultGateway then
      config.networking.defaultGateway
    else
      config.networking.defaultGateway.address or null;

  primaryDevice = "sys-subsystem-net-devices-${cfg.ethernetInterface}.device";

  wifiFailoverScript = pkgs.writeShellApplication {
    name = "wifi-failover-watch";
    runtimeInputs = [
      pkgs.iproute2
      pkgs.gnugrep
      pkgs.coreutils
    ];
    text = builtins.readFile ./watch.sh;
  };
in
{
  options.services.wifi-failover = {
    enable = mkEnableOption "carrier-based standby failover from static ethernet to NetworkManager WiFi";

    ethernetInterface = mkOption {
      type = types.nonEmptyStr;
      default = "eno1";
      description = "Primary ethernet interface (static IP, NixOS-managed)";
    };

    fallbackInterface = mkOption {
      type = types.nonEmptyStr;
      default = "wlan0";
      description = "WiFi fallback interface (NetworkManager-managed hot standby)";
    };

    gateway = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = ''
        IPv4 gateway re-added on carrier return for the primary default
        route. When null, derives from networking.defaultGateway (string or
        address attribute form); enabling without either resolution fails
        at eval time with a pointed message.
      '';
    };

    pollIntervalSeconds = mkOption {
      type = types.ints.positive;
      default = 1;
      description = "Seconds between carrier checks (cable pull is detected within one poll)";
    };

    trustFallbackInterface = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Add the fallback interface to networking.firewall.trustedInterfaces so
        LAN-equivalent service access survives failover (the fallback is the
        user's own hotspot — same trust model as the LAN). Disable to keep it
        filtered down to the globally allowed ports.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = resolvedGateway != null;
        message = ''
          services.wifi-failover needs a gateway: set services.wifi-failover.gateway
          explicitly or provide networking.defaultGateway.
        '';
      }
      {
        # `or false`: an isolated eval of this module alone has no dual-wan
        # module imported — the option tree simply lacks the attribute.
        assertion = !(cfg.enable && (config.services.dual-wan.enable or false));
        message = ''
          services.wifi-failover conflicts with services.dual-wan — both manage
          the ${cfg.ethernetInterface}/fallback default route. dual-wan is
          probe-based ECMP+MPTCP (active-active), wifi-failover is carrier-based
          standby (active-passive). Enable exactly one.
        '';
      }
    ];

    networking.firewall.trustedInterfaces = lib.optionals cfg.trustFallbackInterface [
      cfg.fallbackInterface
    ];

    systemd.services.wifi-failover = {
      description = "WiFi standby failover — carrier-based ${cfg.ethernetInterface} default-route guard";
      wantedBy = [ "multi-user.target" ];
      after = [
        primaryDevice
        "network.target"
      ];
      wants = [
        primaryDevice
        "network.target"
      ];
      inherit onFailure;
      startLimitBurst = 5;
      startLimitIntervalSec = 300;
      serviceConfig = lib.mkMerge [
        {
          Type = "simple";
          Environment = [
            "ENO1_IF=${cfg.ethernetInterface}"
            "FALLBACK_IF=${cfg.fallbackInterface}"
            "GW=${
              if resolvedGateway == null then "<unset: services.wifi-failover.gateway or networking.defaultGateway>" else resolvedGateway
            }"
            "POLL_INTERVAL=${toString cfg.pollIntervalSeconds}"
          ];
          ExecStart = lib.getExe wifiFailoverScript;
        }
        (harden {
          ProtectHome = false;
          CapabilityBoundingSet = "CAP_NET_ADMIN";
          NoNewPrivileges = false;
          MemoryMax = "64M";
        })
        (serviceDefaults { })
      ];
    };
  };
}
