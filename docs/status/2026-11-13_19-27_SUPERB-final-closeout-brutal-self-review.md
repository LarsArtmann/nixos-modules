# SUPERB final close-out — brutal self-review (2026-11-13, session 14:50–19:27 CET)

Scope: THIS session only (resuming from the 08:33 midpoint report after the
"WAIT HERE"). Verified claims carry their gate. The plan
(`docs/planning/2026-11-13_01-19_*`) is closed; this report audits HOW it
was closed.

## a) FULLY DONE (each with its proof)

1. **Statix clean repo-wide.** 3 repeated-key fixes: `treefmt.nix`,
   `tests/hot-dir-migrate.nix` (VM re-proven green after the merge),
   and the parallel a1a session's `tests/systemd-shape-audit-contract.nix`.
   `statix check .` exit 0.
2. **T12a — origin/master restored green.** Push 73462d6; CI run
   [43447887478](https://github.com/LarsArtmann/nixos-modules/actions/runs/43447887478)
   SUCCESS (all VMs).
3. **T12b — the stuck SystemNix commit landed** without my retry loop:
   592592293 (daemon took it; content verified).
4. **T12c — boot-mirror VM leg green**, local + runner, after a 12-iteration
   debugging arc; harness `vm-degradation-unpinned` leg proves the runtime
   pin bites (bootmirror group 6/6). Four VM-vs-production truths pinned
   (test header + AGENTS): mkVMOverride discards plain `fileSystems`;
   bootctl demands a partitioned ESP; virtio unplug is racy (fs-zeroing +
   unit-owned mounts is the deterministic path); dependency failure lands on
   the MOUNT (`Result=exit-code`), never the service's Result.
5. **T13 — dual-wan dropped with evidence** (RETIRED-STACK banner +
   `dual-wan.enable = false`; verified against SystemNix before writing).
6. **T14 — port-registry-audit module**: consumer-side `registry` option,
   membership + collision halves, `allowPorts`, 6-fixture contract (incl.
   word:NNN stays DETECTED, inert-until-enable), `portregistry` group 5/5.
7. **T15 — gatus-coverage-audit module**: class A + B, structural
   external-upstream exemption, proved against nixpkgs' REAL gatus module;
   `gatuscoverage` group 4/4.
8. **T15b — SystemNix bridge landed same day**: lock → 73462d6, both
   delegation layers, 4 plain-import test sites converted, test-paperless
   function-head conversion, their `nix flake check --no-build` green,
   pushed 8c108bdef.
9. **T16 — parenthesization lint parked with evidence** (statix fixed
   W01–W23 set, CLI-verified; misparse invisible post-parse; `[a b]` sweep
   → 3 instant FPs). ROADMAP verdict + AGENTS pin.
10. **T17 — VERIFY re-score + close-out**: fresh 16:30 final report; both
    priors annotated (`check-rows --strict` + `bare-rows` clean) and
    archived via `git mv`; TODO_LIST rewritten (9 rows harvested);
    ROADMAP stale bullets removed; plan bannered EXECUTED IN FULL;
    docs-gates 5/5 PASS.
11. **Full sweep**: negative harness 48/48 (13 groups; 12 green controls —
    grep-verified), `nix flake check --no-build --all-systems` green,
    full harness run completed 15:5x.
12. **Bonus, root-caused from CI journals**: the recurring Ubuntu-26
    hot-tier runner race is NOT udev timing — the boot transaction's DEVICE
    job is not gated by `After=tlc-fmt` and carries the 5s device-timeout
    while the formatter ran 9.1s wall. Fixed: healthy nodes' mounts get a
    90s window (`entrySlow`, both fixtures; both VMs re-proven green
    locally), degraded nodes keep the 5s fast-fail story; plus a CI
    retry-once step (two consecutive failures still land red). Runs
    43454375417-rerun and 43458939368: SUCCESS, SUCCESS.
13. Docs truth-held throughout: CHANGELOG (5 new bullets), FEATURES
    (audit-modules row 🟢, boot-mirror row gains the VM leg, harness
    counts), AGENTS (+5 gotchas), DOMAIN_LANGUAGE (+4 terms), module
    READMEs ×2, TODO_LIST, ROADMAP.

## b) PARTIALLY DONE

- Nothing in-flight. One soft edge: the very last push (c2c813b,
  CHANGELOG-only) was made WITHOUT watching its CI run — I only confirmed
  it retroactively while writing this report (conclusion: success). The
  discipline slipped even though the risk was nil (markdown only).

## c) NOT STARTED (session backlog — all in TODO_LIST/ROADMAP now)

- Flake-update manual flow (`nix flake update` + full gates + parity).
- docs-gates pinned as a flake input (still a floating `github:` ref).
- boot-mirror diff-gate runtime bite leg (gate has no eval-visible pin).
- SystemNix `flake.lib` anomaly tracked SystemNix-side.
- Harness per-group log files surfaced on failure.
- devShell docs-gates passthrough.
- Parity-diff cadence comment in `check.yml`.
- v0.1.1 tag (BLOCKED, owner) · metadata.yaml ownership (BLOCKED, owner).

## d) TOTALLY FUCKED UP (radical honesty)

1. **Pipe-masking recidivism, command #2 of the session**: I ran
   `statix check . | tail; echo $?` — printed tail's exit — after a prior
   session had ALREADY pinned this lesson. Caught one command later, but
   the first instinct was still the anti-pattern.
2. **The `\x2d` escaping bug shipped TWICE** (4 backslashes instead of 2 —
   mask line, then the is-active wait). Cost: two wasted VM builds plus one
   15-MINUTE timeout, because the typo'd unit name made the "wait" pass
   instantly for the wrong reason (the exact phantom-pass class this repo
   canonizes). I even announced the escaping fix and still re-broke it.
3. **Five VM cycles theorizing systemd semantics I could have measured**:
   dependency-vs-exit-code vs inactive; stacked mounts; monitor lag. The
   first diagnostic `machine.execute` (added only at cycle 5) answered in
   one run what three rebuilds had failed to. Lesson written, behavior lagged.
4. **An edit REPLACED the AGENTS SECURITY.md bullet** (composed
   replace-instead-of-insert; silently deleted a security-policy line).
   Caught by post-edit grep within minutes and restored — but it is the
   memory-destroying-replace class the canon explicitly warns about, done
   BY the canon's author.
5. **test-paperless.nix head surgery took 3 attempts** (edited the wrong
   `^{$` hit — the file's `let … in` block vs the returned attrset — then
   produced a double function head). Root cause: grep-anchor + edit without
   viewing the enclosing structure first, in a file another session owned.
6. **Bridge written before feasibility check**: I authored SystemNix
   delegation layers and only THEN discovered their locked input lacked the
   modules (one `nix flake metadata` beforehand would have sequenced
   correctly). The /tmp park + staged/unstaged dance that followed was
   churn from my own ordering error.
7. **Trusted the prior session's runner-race "fix" on faith**: the udev
   settle + poll patch was canonized in CHANGELOG/AGENTS as THE fix; today's
   CI logs proved it could never close the window (device job ungated by
   After=). I only read the mechanism after the second flake — verification
   discipline applied to my own new code but not to inherited conclusions.

## e) WHAT WE SHOULD IMPROVE

- **Instrument first, rebuild second** on VM failures: one `machine.execute`
  - journal grep ≈ 1 min; a theory-driven rebuild ≈ 4–15 min. Make it the
    written rule for any VM red.
- **Commit deliberately immediately after every green gate** — the daemon
  beat me to several commits, including mid-edit-sequence, causing stale
  anchors and "modified since read" churn 3+ times.
- **Verify prose counts at write time, every time**: the "12 green controls"
  claim happened to be right (grep says 12) — but I wrote it BEFORE
  grepping. Lucky is not verified.
- **Re-verify inherited fixes when touching their territory**: the udev-poll
  patch failed precisely where it claimed to defend.
- **/tmp hygiene**: parked bridge copies + a dozen log files left behind;
  parked copies are now stale duplicates of landed content.
- **Watch every push's CI to verdict**, even docs-only pushes.

## f) NEXT (ranked, deduped against TODO_LIST/ROADMAP)

1. `nix flake update` manual flow + full gates + parity diff + harness.
2. Pin docs-gates as a flake input.
3. v0.1.1 tag decision (BLOCKED on owner — see g).
4. VM-test device-timeout audit: any OTHER test mounts relying on 5s
   device-timeouts against in-band formatters (hot-dir-migrate's /mnt/hot
   is tmpfs — fine; verify, don't assume).
5. boot-mirror diff-gate runtime bite leg (needs an eval-visible pin).
6. SystemNix `flake.lib` anomaly: file/fix SystemNix-side.
7. Harness per-group log files surfaced on failure.
8. devShell: docs-gates passthrough (drops the floating-ref invocation).
9. Parity-diff cadence comment in `check.yml` (cannot run in CI — sibling).
10. Harness: consider CASES= filtering hint in the VM-leg comment (it adds
    ~4 min; document the opt-out).
11. Sweep /tmp for the parked bridge copies (stale) — delete.
12. Roadmap: upstream-statix rule sketch (Apply-in-list-element visitor)
    filed as an idea with the evidence from T16.
13. options-json: auto-generate README tables wholesale (ROADMAP idea).
14. lib/README fork ledger auto-generation (ROADMAP idea).
15. Consider a pre-push eval gate for the auto-commit daemon (see g).
16. metadata.yaml ownership (BLOCKED on owner — see g).
17. Dependabot reviewers/assignees once owner prefers (BLOCKED).
18. FEATURES: consider evidence-column links to the exact CI runs
    (now that runs are cited in CHANGELOG, unify).

## g) QUESTIONS (cannot figure out myself)

1. **v0.1.1 or 0.2.0?** The patch content exists (two lib fixes, 6 audit
   modules, boot-mirror VM leg, CI hardening). Tag v0.1.1 now, or hold for
   the pending nixpkgs lock update and cut 0.2.0?
2. **Daemon push policy:** the auto-commit daemon repeatedly pushes
   mid-work states (it once shipped eval-broken wiring for ~6h last
   session). Should I install a pre-push `nix flake check --no-build` gate
   in the daemon, or is the heuristic daemon + my deliberate commits the
   accepted tradeoff as-is?
3. **`.config/metadata.yaml`** (carried, unanswered since the 08:33
   report): which tool owns it, and may docs sessions populate `tags`?

Scores (VERIFY, this session): Accuracy 9 — every shipped claim names its
gate/run; one prose count written pre-verification (verified post-hoc).
Fitness 8.5 — docs match the shipped surface; /tmp litter and the unwatched
final push are the soft edges. Honesty: §d is complete to the best of my
reconstruction; the 12-iteration VM arc and 3-attempt file surgery are the
costline items the next session should not repeat.
