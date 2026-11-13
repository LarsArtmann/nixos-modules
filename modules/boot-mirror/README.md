# boot-mirror

Verified byte-mirror of a systemd-boot primary ESP onto a 2nd boot disk.

The `boot-mirror-sync` oneshot keeps the mirror ESP tree-identical to the
managed ESP (`diff -r` gate — drift fails the unit loudly instead of arming a
stale-boot trap), survives loader-owned boot-counting state (entry renames are
reverse-propagated from the booted ESP before the forward rsync), and
re-triggers on ANY loader-entries change via a path unit — covering raw
`switch-to-configuration` gen-installs, not just deploy flows.

## Consumption

```nix
{
  inputs.boot-mirror.url = "github:LarsArtmann/nixos-modules";
  # keep the consumer's nixpkgs: inputs.boot-mirror.inputs.nixpkgs.follows = "nixpkgs";
}

{
  imports = [ inputs.boot-mirror.nixosModules.boot-mirror ];
  services.boot-mirror = {
    enable = true;
    device = "/dev/disk/by-uuid/XXXX-XXXX"; # the mirror ESP (by-uuid/by-id!)
    # mountPoint = "/boot-mirror";           # defaults shown
    # sourceEsp = "/boot";
    # fsType = "vfat";
    # mountOptions = [ "fmask=0077" "dmask=0077" "nofail" ];
  };
}
```

Deliberately NOT automatic: the EFI boot entry / BootOrder flip (making the
mirror the firmware's first choice) is a one-time operator decision — reboots
are deliberate events; NVRAM order must not fight the operator.

Failure routing (`onFailure` units) is built in; service-registry monitoring
wiring is consumer-side (layer it at the delegation site).

## Options

| Option         | Type           | Default                                | Notes                         |
| -------------- | -------------- | -------------------------------------- | ----------------------------- |
| `enable`       | bool           | `false`                                | inert until enabled           |
| `device`       | null or string | `null`                                 | mirror ESP; null = module off |
| `sourceEsp`    | str            | `"/boot"`                              | watched source ESP            |
| `mountPoint`   | str            | `"/boot-mirror"`                       | mirror mountpoint             |
| `fsType`       | str            | `"vfat"`                               | ESP filesystem                |
| `mountOptions` | list of str    | `["fmask=0077" "dmask=0077" "nofail"]` | nofail is contract-pinned     |

## Contract (eval-pinned)

- path unit watches `<sourceEsp>/loader/entries` → `boot-mirror-sync.service`
- service condition-skips when the mirror is unmounted (wants-not-requires)
- the mirror mount stays `nofail`
- `ProtectSystem = false` is load-bearing (RO bind of the read source breaks
  the counter reverse-propagation renames — EROFS class)
- background IO tier (BE/6)

Violating any of these fails `nix flake check` (the module self-asserts) and
the mutation legs in `tests/negative/` prove the assertions bite.
