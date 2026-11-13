# mount-gating-audit

Eval-time audit for `ReadWritePaths` entries under `/mnt/` that lack mount
gating — the 226/NAMESPACE abort and root-fs shadow-directory contamination
class (cv-backup 2026-08-31: nine days of writes into a silent shadow copy),
plus the dash-prefix leg (`-`-prefixed paths under any declared mount
resolve ENODEV when the mount's unit is FAILED and abort the whole unit's
namespace setup — buildcache-gc 2026-11-03).

Sanctioned gating forms: `unitConfig.RequiresMountsFor` (fails loudly on a
detached DAS) or `serviceConfig.ConditionPathIsMountPoint` (skips cleanly).
`ConditionPathIsDirectory` does NOT count — a shadow dir satisfies it.

Assertions are forced by `nix flake check`; a bare toplevel eval does not
check them.

## Consumption

```nix
imports = [inputs.nixos-modules.nixosModules.mount-gating-audit];

# deliberate exceptions (every entry needs a justification comment at its
# definition site):
services.mount-gating-audit.allowUnits = ["shadow-tolerant-unit"];
```

## Options

| Option       | Type       | Default | Notes                                        |
| ------------ | ---------- | ------- | -------------------------------------------- |
| `allowUnits` | listOf str | `[]`    | units exempt from both gating/dash detection |
