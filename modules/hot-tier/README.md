# hot-tier

Unsnapshotted fast-disk (BTRFS subvolume) mounts for always-churning
directories — journald logs, web-server access logs, anything whose writes
both ride the OS disk's IO storms and pin deleted bytes into snapshots
forever.

## Consumption

```nix
inputs.nixos-modules.url = "github:LarsArtmann/nixos-modules";

# in your NixOS config:
imports = [inputs.nixos-modules.nixosModules.hot-tier];

services.hot-tier = {
  enable = true;
  mounts = {
    journal = {
      device = "/dev/disk/by-label/fastdisk";
      subvol = "journal";
      mountPoint = "/var/log/journal";
      tmpfilesMode = "02755";
      tmpfilesUser = "root";
      tmpfilesGroup = "systemd-journal";
      services.systemd-journald = {}; # after + wants wiring only
    };
    caddy-logs = {
      device = "/dev/disk/by-label/fastdisk";
      subvol = "caddy-logs";
      mountPoint = "/var/log/caddy";
      tmpfilesMode = "0750";
      tmpfilesUser = "caddy";
      tmpfilesGroup = "caddy";
      services.caddy.dropLogsDirectory = true; # + `+`-chown ownership heal
    };
  };
};
```

## Contract (mutation-proven in `tests/negative/`)

- Mount options default to `nofail` + `x-systemd.device-timeout=5s`: a
  detached hot disk degrades to the shadow dir, never a stalled/dead boot.
- Every declared service gets `after` + `wants` (never requires) the mount
  unit — a failed mount job must not kill the service.
- `dropLogsDirectory` neutralizes upstream `*Directory=` settings (which
  systemd turns into implicit RequiresMountsFor, defeating the degradation)
  and adds a `+`-privileged ownership-heal chown at service start.
- `subvol=` is prepended automatically; the fs-options guard
  (`lib.mkFilesystem`) throws on cross-filesystem option contamination.

## Consumer-side by design

Subvolume creation + initial data copy (a migrate script BEFORE the first
deploy carrying the mount — fstab cannot create subvolumes), failure
routing, and health monitoring live at the delegation site.
