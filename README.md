# nixos-modules

LarsArtmann NixOS module collection — reusable pattern modules, eval-time audit
gates, and the systemd hardening lib extracted from (and consumed by)
[SystemNix](https://github.com/LarsArtmann/SystemNix).

## Design rules

- Every module is inert until `services.<name>.enable = true`.
- Modules never change configuration without setting an option.
- `nixosModules.<name>` entries are **paths**, not import-applied modules —
  declaration provenance survives into `options.json`.
- Collection code uses plain / `mkDefault` priorities only; `mkForce` is a
  consumer right.
- Breaking option changes go through `modules/_renames.nix`
  (`mkRenamedOptionModule` / `mkRemovedOptionModule` with a reason string).

## Usage

```nix
{
  inputs = {
    nixos-modules.url = "github:LarsArtmann/nixos-modules";
    nixos-modules.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { nixpkgs, nixos-modules, ... }: {
    nixosConfigurations.example = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        nixos-modules.nixosModules.wifi-failover
      ];
    };
  };
}
```

## Modules

(populated as modules land; each module dir carries its own README with the
consumption snippet and option notes)

## Development

```sh
nix fmt          # treefmt + alejandra
nix flake check  # formatting gate, module-path introspection, VM tests
```
