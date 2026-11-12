# AGENTS.md

NixOS module collection: reusable pattern modules (`modules/`), a three-legged
testing model (`tests/`), and the systemd hardening lib (`lib/`) extracted
from — and consumed by — [SystemNix](https://github.com/LarsArtmann/SystemNix).
This repo is a flake library: it builds no packages, exposes `nixosModules.*`,
`lib`, `checks`, and a `formatter`. There is no application code and no CI
beyond the flake checks.

## Commands

```sh
nix fmt                       # treefmt + alejandra (Nix files only)
nix flake check               # formatting + module-path assert + all checks
nix build .#checks.x86_64-linux.boot-mirror-contract  # one check, no VM
nix build .#checks.x86_64-linux.wifi-failover-vm      # the VM test alone
bash tests/negative/run.sh    # mutation tests — NOT part of flake check
CASES=bootmirror bash tests/negative/run.sh  # filter one case group
KEEP=1 bash tests/negative/run.sh            # keep mutated copy for triage
```

- `nix flake check` on x86_64-linux builds the wifi-failover VM test — slow.
  Build individual checks when iterating.
- aarch64-linux carries the formatting check only (VM + contract checks are
  x86_64-only).
- `dprint.json` configures dprint for JSON/YAML/Markdown/Dockerfile, but the
  enforced formatting gate (`nix fmt` / `checks.formatting`) is
  treefmt/alejandra over Nix files only.

## Flake surface

- `nixosModules.<name>` — auto-discovered from every `modules/<dir>` holding
  a `default.nix`; `_`-prefixed dirs are helper space and are skipped.
  Entries are PATHS, never import-applied modules: import-application strips
  the "declared in" provenance from `options.json`. An `assert` in flake.nix
  fails `nix flake check` the moment an import-applied entry appears.
- `lib` — `import ./lib lib`: the portable systemd hardening spine (depends
  on nixpkgs lib ONLY). Fleet-bound helpers (ports registry, gatus, OIDC/DNS
  gates, rocm, filesystems) deliberately stay SystemNix-side — the split
  contract lives in `lib/README.md`.
- `checks` — per-module tests plus `module-list`, an introspection check that
  forces evaluation of every discovered module path; surface changes show up
  as a check-input diff.

## Relationship to SystemNix (forked-during-migration)

SystemNix keeps local copies of the lib helpers while its consumers migrate
to these imports; the final re-point happens when the last consumer moves.
Consequences when editing `lib/`:

- Parity between the copies matters. Do not "improve" one side silently —
  parity diffs and the negative-test legs guard value drift.
- Consumers pin by rev, so shipped option aliases are effectively permanent.

## Module conventions (enforced, not stylistic)

- Every module is inert until `services.<name>.enable = true` and never
  changes configuration without setting an option.
- Collection code uses plain / `mkDefault` priorities only; `mkForce` is a
  consumer right. (Deliberate in-repo exception: `serviceDefaults` — lib, not
  a module — uses `mkForce` internally to beat nixpkgs defaults.)
- Breaking option changes go through `modules/_renames.nix`
  (`mkRenamedOptionModule` / `mkRemovedOptionModule` plus a reason string);
  entries are kept forever.
- Fleet integrations (service registry entries, monitoring wiring,
  `onFailure` template units) are consumer-side. An
  `options ? services.<registry>` guard inside the module cannot survive the
  enclosing `mkIf cfg.enable` — layer integrations at the consumer's
  delegation site.
- Module shape: `modules/<name>/default.nix` plus a README with the
  consumption snippet, plus colocated scripts (e.g. `watch.sh`) pulled into
  `writeShellApplication` via `builtins.readFile`. Header comments carry the
  problem/solution narrative — preserve them when editing.
- Contracts a module relies on are SELF-ASSERTED at eval time (boot-mirror
  asserts its own path-unit shape, mount condition, nofail, IO tier), so a
  regression fails `nix flake check` instead of surfacing as a stale boot.

## systemd unit patterns (lib)

Units compose via `lib.mkMerge` of positionally distinct fragments:

```nix
serviceConfig = lib.mkMerge [
  { Type = "oneshot"; ExecStart = …; }  # lifecycle: OUTSIDE harden
  (harden { MemoryMax = "1G"; })
  (serviceOneshotDefaults {})
  ioTier.background
];
```

- `harden {}` / `hardenUser` — the hardening fragment. It THROWS at eval if
  given lifecycle keys (`ExecStart*`, `Type`, `Restart`,
  `RemainAfterExit`, …); merge those outside via `mkMerge`. Unknown keys pass
  through verbatim (mind capitalisation: `MemoryMax`, not `memoryMax`).
- Pass `MemoryMax` INTO `harden`, never merge it separately: the default
  `MemoryHigh` (80%) derives from the `MemoryMax` ARGUMENT, and a separately
  merged MemoryMax leaves MemoryHigh pinned to the 512M default. Systemd
  memory percentages resolve against TOTAL RAM, not MemoryMax.
- `serviceDefaults` (Restart=always, mkForce) is for long-running daemons and
  CRASHES `Type=oneshot` units — use `serviceOneshotDefaults` (Restart=no,
  5min TimeoutStartSec floor) for oneshots. The `*User` variants drop
  mkForce for Home Manager units.
- `onFailure` / `onFailureP0` reference `notify-failure@%n.service` template
  units the CONSUMER must provide.
- One `harden {}` call per unit when `CapabilityBoundingSet` is in play —
  two plain strings cannot merge.
- Unit generators (`mkPoolDirUnit`, `mkSqliteBackupUnit`,
  `mkMetricTextfileCollector`) return `{ services.<name>; timers.<name>; }`
  for caller-side `systemd = mk… { … };`. Their invariants are documented in
  `lib/default.nix` comments — do not relax them at call sites.
- `unitExecText` / `extractPortLiterals` are the shared scan surface for
  consumer-side eval audits (port registry, gatus coverage) — a new Exec key
  or Environment form added there lands in both audits at once.

## Testing model (three legs)

1. **Eval-contract checks** (`tests/boot-mirror.nix` →
   `checks.x86_64-linux.boot-mirror-contract`): eval a fixture host with the
   module enabled, force `config.system.build.toplevel.drvPath` (full merge;
   module assertions throw here), then pin observable unit shapes with
   `lib.throwIfNot` chains. No VM needed when the contract is eval-observable.
2. **VM tests** (`tests/wifi-failover.nix` → `wifi-failover-vm`):
   `runNixOSTest` exercising the REAL deployed ExecStart binary; a veth
   PEER's admin state simulates cable carrier (peer down = NO-CARRIER with
   the route still pinned — the exact production bug shape).
