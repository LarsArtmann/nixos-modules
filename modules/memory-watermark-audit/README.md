# memory-watermark-audit

Eval-time assertion that a unit's `MemoryHigh` (soft throttle watermark)
never sits below 50% of its own `MemoryMax` (hard kill) when both are plain
byte values. The trap: `harden {}` derives the watermark from its own
`MemoryMax` argument, so merging a bigger ceiling outside the call wins the
limit while the watermark stays at the old derivation — the kernel
reclaim-thrashes forever with the unit `active (running)` and every liveness
check green (llama-chat 2026-10-08: 410M watermark under a 48G ceiling, 46k
throttle events).

Percent values, "infinity"/"max", high-only, and max-only units pass — they
are visible, different failure modes. Covers system units, user units, and
home-manager user services (owner-prefixed `user:unit` names).

Assertions are forced by `nix flake check`; a bare toplevel eval does not
check them.

## Consumption

```nix
imports = [inputs.nixos-modules.nixosModules.memory-watermark-audit];

# deliberate exceptions (every entry needs a justification comment at its
# definition site):
services.memory-watermark-audit.allowUnits = ["aggressive-reclaimer"];
```

## Options

| Option       | Type       | Default | Notes                                        |
| ------------ | ---------- | ------- | -------------------------------------------- |
| `allowUnits` | listOf str | `[]`    | deliberate sub-50% watermarks                |
