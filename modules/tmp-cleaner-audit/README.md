# tmp-cleaner-audit

Eval-time assertion: no unit may glob-delete `/tmp/*` inline without excluding
`systemd-private-*` — the PrivateTmp backing dirs. Deleting one unlinks the
bind-mount source and every file creation inside the unit's private `/tmp`
then fails ENOENT, self-perpetuating (idle services never refresh their
private tmp). Live incident: forgejo mirrors dead 12 days, ~16.9k ENOENT
lines across 4 services (2026-08-18..30).

Catches the INLINE variant (text visible at eval time: Exec\*/script options).
Store-path cleaner scripts are invisible here and need their own
self-assertions + behavioral tests consumer-side.

## Consumption

```nix
imports = [inputs.nixos-modules.nixosModules.tmp-cleaner-audit];
```

## Options

This module declares no options — the guard is unconditional.
