# SUPERB execution — midpoint status (2026-11-13 08:33)

**Verdict up front:** T1-T11 of the 17-task SUPERB plan are DONE and verified
(11/17). T12 is written-but-red (eval bug) and — worse — its broken wiring
was auto-committed and PUSHED, so **origin/master CI is RED right now**
(run 43347413182). T13 hit a discovery that may kill the task (the dual-wan
stack is banner-RETIRED SystemNix-side). T14-T17 not started. The SystemNix
cross-repo commit from T2/T4 is still STAGED there after a ~6h stuck retry
loop. Restore-green is the first action after this report.

Scope of this report: ONLY this session's run (2026-11-13 ~01:00 → 08:31,
one continuous execution turn with a ~5.5h gap at the end where background
jobs finished unattended). Local gates were green at every deliberate push;
the one red push happened through a daemon race, documented in (d).

---

## a) FULLY DONE (verified this session)

| # | What | Evidence |
|---|------|----------|
| T1 | CI first run red → root-caused → fixed → **green incl. all 4 VMs** | run 43336330142 (red: contract checks embedded `toplevel.drvPath` in derivation env — unrealizable on fresh stores, warm-store phantom-green) → fix = `config.assertions` gate → run 43338694884 green; FEATURES 🟡→🟢 with URL; fresh-store repro (`--store /tmp/ci-repro`) proved the fix; harness marker re-pointed (boot-mirror condition leg now matches the module's own self-pinned assertion — stronger catch) |
| T2 | SystemNix `parseMemoryBytes` bare-byte fix + `lib-parse-memory` regression check | fix applied + check builds green SystemNix-side (`harden {MemoryMax="5242880";}` → MemoryHigh 4194304, proven); **commit there still pending — see (d)** |
| T3 | Evidence hardening | `optionsjson` harness group + hand-proven marker specificity; honest mergeIt approximation note in tests/lib-eval.nix; `--rebuild` semantics established empirically (re-EXECUTE builder + compare vs existing store paths, nix 2.34.9; v0.1.0 wording accurate); 00:58 report caveat resolved inline |
| T4 | lib-eval II: 5 helpers → Class A, **76 contracts** (was 53) | found + fixed a SECOND real bug: `mkDesktopNotifyService` passed a `mkMerge` wrapper as harden's ARGUMENTS (neutralizations never bound, `_type`/`contents` garbage, option-merge unwrap silently DISCARDED every harden default) — fixed to plain attrset union BOTH repos; `iotier-drifted` harness leg; harness 25 cases |
| T5 | Bookkeeping | 22-04 plan EXECUTED banner; CHANGELOG [0.1.0] tag-ref link; README version-bump flow |
| T6 | watch.sh divergence: **dissolved** | SystemNix delegated its wifi-failover module WHOLESALE to this collection's flake input (lock-pinned `726c2bb`, ancestor of v0.1.0) — no SystemNix copy remains; divergence ledger now EMPTY |
| T7 | **Standing semantic parity diff** | `tests/parity/run.sh` / `nix run .#parity-diff`: 22 helper probes × identical inputs × same nixpkgs instance × normalized JSON (overrides unwrapped, derivations→names, store hashes→`<h>`); bite-proven with a mutated fork copy (names probe, prints both sides); current verdict 22/22 identical |
| T8 | Dependency policy (Q3 decided) + Dependabot | `.github/dependabot.yml` (weekly, grouped, chore(deps)); floating @vN majors (SHA-pin rejected: no secrets at stake, CI re-proves); flake.lock stays MANUAL; Renovate = owner opt-in in ROADMAP; Dependabot PR #1 (checkout 7.0.1 + nix-installer bump) reviewed + merged |
| T9 | Harness ergonomics + runner race #1 | `--help`, per-group PARALLEL default (PARALLEL=0 serialize; log-derived counts), devShell (`nix develop`), `checks.*.tests-wiring` (every tests/*.nix ⇄ flake.nix, bite-proven both directions — kills the 7→8→10 hand-count class); Ubuntu-26 runner exposed missing `wait_for_unit(mount)` in caddy/journal tests — fixed |
| T10 | Single-sourcing spike: **PARKED with verdict** | the 4 "copies" are independent witnesses (module self-assert = internal consistency; test pins = external hardcoded truth; README = human contract); collapsing them = the phantom-green class the repo's own canon warns about. Verdict in ROADMAP |
| T11 | README options tables + drift guard | Options tables rendered from options-json data for the 3 modules lacking them (boot-mirror 6, hot-tier 13, hot-dir-migrate 15 options); `checks.*.options-readme-drift` proves table ⇄ declared surface both directions (ghost-row bite); Nix lesson pinned in-file: `[f x]` is a TWO-element list — parens required for applications in list literals |
| — | Docs canon held throughout | docs-gates 5/5 re-run green after every doc batch; annotate tool repaired 2 archived reports (strike-per-cell + verdicts) after an upstream docs-gates rule drift; TODO rows deleted only with CHANGELOG entries; counts recomputed by grep at write time |
| — | Pushes | 8 deliberate pushes landed (1900016-era plan push was prior session; this session: fix → docs → T3-T5 → T6+T7 → T8 → T9 → T10+T11) |

## b) PARTIALLY DONE

| # | What | State | Missing |
|---|------|-------|---------|
| T12 | boot-mirror runtime VM leg | `tests/boot-mirror-vm.nix` WRITTEN (4 scenarios: full sync + diff-gate, counter reverse-propagation, blessing convergence, condition-skip degradation, ro-mirror loud failure) and WIRED into flake.nix as `checks.*.boot-mirror-vm` | **eval-red**: `attribute '"/boot-mirror"' missing` at the module's nofail assertion inside the VM fixture — needs debugging (likely the fixture evaluates the module's mkIf without the fileSystems entry landing); never built; no harness leg yet; **its broken wiring is on origin (see d)** |
| T13 | dual-wan migration | research complete: module read (233 lines), fleet couplings = exactly `networking.local.{lanIP,gateway}` + 2 colocated scripts (273+99 lines); extraction shape designed (options `lanIP`+`gateway`, collection lib, reverse conflict assertion) | **BLOCKED on a discovery**: `mptcp-endpoint-manager.sh` carries a RETIRED-STACK banner (2026-09-16: "rode the retired dual-WAN stack (replaced by services.wifi-failover)… Nothing invokes this script") — the stack is retired fleet-side; migrating it may be moot. Question (g1) |
| — | SystemNix cross-repo commit (T2+T4 fixes) | fixes APPLIED + STAGED there (status M/A on flake.nix, lib/systemd.nix, lib/default.nix, checks/lib-parse-memory.nix); their pre-commit hook runs `nix flake check --no-build --all-systems` (~minutes) under continuous daemon lock contention | my 90×12s commit retry loop ran ~6h in background without landing a commit (job 142 still "running" at report time — stuck/stale); the daemon committed 21 OTHER files meanwhile but never my staged set. Land manually next session |

