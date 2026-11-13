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
- boot-mirror contract single-sourcing — PARKED 2026-11-13 (SUPERB T10
  spike verdict): the "duplication" is deliberate three-layer witnessing
  (module self-assertions = internal consistency; the test's hardcoded
  throwIfNot pins = independent external witness; README = the human
  contract). Collapsing them into one exported source would make the
  witness read its truth from the thing it watches — the phantom-green
  class this repo's own hot-dir-migrate test header warns about. Layer
  drift stays guarded by the negative-harness markers (each layer bites);
  re-open only if a real cross-layer drift incident occurs. The options-
  TABLE drift guard (README options vs options-json) remains separate and
  viable — see its own bullet.
- Docs automation: options tables in module READMEs are now GUARDED
  (`checks.*.options-readme-drift`, shipped 2026-11-13 as SUPERB T11 — the
  tables themselves were added then, rendered from options-json); the
  remaining idea is auto-GENERATING them wholesale
- boot-mirror runtime VM leg — the sync script's bootctl/rsync/diff path has
  never executed inside this repo's test net
- Renovate app for flake inputs (the nixpkgs unstable pin) — owner opt-in:
  Dependabot covers github-actions since 2026-11-13 (T8); flake.lock stays
  manual (`nix flake update` + full gates) until the app is installed
- Docs automation: per-module option tables generated from the options-json
  check output; FEATURES infra table split shipped vs pending; the lib/README
  fork ledger with per-helper SystemNix consumer counts, auto-generated
- A lint/review rule against unparenthesized selects over applications
  (`f x y .attr` — the session's phantom-falsehood class), e.g. a statix
  custom rule

### 3. Ship eval-time audit gates as modules

The original collection charter named eval-time audit gates; the flake
description and README now ship the honest current surface instead, but the
audit-gate goal stands — only the scan surface (`unitExecText` /
`extractPortLiterals`, in-repo-tested via `checks.*.lib-eval`) ships in
`lib` today.

Raw ideas:

- Port-registry audit (port-literal extraction across unit Exec/Environment
  vs a declared registry) as a consumable module
- Gatus-coverage audit (declared checks vs listening services) on the same
  shared scan surface, so both audits cannot drift apart

## Non-goals

Things we are deliberately NOT pursuing and why:

- **Fleet-bound helpers in this collection:** ports registry, gatus helpers,
  OIDC/DNS gates, rocm, buildcache stay SystemNix-side — the
  split contract (`lib/README.md`) keeps this lib portable
  (nixpkgs-lib-only). (`mkFilesystem` moved INTO the collection 2026-11-12 —
  the filesystems guard is fleet-agnostic; SystemNix keeps a forked copy.)
- **`mkForce` in collection code:** overriding is a consumer right; the
  collection speaks plain / `mkDefault` priorities only.
- **A general-purpose community module registry:** this collection carries
  LarsArtmann fleet patterns, not third-party submissions.
