# gatus-coverage-audit

Eval-time audit enforcing monitoring coverage, in both directions over the
resolved config:

- **A — uncovered listeners**: every registered port that live unit text
  actually uses must appear in at least one gatus endpoint URL — a service
  serving a port nothing watches fails eval (silent failures are
  unacceptable). Enforced only when `services.gatus` is enabled on the host.
- **B — monitor-side drift**: every loopback gatus URL must use a
  registered port (external upstreams like `tcp://dot.mullvad.net:853` are
  exempt by design).

Shares the port-registry-audit scan surface (`unitExecText` +
`extractPortLiterals`) and the same consumer-fed registry. Sanctioned
exception classes: prohibited-to-probe sockets (probes hold connection
slots real clients need) and vHost-monitored backends (the check rides the
reverse proxy, so the backend port never appears in a URL) — both go
through `allowPorts` with a justification comment.

## Consumption

```nix
imports = [inputs.nixos-modules.nixosModules.gatus-coverage-audit];

services.gatus-coverage-audit = {
  enable = true;
  registry = import ./ports.nix; # same map as port-registry-audit
};
```

## Options

| Option       | Type          | Default | Notes                                          |
| ------------ | ------------- | ------- | ---------------------------------------------- |
| `enable`     | bool          | `false` | inert until enabled                            |
| `registry`   | attrs of port | `{}`    | same consumer map as port-registry-audit       |
| `allowPorts` | list of port  | `[]`    | justified exemptions; comment each where set   |

## Contract (mutation-proven in `tests/negative/`)

- An in-use registered port with no covering gatus URL fails eval, naming
  the port and its owning units
- A loopback gatus URL on an unregistered port fails eval
- `allowPorts` is the sanctioned escape for both directions