## c) NOT STARTED

| # | Task |
|---|------|
| T14 | Port-registry audit-gate module (unitExecText/extractPortLiterals scan + registry + allowPorts) |
| T15 | Gatus-coverage audit-gate module (same scan surface) |
| T16 | Statix custom rule: unparenthesized select over application (`f x y .attr`) |
| T17 | Post-execution VERIFY re-score + report + harvest (depends on T12-T16) |

## d) TOTALLY FUCKED UP (honest register)

1. **Origin/master is RED right now** (run 43347413182, ~5h old): the daemon
   auto-committed my flake.nix wiring of the eval-broken `boot-mirror-vm`
   check and pushed before my local build verdict landed. I wired a check
   I had never evaluated — the exact class `tests-wiring` guards in the
   files→flake direction, nothing guards flake→BROKEN. Sequencing failure,
   not a tooling gap. Local is ahead 1 (e62a647, docs-only) and NOT pushed.
2. **boot-mirror-vm fixture eval bug** (the proximate cause; unresolved).
3. **SystemNix commit loop stuck ~6h** (job 142): my retry loop had no
   wall-clock timeout reporting and no failure surface — it silently ground
   against daemon lock cycles. Fix is staged; nothing lost, but the bridge
   note (rev reference) never landed in either CHANGELOG.
4. **Edit-vs-daemon races**: 6+ "modified since last read" rejections this
   session; twice I nearly lost edits (CHANGELOG bullet, plan banner) —
   caught only by the tool's mtimes.
5. **Pipe-masking recidivism**: hit the documented `$?`-of-`tail` trap TWICE
   more (SystemNix build, an early grep) despite it being a written lesson.
   The lesson exists; the reflex doesn't.
