# hot-dir-migrate

Relocates per-project session-DB directories (e.g. `~/projects/*/.crush`)
off the OS disk onto a dedicated hot disk, leaving symlinks behind — seeky
SQLite churn leaves the snapshot-pinned OS disk entirely.

## Consumption

```nix
inputs.nixos-modules.url = "github:LarsArtmann/nixos-modules";

# in your NixOS config:
imports = [inputs.nixos-modules.nixosModules.hot-dir-migrate];

services.hot-dir-migrate = {
  enable = true;
  # Historical unit names keep deploy restart blocks and audits stable:
  unitName = "crush-hot-db-migrate";
  dirName = ".crush";
  dbName = "crush.db";
  matchComm = "crush";
  projectsDir = "/home/lars/projects";
  mountPoint = "/mnt/hot";
  destName = "crush";
  ownerUser = "lars";
  dryRunEnvVar = "CRUSH_HOT_DB_DRY_RUN"; # runbook compatibility
};
```

## Contract (VM-tested + mutation-proven)

- Timer-pulled (`OnBootSec` + daily `Persistent` catch-up), never
  boot-gated — the migrate run must not delay the login screen.
- Per-project liveness guard: a process with comm `matchComm` holding an
  fd/cwd under a project's session dir blocks ONLY that project (a blanket
  name-skip starves convergence on busy hosts).
- Fresh-write window (`freshWriteMinutes`), depth-cap WARN tripwire,
  empty-target auto-heal vs populated-target manual-merge refusal, dry-run
  rehearsal via the configured env var, single-flight flock, non-zero exit
  on per-dir failures.
- Sandbox: `ProtectHome=read-only` (NOT true — systemd maps true to
  inaccessible-and-EMPTY /home and every find ENOENTs), ReadWritePaths on
  the MOUNT ROOT (226/NAMESPACE class), CAP_CHOWN/FOWNER/DAC_OVERRIDE for
  the rename + symlink swap, background IO tier.

## Consumer-side by design

The hot-disk mount itself (see the `hot-tier` module or hardware config),
OnFailure routing, and health monitoring live at the delegation site.
