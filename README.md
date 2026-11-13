# nixos-modules

LarsArtmann NixOS module collection — production modules (wifi failover, boot
mirror, hot-disk tiering + migration), the systemd hardening lib, and the
mutation-proven contract checks — extracted from (and consumed by)
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

- [`wifi-failover`](modules/wifi-failover/) — carrier-based standby failover
  from a static-IP ethernet interface to a NetworkManager WiFi fallback. The
  kernel keeps static metric-0 default routes on carrier loss; the daemon
  evicts them and restores the primary route when the cable returns.
  VM-tested (5 scenarios).
- [`boot-mirror`](modules/boot-mirror/) — verified byte-mirror of a
  systemd-boot primary ESP on a 2nd boot disk: reverse-propagates loader-owned
  boot-counting state before the forward rsync, fails loudly on any drift,
  and re-triggers on every loader-entries change. Eval-contract-tested.
- [`hot-tier`](modules/hot-tier/) — unsnapshotted fast-disk subvolume mounts
  for always-churning directories (journald logs, access logs): nofail +
  bounded device-timeout degradation, after/wants (never requires) service
  wiring, `*Directory=` neutralization + `+`-privileged ownership heal.
  VM-tested on both the healthy and the detached-disk degraded paths.
- [`hot-dir-migrate`](modules/hot-dir-migrate/) — relocates per-project
  session-DB directories onto a hot disk leaving symlinks behind: per-project
  live-writer guard (comm + fd/cwd under /proc), fresh-write window, depth
  tripwire, empty-target auto-heal, dry-run rehearsal, timer-pulled never
  boot-gated. VM-tested across the full behavior matrix.

Each module dir carries its own README with the consumption snippet and
option notes.

## Development

```sh
nix fmt          # treefmt: alejandra + deadnix + statix (Nix files)
nix flake check  # formatting, module introspection, lib + module contracts,
                 # options.json provenance, VM tests (x86_64)
nix run .#negative-tests   # mutation harness (repo root; CASES= filter)
```

Contributions follow the [Design rules](#design-rules) above; every module
change lands with its contract check and (where behavior is runtime-visible)
VM + negative-mutation legs.

Version bumps: wrap new CHANGELOG entries under `## [x.y.z] - date`, commit,
tag annotated (`git tag -a vx.y.z`), push `--follow-tags`, then re-point
SystemNix's flake input at the tag.

## License

[MIT](LICENSE) © Lars Artmann
