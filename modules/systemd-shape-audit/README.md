# systemd-shape-audit

Eval-time audit for invalid or racy systemd unit SHAPES that systemd either
refuses to load or accepts while silently arming a failure cascade. Ten bug
classes, each with live incident history (see the module header for the full
narratives): oneshot+invalid-Restart, timer+Restart≠no, PathExists-triggered
path units, literal `$HOME` in user-unit Exec lines, script options nested in
serviceConfig, shared RuntimeDirectory, unbounded boot-blocking oneshots,
OnFailure in serviceConfig, [Service] keys in unitConfig, and `is-active`
probes against oneshots without RemainAfterExit.

Assertions are forced by `nix flake check`; a bare toplevel eval does not
check them.

## Consumption

```nix
imports = [inputs.nixos-modules.nixosModules.systemd-shape-audit];

# deliberate exceptions (every entry needs a justification comment at its
# definition site):
services.systemd-shape-audit.allowTimerRestart = ["racy-sync"];
```

## Options

| Option                       | Type       | Default | Notes                                               |
| ---------------------------- | ---------- | ------- | --------------------------------------------------- |
| `allowTimerRestart`          | listOf str | `[]`    | timer-driven units whose Restart≠no is deliberate   |
| `allowUnboundedOneshot`      | listOf str | `[]`    | boot-blocking oneshots with unbounded timeout       |
| `allowUnitConfigServiceKeys` | listOf str | `[]`    | `"<unit>:<Key>"` deliberate [Service]-in-unitConfig |
| `allowOneshotIsactiveProbe`  | listOf str | `[]`    | `"<prober>:<target>"` deliberate lying probes       |