6. **v0.1.0 ships both lib bugs** (parseMemoryBytes + mkDesktopNotifyService
   harden-call) — both fixed only on master. Any consumer pinning v0.1.0
   (none known beyond SystemNix's pre-fix delegation) gets them.
7. Drafting debris: a nonsense `systemctl start boot-mirror-mount-retry…`
   line shipped in the first boot-mirror-vm.nix write (caught in review,
   removed before commit).

## e) WHAT WE SHOULD IMPROVE

- **Push gate discipline**: never let a flake.nix check-wiring leave the
  working tree without a green `nix build .#checks.<name>` FIRST; commit the
  check + its green in one step, immediately (the daemon will otherwise
  race you to origin).
- **A flake→broken guard**: tests-wiring catches missing wiring; consider a
  `nix flake check --no-build` hook the daemon respects (or commit-time) —
  this exact red would have been caught at commit.
- **Cross-repo commits: stop fighting the daemon.** Apply → verify → stage →
  ONE commit attempt; if locked, LET THE DAEMON take it with its heuristic
  message and reference "SystemNix master <date>" in the bridge CHANGELOG.
  Content > commit message. Retry loops that grind for hours are worse.
- **VM tests + the Ubuntu-26 runner**: 3 CI reds across 2 distinct races
  (mount-unit wait; udev label-symlink vs 5s device-timeout). Any push
  touching VM tests should re-prove locally with `--rebuild`; consider a
  workflow retry-once-on-failure for VM steps.
- **Harness legs for new checks on arrival**: options-readme-drift and
  tests-wiring got manual bites; boot-mirror-vm has no mutation leg yet.
- **docs-gates floats** (github: ref) — its rule drift redid two archived
  reports mid-session; pin it in the flake or vendor the config.

## f) NEXT — up to 50, in priority order

**Restore trust (today):**
1. Fix boot-mirror-vm fixture eval (`"/boot-mirror"` fileSystems assertion) or temporarily unwire it — get origin/master green.
2. Push the local ahead-1 commit once green.
3. Land the staged SystemNix commit (accept daemon heuristic message if locked; record the rev in this repo's CHANGELOG).
4. Re-run docs-gates + full harness (25) + parity diff after the fix.

**Finish the plan:**
5. T12 completion: VM test green locally + on runner; add the boot-mirror harness leg (diff-gate / counter mutation).
6. T13 decision per (g1): if dead → close the TODO row with the retirement evidence; if alive → extract fleet-agnostic core (options lanIP/gateway, scripts colocated, collection lib), eval-contract, 2-leg negative group, both-direction conflict assertions, README + options table (drift guard will demand it).
7. T14 port-registry audit module (registry option, unitExecText scan, violations throw naming unit+port, allowPorts escape, contract + 2 negative legs).
8. T15 gatus-coverage audit module (consumer gatus config as input, uncovered-listener report, shared scan surface with T14).
9. T16 select-parenthesization statix rule (research API → prototype → fixture on the d.4 phantom-falsehood case → FP sweep over repo + nixpkgs sample → wire or park).
10. T17 VERIFY re-score + fresh report + harvest §f + annotate/archive the 00:58 living report (check-rows --strict + bare-rows BEFORE git mv).

**Hardening/backlog observed this session:**
11. Pin docs-gates (flake input) instead of the floating github: ref.
12. VM-test workflow: retry-once on VM-step failure (runner races).
13. Add a boot-mirror-vm bite leg to tests/negative (mutate the diff gate out of the script → VM leg must fail — needs eval-visible pin first; the gate is runtime-only today).
14. Pin the `[f x]` list-literal lesson + the drvPath-in-env lesson into AGENTS gotchas (drvPath one IS in; list-literal one is only in the test file).
15. SystemNix `flake.lib` anomaly (harden closure loses `lib.genAttrs`): file a SystemNix-side TODO/issue so it outlives my commit message.
16. v0.1.1 decision per (g3) (patch tag with the two lib fixes + CI-verified state).
17. options-json: consider rendering option DEFAULTS into the README tables automatically (T11 left generation manual, guard automatic).
18. `nix flake update` cadence: lock is days-old nixos-unstable; run the manual flow (update + full gates + parity) once CI is green.
19. Harness: parallel mode prints interleaved group output — consider per-group log files surfaced on failure.
20. devShell: add the docs-gates package or a passthrough wrapper so the battery runs without the floating github: ref.
21. ROADMAP sweep after T13 verdict (dual-wan bullet either way).
22. Consider Dependabot reviewers/assignees config once the owner expresses a preference.
23. If dual-wan is migrated: VM story decision (2×veth WAN simulation vs eval-only) — document honestly either way.
24. tests/parity: add a CI-optional job or a scheduled reminder to run it (it needs the SystemNix sibling, so it cannot run in CI as-is — document that boundary in the workflow comments).
25. Backfill FEATURE rows for any v0.1.1 tag story.
26. Sweep AGENTS "10 test files" count → recount via grep after T12-T16 land (the count WILL drift; tests-wiring guards wiring, not prose counts).

## g) QUESTIONS (cannot figure out myself)

1. **T13 / dual-wan:** `mptcp-endpoint-manager.sh` is banner-RETIRED
   SystemNix-side (2026-09-16: "replaced by services.wifi-failover …
   nothing invokes this script"), yet the dual-wan MODULE still exists and
   wifi-failover still carries a conflict assertion against it. Is dual-wan
   (a) dead — close T13 with the retirement evidence, or (b) standby
   tooling worth absorbing into the collection anyway?
2. **Red-master handling:** fix-forward (debug the boot-mirror-vm fixture,
   ~30 min, one more push) or hotfix-revert the wiring now (green in
   minutes, T12 re-lands later)?
3. **v0.1.1:** tag a patch release once master is green (carries both lib
   bug fixes + CI-verified state; SystemNix re-pins), or hold tags until
   T12-T17 land and cut 0.2.0 whole?

— Report written 2026-11-13 08:33 CET; execution resumes on GO.
