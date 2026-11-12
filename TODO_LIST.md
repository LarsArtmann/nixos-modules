<!-- TODO_LIST.md — living document. DONE items are REMOVED and logged in
     CHANGELOG.md. For long-term vision and unrefined ideas, use ROADMAP.md. -->

# TODO List

> Short-term, actionable, bounded work items, verified against the actual
> code. For long-term vision and unrefined ideas, use ROADMAP.md. Items are
> ranked by impact. Status is verified, not assumed.

## Status legend

| Status           | Meaning                                                     |
| ---------------- | ----------------------------------------------------------- |
| 🔴 `TODO`        | Not started. Needs doing.                                   |
| 🟡 `IN_PROGRESS` | Actively being worked on.                                   |
| 🔵 `BLOCKED`     | Cannot proceed, external dependency or decision needed.     |
| 🟢 `DONE`        | Completed. Remove from this list and log in `CHANGELOG.md`. |

## High Impact

| Task                                                                 | Status        | Impact | Effort | Evidence                                                                                                        |
| -------------------------------------------------------------------- | ------------- | ------ | ------ | --------------------------------------------------------------------------------------------------------------- |
| Align the FEATURES.md evidence standard                             | 🔴 `TODO`     | High   | 30min  | `serviceTypes` row is 🟡 for "no in-repo consumer or test" while other parity-proven helpers (mkPoolDirUnit, mkSqliteBackupUnit, …) are 🟢 on the same evidence class (`lib/README.md` parity list includes `serviceTypes`) — statuses must be a pure function of evidence class |
| Add negative mutation legs for the wifi-failover eval assertions     | 🔴 `TODO`     | High   | 1-2h   | `tests/negative/run.sh` carries only the `bootmirror` group; module assertions at `modules/wifi-failover/default.nix:103-122` (gateway-required, dual-wan conflict) have no mutation legs |
| Add in-repo eval tests for the lib's pure helpers                   | 🔴 `TODO`     | High   | 3-4h   | `flake.nix` checks have no lib leg; guards worth pinning: harden lifecycle-throw (`lib/systemd.nix:41-53`), MemoryHigh derivation (`lib/systemd.nix:69-99`), `extractPortLiterals` forms (`lib/default.nix`) — parity with SystemNix is proven at extraction only, nothing re-proves it as the fork evolves |

## Medium Impact

| Task                                                                | Status    | Impact | Effort | Evidence                                              |
| ------------------------------------------------------------------- | --------- | ------ | ------ | ----------------------------------------------------- |
| Fix stale GW-source comment in `watch.sh`                           | 🔴 `TODO` | Med    | 15min  | `modules/wifi-failover/watch.sh:26-27` says the unit injects GW from `config.networking.local.gateway` (SystemNix-era coupling); this repo injects from `services.wifi-failover.gateway` / `networking.defaultGateway` (`modules/wifi-failover/default.nix:37-44`). Coordinate with the SystemNix parity diff — the copies are forked-during-migration |
| Run the pure-eval checks on aarch64-linux too                       | 🔴 `TODO` | Med    | 30min  | `flake.nix` gates `boot-mirror-contract` + `module-list` behind `system == "x86_64-linux"`; both are pure eval and portable |
| Marker-stability pass over archived strikethroughs                  | 🔴 `TODO` | Med    | 15min  | `docs/status/archived/2026-11-12_docs-overhaul.md` was gated pre-move but no dprint pass + re-gate ran (annotate → check-rows → format → check-rows canon) |
| options.json render check per module                                | 🔴 `TODO` | Med    | 1-2h   | `flake.nix`'s `module-list` records module paths only; the "declared in" provenance claim (path-not-import rationale) is never mechanically proven |

## Low Impact

| Task                                                             | Status    | Impact | Effort | Evidence                                                                  |
| ---------------------------------------------------------------- | --------- | ------ | ------ | ------------------------------------------------------------------------- |
| Decide dprint's role: wire `dprint.json` into treefmt or drop it | 🔴 `TODO` | Low    | 30min  | `dprint.json` configures JSON/YAML/Markdown/Dockerfile but `treefmt.nix` enables only alejandra — nothing enforces dprint |
| Surface the negative harness as a flake app or devShell command  | 🔴 `TODO` | Low    | 30min  | `tests/negative/run.sh` is invoked by raw path only (`flake.nix` has no app; no devShell exists) |
| Force a fresh (non-cached) wifi-failover-vm run                   | 🔴 `TODO` | Low    | 15min  | This session's `nix flake check` green for `wifi-failover-vm` was store-substituted (inputs unchanged); a cache-busted rebuild re-proves the VM leg |
