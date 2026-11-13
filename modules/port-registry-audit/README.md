# port-registry-audit

Eval-time audit enforcing the "never hardcode localhost:PORT" rule: every
TCP port literal found in systemd unit `Exec*`/`Environment` text must be a
value from the consumer's registry, and no two registry names may claim the
same port. Both halves fail eval naming the offender unit/ports — the
"missing config" port-collision class dies at eval time instead of as a
runtime `EADDRINUSE` or a forgotten port map entry.

The registry lives consumer-side (the collection never hardcodes fleet
ports): SystemNix feeds its `lib/ports.nix` into the `registry` option.

## Consumption

```nix
imports = [inputs.nixos-modules.nixosModules.port-registry-audit];

services.port-registry-audit = {
  enable = true;
  registry = import ./ports.nix; # consumer's name -> port map
};
```

## Options

| Option       | Type          | Default | Notes                                              |
| ------------ | ------------- | ------- | -------------------------------------------------- |
| `enable`     | bool          | `false` | inert until enabled                                |
| `registry`   | attrs of port | `{}`    | consumer's name -> port map; collision-checked     |
| `allowPorts` | list of port  | `[]`    | justified exemptions; comment each where it is set |

## Contract (mutation-proven in `tests/negative/`)

- Unregistered port literal in any unit's Exec text fails eval, naming unit
  and port
- Registry collision (two names, one port) fails eval, naming both
- `allowPorts` is the sanctioned escape (upstream-owned ports, the
  word:NNN false-positive class)
