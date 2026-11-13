# start-limit-audit

Eval-time assertion: `StartLimitBurst`/`StartLimitIntervalSec` must never live
inside `serviceConfig`. systemd 261+ honors them only in the `[Unit]` section —
placed in `[Service]` they are silently ignored, so a `Restart=on-failure`
service restarts infinitely with no rate limit while its author believes one
exists.

## Consumption

```nix
imports = [inputs.nixos-modules.nixosModules.start-limit-audit];
```

## Options

This module declares no options — the guard is unconditional.
