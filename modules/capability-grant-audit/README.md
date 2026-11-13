# capability-grant-audit

Eval-time audit for capability-grant confusion on non-root units:
`CapabilityBoundingSet` only LIMITS which caps may exist — for a non-root
`User=`/`DynamicUser` unit, only `AmbientCapabilities` GRANTS them. An
ungranted DAC-class bounding entry is dead weight and the service hits
EACCES where its author expected access while `/health` stays 200
(geometrikks 2026-09-29→10-07: zero ingested caddy events).

Flags DAC-class file-access caps (`CAP_DAC_READ_SEARCH`,
`CAP_DAC_OVERRIDE`, `CAP_FOWNER`, `CAP_CHOWN`, `CAP_FSETID`) listed in the
bounding set but not fully covered by the ambient grant. Non-DAC caps and
root/User-unset units are not flagged.

Assertions are forced by `nix flake check`; a bare toplevel eval does not
check them.

## Consumption

```nix
imports = [inputs.nixos-modules.nixosModules.capability-grant-audit];

# deliberate exceptions (every entry needs a justification comment at its
# definition site — bounding kept as documentation / future root flip):
services.capability-grant-audit.allow = ["doc-only-caps-unit"];
```

## Options

| Option  | Type       | Default | Notes                                    |
| ------- | ---------- | ------- | ---------------------------------------- |
| `allow` | listOf str | `[]`    | deliberate ungranted DAC bounding entries |
