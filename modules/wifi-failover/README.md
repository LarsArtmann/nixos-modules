# wifi-failover

Carrier-based standby failover from a static-IP ethernet interface to a
NetworkManager WiFi fallback. See the module header and `watch.sh` for the
full problem/solution narrative (kernel keeps static metric-0 defaults on
carrier loss; the daemon evicts them and re-adds on carrier return).

## Usage

```nix
{
  inputs.nixos-modules.url = "github:LarsArtmann/nixos-modules";
  # ... then:
  imports = [ nixos-modules.nixosModules.wifi-failover ];

  services.wifi-failover = {
    enable = true;
    ethernetInterface = "eno1";   # static, NixOS-managed primary
    fallbackInterface = "wlan0";  # NetworkManager hot standby
    gateway = "192.168.1.1";      # or leave null + set networking.defaultGateway
    pollIntervalSeconds = 1;
    trustFallbackInterface = true;
  };
}
```

## Options

| Option | Type | Default | Notes |
|---|---|---|---|
| `enable` | bool | false | inert until enabled |
| `ethernetInterface` | str | `"eno1"` | primary (static IP) |
| `fallbackInterface` | str | `"wlan0"` | NM-managed standby |
| `gateway` | nullOr str | null | null → derived from `networking.defaultGateway` |
| `pollIntervalSeconds` | positive int | 1 | cable pull detected within one poll |
| `trustFallbackInterface` | bool | true | adds fallback to `firewall.trustedInterfaces` |

## Design notes

- CARRIER-based, never ISP-probe-based: transient upstream blips must not
  evict the primary route. STANDBY model, never ECMP: the fallback is
  typically a metered phone hotspot — no packet splitting.
- An eval-time assertion rejects enabling this together with a
  `services.dual-wan` option when one is declared.
- Fleet integrations (service registry entries, monitoring) are deliberately
  NOT in this module: an `options ? services.<registry>` guard cannot survive
  the enclosing `mkIf cfg.enable` with `enable = true` (the undeclared-option
  assignment materializes and fails the eval) — layer them at the delegation
  site where the registry option is always declared.
- `DEBUG_POLL=1` in the unit environment emits per-poll carrier/last-state
  journal lines for diagnosis.
