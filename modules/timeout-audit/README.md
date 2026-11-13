# timeout-audit

Sets a global `DefaultTimeoutStartSec=3min` via `systemd.settings.Manager`,
covering every service — upstream nixpkgs modules, external flakes, consumer
modules alike. Per-service `TimeoutStartSec` overrides still win.

Why: the systemd default (90s) expires during system switches under I/O
contention — ExecStartPre legs (DNS-gate waits, DB heal, migrations) hang and
deploys die with exit code 4 (13 services hit it before this default existed).

## Consumption

```nix
imports = [inputs.nixos-modules.nixosModules.timeout-audit];
```

## Options

This module declares no options — the default is the contract.
