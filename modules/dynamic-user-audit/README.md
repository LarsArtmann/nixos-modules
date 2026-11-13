# dynamic-user-audit

Eval-time assertion that sops secrets and templates owned by a DynamicUser
service name are root-owned. DynamicUser creates the service user at
startup — it does not exist when sops-nix decrypts, so a non-root owner
fails with "failed to lookup user" and blocks ALL secrets atomically (live
incidents: Gatus, crush-daily, Attic).

Auto-discovers every `DynamicUser=true` service at eval time (nixpkgs
upstream modules included) and cross-references `config.sops.secrets` /
`config.sops.templates` ownership. Reads sops through `builtins.tryEval`:
silent on hosts without sops-nix.

Assertions are forced by `nix flake check`; a bare toplevel eval does not
check them.

## Consumption

```nix
imports = [inputs.nixos-modules.nixosModules.dynamic-user-audit];
```

## Options

None — the invariant is absolute; there is no legitimate non-root owner for
a DynamicUser's secret.
