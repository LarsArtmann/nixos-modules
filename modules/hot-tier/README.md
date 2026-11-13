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

## Options

| Option                                       | Type     | Default        | Notes                                    |
| -------------------------------------------- | -------- | -------------- | ---------------------------------------- |
| `enable`                                     | bool     | `false`        | inert until enabled                      |
| `mounts`                                     | attrs    | `{}`           | one hot-disk mount instance per attr     |
| `mounts.<name>.device`                       | str      | (required)     | e.g. `/dev/disk/by-label/hot`            |
| `mounts.<name>.subvol`                       | str      | (required)     | btrfs subvolume on the hot disk          |
| `mounts.<name>.mountPoint`                   | str      | (required)     | where the subvol mounts                  |
| `mounts.<name>.fsType`                       | str      | `"btrfs"`      |                                          |
| `mounts.<name>.mountOptions`                 | list of str | `["noatime" "nodiscard" "space_cache=v2" "nofail" "x-systemd.device-timeout=5s"]` | degradation contract |
| `mounts.<name>.tmpfilesMode`                 | str      | `"0755"`       | shadow-dir mode                          |
| `mounts.<name>.tmpfilesUser`                 | str      | `"root"`       | shadow-dir owner                         |
| `mounts.<name>.tmpfilesGroup`                | str      | `"root"`       | shadow-dir group                         |
| `mounts.<name>.services`                     | attrs    | `{}`           | services riding this mount               |
| `mounts.<name>.services.<name>.dropLogsDirectory` | bool | `false`      | neutralize upstream `LogsDirectory`      |
| `mounts.<name>.services.<name>.healOwnership` | bool    | `true`         | the `+`-privileged chown heal            |

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