3. **Negative mutation tests** (`tests/negative/run.sh`): copy the
   git-tracked tree WITHOUT `.git`, apply ONE sed mutation per case, build
   the check from the copy with `nix build --impure`, and require the
   failure to carry the CONTRACT MARKER (an unrelated eval error does not
   count). Green controls prove the harness bites. Run after touching module
   assertions; not wired into `nix flake check`.

Cross-file contracts: the wifi-failover VM test asserts on journal markers
(`FAILOVER: carrier lost`, `RESTORE: carrier back`) and the `DEBUG_POLL=1`
environment override — renaming log lines in `watch.sh` breaks the test.

## Gotchas

- `tests/negative/run.sh` copies only git-TRACKED files (`git ls-files`) —
  untracked new files silently miss the mutation copies.
- `tests/*.nix` are functions with two signatures: VM tests take `{pkgs}`
  (wifi-failover ignores it as `_`) — wifi-failover, hot-tier-journal,
  hot-tier-caddy, hot-dir-migrate; eval-contract tests take
  `{lib, pkgs, module}` — boot-mirror, hot-tier-contract,
  hot-dir-migrate-contract. All 7 wired in flake.nix.
- Unit names with dashes: a literal `after = ["boot-mirror.mount"]` names a
  nonexistent unit (systemd escapes dashes: `boot\x2dmirror.mount`). Use
  `unitConfig.RequiresMountsFor`, which implies Requires=+After= on the real
  mount (see boot-mirror comments).
- `harden {}` defaults an empty `CapabilityBoundingSet`; anything needing
  caps (e.g. `chown`) must pass them explicitly.
- CHANGELOG.md follows Keep a Changelog — add an entry for notable changes.
- SECURITY.md: vulnerabilities go through GitHub private security advisories,
  never public issues.

## High-value references

- `lib/README.md` — the split contract: what moved here vs stayed SystemNix,
  and the forked-during-migration kill path.
- `modules/_renames.nix` — migration-ledger policy for breaking changes.
- `modules/<name>/README.md` — per-module consumption snippet + pinned
  contracts.
- `lib/port-guard.nix` header — the berth-pattern port handoff contract.
- Living docs: `FEATURES.md` (feature inventory), `TODO_LIST.md` (open work),
  `ROADMAP.md` (direction), `docs/DOMAIN_LANGUAGE.md` (glossary).
