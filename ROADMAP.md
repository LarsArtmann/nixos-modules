<!-- ROADMAP.md — LONG-TERM DIRECTION and raw ideas.
     No bounded tasks, no status indicators, no completed milestones. -->

# Roadmap

> Long-term direction and raw ideas. Items here are NOT actionable tasks.
> When an idea is refined into bounded work, it moves to TODO_LIST.md.

## Themes

### 1. Finish the SystemNix migration (the kill)

The lib is forked-during-migration: SystemNix keeps local copies while its
consumers move to these imports. Direction: shrink the fork to zero.

Raw ideas:

- Migrate the remaining SystemNix lib consumers to collection imports,
  deleting SystemNix's local copies helper-by-helper
- A standing parity diff between this lib and SystemNix's forked copies that
  runs until the last consumer moves (today parity is proven at extraction
  time only)
- Re-point SystemNix's `lib/default.nix` at this flake input — the final kill
  documented in `lib/README.md`

### 2. Grow the pattern-module collection

Direction: every proven SystemNix pattern module that is fleet-agnostic
becomes reusable here, keeping the inert-until-enable shape and
consumer-side integrations.

Raw ideas:

- Migrate `dual-wan` (the probe-based ECMP+MPTCP partner that wifi-failover's
  conflict assertion names) once its consumer story is settled
- Extract further proven pattern modules on demand — collection grows with
  real consumers, not speculatively

### 3. Ship eval-time audit gates as modules

The collection charter names "eval-time audit gates" (flake description,
README) but no audit module exists yet — only the scan surface
(`unitExecText` / `extractPortLiterals`) ships in `lib`.

Raw ideas:

- Port-registry audit (port-literal extraction across unit Exec/Environment
  vs a declared registry) as a consumable module
- Gatus-coverage audit (declared checks vs listening services) on the same
  shared scan surface, so both audits cannot drift apart

## Non-goals

Things we are deliberately NOT pursuing and why:

- **Fleet-bound helpers in this collection:** ports registry, gatus helpers,
  OIDC/DNS gates, rocm, filesystems, buildcache stay SystemNix-side — the
  split contract (`lib/README.md`) keeps this lib portable
  (nixpkgs-lib-only).
- **`mkForce` in collection code:** overriding is a consumer right; the
  collection speaks plain / `mkDefault` priorities only.
- **A general-purpose community module registry:** this collection carries
  LarsArtmann fleet patterns, not third-party submissions.
