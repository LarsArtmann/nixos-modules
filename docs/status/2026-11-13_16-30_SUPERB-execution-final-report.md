# SUPERB plan execution — FINAL report (T1–T17 closed)

Date: 2026-11-13 16:30 CET · Plan: `docs/planning/2026-11-13_01-19_SUPERB-release-hardening-fleet-bridge.md`
Prior living snapshots: `archived/2026-11-13_00-58_*` (v0.1.0 close-out) and
`archived/2026-11-13_08-33_*` (midpoint; superseded by this report — the
midpoint's open items are all resolved below).

## a) FULLY DONE (verified this session, with the gate that proves it)

1. **T12 — boot-mirror runtime VM leg.** `tests/boot-mirror-vm.nix` →
   `checks.x86_64-linux.boot-mirror-vm`, 4 scenarios over the production sync
   script (full sync + diff gate, counter reverse-propagation, blessing
   convergence, degradation, ro-mirror loud failure). Green locally and on
   the runner: CI run [43447887478](https://github.com/LarsArtmann/nixos-modules/actions/runs/43447887478)
   SUCCESS. Harness `vm-degradation-unpinned` leg proves the runtime pin
   bites (bootmirror group 6/6).
2. **T13 — dual-wan dropped with evidence.** RETIRED-STACK banner on
   SystemNix's mptcp-endpoint-manager.sh (2026-09-16) + `dual-wan.enable =
   false` fleet-side; verdict in ROADMAP. (Question g1 answered by evidence,
   not preference: nothing consumes the stack.)
3. **T14 — port-registry-audit module.** Consumer-side `registry` option +
   membership AND collision assertion halves + `allowPorts` escape;
   eval-contract pins 6 host fixtures (incl. the word:NNN class staying
   DETECTED and inert-until-enable); `portregistry` harness group 5/5.
4. **T15 — gatus-coverage-audit module.** Same registry surface, class A
   (uncovered listeners, naming port + owners) + class B (loopback URL
   registry drift), structural external-upstream exemption, gatus-gated;
   contract proved against nixpkgs' REAL gatus module; `gatuscoverage`
   group 4/4.
5. **T15b — SystemNix bridge landed same day.** Their lock bumped to
   collection 73462d6, both delegation layers live (import + enable +
   registry from lib/ports.nix), 4 plain-import test sites converted, full
   `nix flake check --no-build` green, pushed (8c108bdef).
6. **T16 — select-parenthesization lint parked with evidence.** statix has
   no custom-rule API (fixed W01–W23, CLI-verified); the `f x.y` misparse
   is invisible post-parse; the lexical `[a b]` shape is idiomatic (3 FP
   hits in-repo immediately). Verdict + upstream-rule sketch in ROADMAP.
7. **Full verification sweep.** `nix flake check --no-build --all-systems`
   green; full negative harness 48/48 (13 groups, first full run since the
   a1a wave); `statix check .` clean (3 repeated-key fixes: treefmt.nix,
   hot-dir-migrate.nix, a1a's shape-audit contract); docs-gates 5/5; docs
   updated truthfully (CHANGELOG, FEATURES, AGENTS gotchas, ROADMAP
   verdicts, DOMAIN_LANGUAGE +4 terms, module READMEs, TODO_LIST rewritten
   as the harvested backlog).
8. **Earlier-session carry-overs re-verified:** SystemNix cross-repo fix
   commit 592592293 landed+pushed; origin/master restored green after the
   broken boot-mirror-vm wiring (fix-forward, g2).

## b) PARTIALLY DONE

None — every plan task is closed (done, or dropped/parked with a recorded
verdict + evidence).

## c) NOT STARTED

None from the plan. Backlog beyond the plan lives in TODO_LIST (9 rows: 7
TODO, 2 BLOCKED-on-owner).

## d) TOTALLY FUCKED UP (honest register)

1. **CI ran red ~6h on master** (the daemon pushed my eval-broken
   boot-mirror-vm wiring before the build verdict). The lesson held — never
   wire before green — but the daemon race beat me once more; the recovery
   was fix-forward in one session block.
2. **Four VM-test debugging cycles burned on semantics I theorized instead
   of measured**: (a) assumed the module's fileSystems survives the VM
   merge (it never does — mkVMOverride); (b) assumed `umount` ⇒ unit
   inactive (stacked mounts + monitor lag); (c) assumed dependency failure
   shows as Result=dependency on the service (it is the JOB result; the
   mount carries exit-code); (d) shipped an over-escaped `\x2d` unit name
   twice (4 backslashes → wrong name → phantom waits passing instantly).
   All four are now AGENTS gotchas; the fix pattern each time was "stop
   theorizing, instrument, read the journal."
3. **My first CHANGELOG edit for this wave accidentally REPLACED the
   SECURITY.md bullet in AGENTS** (edit composed as replace, not insert);
   caught within minutes by grep-verification and restored.
4. **SystemNix test-paperless.nix head surgery took 3 attempts** (nested
   let-in structure; two partial edits left double function heads). The
   file was never red on their master (all pre-push), but the churn was
   avoidable with one view-before-edit.

## e) WHAT WE SHOULD IMPROVE

- Instrument FIRST on VM failures: one `machine.execute` + journal read
  replaces three theory-driven rebuild cycles (~10 min each).
- The daemon/CI race is structural: consider a pre-push local
  `nix flake check --no-build` gate in the daemon or a CI-required
  "eval-first" workflow split.
- Escaping through three layers (nix string → python → shell) needs a
  named idiom: file carries `\\x2d` (2), never more; write a helper or a
  pinned example comment next to every use.

## f) NEXT

Harvested into TODO_LIST (rewritten today): 7 TODO rows (flake update
manual flow, docs-gates pin, VM retry-once, diff-gate bite leg, SystemNix
flake.lib anomaly tracking, harness per-group logs, devShell docs-gates
passthrough, parity cadence comment) + 2 BLOCKED (v0.1.1 tag = g3;
metadata.yaml owner = Q3). ROADMAP parked tier: single-sourcing (T10),
parenthesization lint (T16), dual-wan dropped (T13), Renovate opt-in.

## g) QUESTIONS (owner)

1. **v0.1.1 patch tag?** The release content exists (CHANGELOG: two lib
   fixes, CI hardening, 6 audit modules, the VM leg). Tag now or fold
   into 0.2.0 with the pending flake update?
2. **`.config/metadata.yaml`** (unchanged from the 08:33 report): which
   tool owns it, and may docs sessions populate `tags`?

Scores (VERIFY self-assessment): Accuracy 9.5 (every claim above names its
gate/run; counts grepped at write time), Fitness 9 (docs match the shipped
surface; the two BLOCKED rows are the only prose without a mechanical
witness), Trust floor held: CI green at report time, harness 48/48, both
repos' flake checks green.
