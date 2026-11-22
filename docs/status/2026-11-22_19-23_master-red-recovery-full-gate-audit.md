# Status Report — master-red recovery + full gate audit (nixos-modules)

**2026-11-22 19:23 CET · session scope: single-session audit-and-fix pass over `~/projects/nixos-modules`, triggered by an open-ended "fix it all" directive; includes verification of the interrupted 2026-11-22 wave the auto-commit daemon had landed in two chunks (766be30 + 3ab8d22).**

## Scope line — what this report VERIFIED vs NOT verified

**Verified here (fresh commands, this session):**

| Claim | Evidence |
| --- | --- |
| Master was eval-RED on BOTH systems | `nix flake check -L` (bg job 008) failed: `error: expected a set but found a list: [ ]` at `checks.x86_64-linux.systemd-shape-audit-contract`; full trace pinned `modules/systemd-shape-audit/default.nix:213:30` (`lib.mapAttrsToList` fed `lib.attrNames` output). `nix flake check --all-systems --no-build` failed identically on aarch64. |
| Fix is in and green | Edited `default.nix:213` to `map (n: "user:${n}")`; `nix build -L .#checks.x86_64-linux.systemd-shape-audit-contract` → `systemd-shape-audit-contract: 11 classes flagged, clean host silent`, output file `{"clean":true,"flaggedClasses":11}`; landed via daemon commit `e8af019`. |
| Full flake check green post-fix | `nix flake check -L` (bg job 022) → `all checks passed!` (20 x86_64 checks incl. 5 VM tests; wifi-failover VM ran 316 s in the captured log). A second defect surfaced mid-run and was fixed first (see (a) #2). |
| aarch64 eval portability | `nix flake check --all-systems --no-build` → `all checks passed!` (the `app ... lacks attribute 'meta'` warnings are cosmetic and pre-existing). |
| Parity with the SystemNix fork | `bash tests/parity/run.sh` → `parity-diff: OK — 22 helper probes semantically identical`. |
| Mutation harness green incl. 4 never-run legs | `bash tests/negative/run.sh` → `passed=67 failed=0`; focused `CASES=bootmirror` re-run → `passed=9 failed=0` with `bootmirror/remainafterexit-restored` and `bootmirror/vm-deaf-trigger` (the two new VM/eval legs) failing-with-expected-marker. |
| Formatter clean | `nix fmt` twice → `formatted 0 files (0 changed)`. |
| docs-gates green | `nix run .#docs-gates -- run .` → 8/8 PASS, run twice (pre- and post-doc-edits). |
| `nix flake show` recovered | Now evaluates through every module output; the owner's pre-session BuildFlow line `DISCOVERY DEGRADED … nix flake show failed` was a symptom of the same eval-red bug. |
| statix finding at contract test:83 still present | `statix check tests/systemd-shape-audit-contract.nix` → `[20] Warning: Avoid repeated keys in attribute sets` (`user` path assigned 3× inside one `systemd = { … }` literal). Eval-LEGAL (nested attrset paths merge — the check builds), lint-only; NOT fixed in this session. |

**NOT verified here (gaps named in advance):**

- **CI never consulted.** No `gh run list`, no push. Whether CI ran (or can run) on `e8af019` is unknown; if the daemon never pushes, the red window was invisible to CI and the fresh-store proof (CI is the standing witness for the drvPath class) has not happened.
- **FEATURES line 32 "6 mutation legs" for boot-mirror is stale** — the group now has 8 mutation legs + 1 control (derived from `grep run_case tests/negative/run.sh` + the focused run's output). Found while writing THIS report; not yet fixed.
- **boot-mirror-vm "4-scenario" counts (FEATURES lines 32/79)** — today's second-write leg extends an existing scenario; whether the top-level scenario count changed was not re-derived from the test file.
- **The harness printed `bootmirror/vm-deaf-trigger` PASS twice** in the focused re-run (10 lines, `passed=9`). Cosmetic? Not investigated — print-dup vs counter-dup matters for trusting `passed=67`.
- **The owner's pre-session `buildflow --fix --build-mode=full` findings were triaged ad hoc, not systematically worked:** stale flake.lock pins (5 go-* inputs 42–60 d old), vulnix 56 advisories in the VM closure, flake-parts locked twice under docs-gates, AGENTS.md 263 > 220 lines, lychee/vulnix missing from devShell, BuildFlow state DB 1.1 GB. None touched except dprint-remote-plugins (resolved by deleting the resurrected config) and doc-age (resolved by today's doc edits).
- `modules/_*` helper space and `.docs-gates.json` were not audited.

---

## a) FULLY DONE

1. **Root-caused and fixed the master-red eval bug** — `modules/systemd-shape-audit/default.nix:213`: `lib.mapAttrsToList (n: _: …)` consumed `pathTriggerOffendersIn …` which returns `lib.attrNames (…)` (a LIST; set-typed builtin → unconditional throw). Changed to `map (n: "user:${n}")`. Evidence: contract check builds with `{"clean":true,"flaggedClasses":11}`; daemon commit `e8af019` carries it (plus .gitignore + dprint deletion).
2. **Caught and fixed the SECOND red gate the fix uncovered** — `checks.*.options-readme-drift` failed: `undocumented option(s): allowPathTriggerOnRemainAfterExit` (the interrupted wave added/renamed the option but never updated the README table). Added the row, corrected "Ten bug classes" → "Eleven" + the deaf-trigger class in `modules/systemd-shape-audit/README.md`. Evidence: `nix build -L .#checks.x86_64-linux.options-readme-drift` → exit 0.
3. **Deleted the dprint.json zombie and root-caused its resurrection** — the file had been deleted twice by decision (2026-11-12, documented in AGENTS) and re-committed byte-identical twice by the auto-commit daemon (229f441 → 1701745 deleted → 9148c0d → 62a167f deleted → a221220; md5 identical across all versions). Now deleted AND gitignored with a rationale comment so the daemon's `git add` heuristic cannot resurrect it.
4. **Verified the interrupted wave's full surface** — boot-mirror start-limit headroom (burst 5→30 + self-pinned `>= 20` assertion + contract pin), class-11 user-manager scan, boot-mirror-vm second-write leg (second loader-entry write must mirror without restart; path unit must sit `waiting` between runs), 4 new negative legs. Evidence: full `nix flake check -L` green + harness 67/67 + focused bootmirror 9/9.
5. **Closed the `.config/metadata.yaml` TODO row by identifying the owner** — projects-management-automation's `MetadataService` (`internal/infrastructure/meta/service.go:29` writes `<project>/.config/metadata.yaml`; shape matches: created_at/updated_at/tags). The "may docs sessions populate tags?" sub-question stays an owner call. Evidence row removed from TODO_LIST.md.
6. **Docs honesty sweep** — AGENTS.md: new gotcha (the daemon commits interrupted work in heuristic chunks → master can land eval-red; START sessions by running gates on CURRENT master), testing-model leg 1 rewritten to the assertions-gate wording (it still described the REMOVED drvPath-forcing pattern, contradicting the file's own CI gotcha), leg 2 now lists all 5 VM tests. FEATURES.md: harness row 16 groups / 67 cases / 16 green controls (derived by `grep -c run_case`), shape-audit 11 classes system+user. README.md: new "Eval-time audit gates" section — all 10 audit modules were entirely absent from the front door. docs/DOMAIN_LANGUAGE.md: new "deaf trigger" term. CHANGELOG.md: `## [Unreleased]` entry narrating the bug + wave verification. TODO_LIST.md: metadata row removed.
7. **All gates re-proven after the doc edits** — flake check, aarch64 pass, fmt, parity 22/22, docs-gates 8/8 ×2, harness 67/67.

## b) PARTIALLY DONE

1. **BuildFlow findings triage** (owner's pre-session run, 70 findings): resolved in-session — the eval-red `nix-flake-check` findings (root cause fixed), `quality/dprint-remote-plugins` (config deleted), `doc-files-age-check` (docs edited). Still open: stale lock pins, vulnix, AGENTS size, flake-parts dup, devShell binaries, statix:83, DB sizes. Blocker: none — pure scheduling; several are fleet-policy calls. Effort: M for the whole batch.
2. **Doc-count honesty** — the counts I KNEW changed got updated; a full re-derivation found one more stale row (FEATURES line 32 mutation-leg count) that is still unfixed, and two count claims (boot-mirror-vm scenario count) remain unverified. Effort: S.
3. **CI proof of the fix** — locally proven on a warm store; the fresh-store/CI witness has not run (see Not-verified). Blocker: push policy (I don't push). Effort: S once pushed.

## c) NOT STARTED

1. **`nix flake update` manual flow** — 5 flake inputs in the warn band of the nix-checker ADR-0003 thresholds (42–60 d old; warn >30 d, fail >90 d). Not started: deliberate — the flow requires the full gate battery + harness + parity before pushing the lock, and nixpkgs-unstable churn makes it a heavyweight operation. Still wanted (it is repo policy).
2. **vulnix triage (56 advisories in the VM-test closure)** — Diff 9.1 critical, binutils ×17, ada/async high…; none triaged (build-time/test-closure exposure vs shipped-surface exposure unclassified). Not started: out of session scope, needs a policy.
3. **Structural gate-before-commit for the daemon in this repo** — BuildFlow pre-commit exists as a fleet pattern; this repo has no `.buildflow.yml` and no pre-commit hook, so an interrupted session can again land master red. Not started (needs an owner decision on the mechanism).
4. **Harness mutation legs for options-readme-drift and tests-wiring** — both checks exist and were bite-proven manually once, but no permanent harness group guards them (group list: bootmirror…capgrant, lib, optionsjson — no readmedrift, no wiring). Not started.
5. **ROADMAP items** (SystemNix migration kill, generated option tables, Renovate opt-in, upstream statix rule, port/gatus audits as modules — last two partially shipped as scan surface only). Not started: parked by design.

## d) TOTALLY FUCKED UP

1. **Master was eval-RED for ~75 min (17:52–19:05 local) with zero structural defense.** The auto-commit daemon committed an interrupted session in two heuristic chunks (766be30 at 17:52, 3ab8d22 at 17:55) including an unconditional eval throw and a half-reverted option type (`types.str` → `lib.types.str` across two commits). Nothing gated the commits: no pre-commit hook, no flake check in the daemon path. Anyone pulling in that window got a broken flake. Mitigation now: bug fixed, AGENTS gotcha pinned; the STRUCTURAL fix (gate-before-commit) is still open — c) #3.
2. **The wave shipped runtime-contract legs that had never executed.** 4 negative-harness legs + the VM second-write assertions went into master blind (committed before any run). They pass — verified this session — but that is luck + the original session's coherence, not process. The same class produced the phantom-green trap this repo documented on 2026-11-13 (drvPath-in-env passing warm stores only).
3. **dprint.json was resurrected twice and nobody noticed for 9 days.** The daemon re-added a deliberately deleted file byte-identically in two separate heuristic commits (2026-11-13); it sat tracked-but-unreferenced, contradicting AGENTS, until this session's unrelated `ls` caught it. Mitigation: gitignored; the underlying daemon blind spot is fleet-wide (cf. `go-filewatcher#61` daemon-junk report in the dispatch queue).
4. **My own honesty sweep was partial — two drifts escaped it.** (i) FEATURES line 32 still claims "6 mutation legs" for boot-mirror (actual: 8 — found while writing this report, not by the sweep). (ii) The statix repeated-key warning on the contract test survived the session (I never ran statix standalone on the file my fix touched). Lesson pinned: re-derive counts from code (`grep`), don't update the ones you remember changing.
5. **The doc-count class keeps rotting because counts live in prose, not code.** Today: AGENTS "the 4 eval-contracts" (actual 14), FEATURES "13 groups / 48 cases" (actual 16/67), "10 classes" (actual 11), "6 mutation legs" (actual 8), README missing 10 modules. Every one required a human/agent notice-and-fix cycle. Root cause: unguarded prose counts; the repo guards option tables (options-readme-drift) but not narrative counts.

Severity summary: #1/#2 block trust in master's history (fixed retroactively); #3/#4 are hygiene with real cost (9-day zombie, repeated manual sweeps); #5 is a standing tax paid every session.

## e) WHAT WE SHOULD IMPROVE

1. **Gate the daemon, not just the session.** The daemon's heuristic commit should refuse (or defer) when `nix flake check --no-build` fails — it is pure eval, seconds-cheap, and would have blocked BOTH of today's red chunks. Fleet-level: BuildFlow pre-commit already implements the pattern; this repo needs `.buildflow.yml` or a local equivalent.
2. **Counts belong to code, prose just points at them.** Either generate count-bearing sentences (harness `--help` already emits group/case lists — README/FEATURES could quote it) or accept a periodic `grep`-derived audit as ritual. The middle path: a tiny check that greps `run_case`/`group_` counts against the two doc rows (same shape as options-readme-drift).
3. **Session-start green check as ritual** — now pinned in AGENTS ("never assume HEAD is green because the last session ended clean"). Better: make it mechanical (Crush hook / devShell shellHook that runs `nix flake check --no-build` on entry and prints the verdict).
4. **Harness green-output ergonomics.** On green, the group logs are deleted and only a flat PASS list prints (tail-truncation hid the bootmirror group; the duplicate `vm-deaf-trigger` line hints at double-printing). A compact 16-group matrix (cases/passed/failed per group) printed on EVERY run — green included — would make every run self-witnessing.
5. **Interrupted-work handoff.** The wave was recoverable only because the original session's comments were excellent (deaf-trigger narrative, live-incident dates). A crash-resume convention (a `docs/status/…WIP.md` the session updates before each daemon-sweepable edit) would let the next session distinguish "half-done" from "done-but-unverified" without archaeology via `git log -S`.
6. **Advisory batteries need an owner.** BuildFlow's findings (stale pins, vulnix, sizes) are nobody's scheduled work — they surface only when someone runs the battery. Either schedule it (CI/cron) or route each finding class to an owner file (TODO row / policy doc).

## f) Top things to get done next (ranked; HARVEST input — pull into TODO_LIST/ROADMAP, do not entomb here)

| # | Task | Impact | Effort | Category |
| --- | --- | --- | --- | --- |
| 1 | Fix FEATURES line 32: "6 mutation legs" → 8 (boot-mirror group re-derived: 8 mutations + control) | High | S | Documentation |
| 2 | Resolve statix W20 at `tests/systemd-shape-audit-contract.nix:83`: merge the three `user.*` path assignments into one `user = { services…; paths…; }` block | Medium | S | Cleanup |
| 3 | Push master (owner action) so CI re-proves the eval-red fix on a fresh store; confirm the run green | Critical | S | Bug (verification) |
| 4 | Investigate harness duplicate `vm-deaf-trigger` PASS line (print-dup vs counter-dup); if counter-dup, `passed=67` needs re-basing | Medium | S | Bug |
| 5 | HARVEST this report's (f) into TODO_LIST.md / ROADMAP.md (docs-health HARVEST mode) | High | M | Documentation |
| 6 | Decide + implement gate-before-commit for this repo (`.buildflow.yml` with BuildFlow pre-commit, or a minimal `nix flake check --no-build` pre-commit hook) — kills today's incident class structurally | Critical | M | Quality |
| 7 | Run the `nix flake update` manual flow for the 5 warn-band inputs (go-finding 42 d, go-branded-id 54 d, samber-do-auditlog 48 d, go-atomic-write 60 d, go-error-family 54 d) + full gates + harness + parity before pushing the lock | High | L | Dependency |
| 8 | Add harness mutation legs for `options-readme-drift` (ghost-row + dropped-row directions) and `tests-wiring` (unwire + phantom-ref) — both bite-proven once, never institutionalized | High | M | Quality |
| 9 | Vulnix triage of the 56 advisories in the VM-test closure: classify test-only vs shipped exposure; write the policy sentence (ignore/schedule/pin) in AGENTS | Medium | M | Security |
| 10 | Trim AGENTS.md back under the 220-line preflight budget (263 now, and this session ADDED lines): move the gotcha narratives to docs/, keep pointers | Medium | M | Documentation |
| 11 | Deduplicate the flake-parts double-lock under `docs-gates/erraudit` + `docs-gates/go-nix-helpers` (follows indirection docs-gates-side, or accept + document) | Low | S | Dependency |
| 12 | Re-derive and re-verify every count-claim in README/FEATURES from code in one sweep (VM scenarios per test, mutation legs per group, check counts) — one systematic pass instead of notice-and-fix cycles | High | M | Documentation |
| 13 | Consider a `readme-drift`-style check for narrative counts (grep run_case/group_ vs the doc rows) — the options-table guard pattern generalized | Medium | M | Quality |
| 14 | Set `system.stateVersion` in contract-test fixtures (or document why absent) to silence the eval-warning spam on every check build | Low | S | Cleanup |
| 15 | Add lychee + vulnix to the devShell (or flake apps) so ad-hoc quality runs use project deps, not bare `nix run nixpkgs#…` | Low | S | Quality |
| 16 | Decide the fate of the buildflow-managed `.gitignore` block in a repo with no `.buildflow.yml` (remove, or keep with a comment) | Low | S | Cleanup |
| 17 | Harness: print a per-group compact matrix on green runs too (groups × cases × verdicts), keep it on disk | Medium | S | Quality |
| 18 | Crash-resume convention: WIP marker file updated before daemon-sweepable edits (turns "half-done" into a discoverable state) | Medium | S | Process |
| 19 | Schedule the negative harness (weekly CI cron or cron job) — it guards exactly the class that rotted for 75 min today and is currently manual-only | High | M | Quality |
| 20 | Cut v0.1.1 once the owner makes the tag decision (pending TODO row; content exists in CHANGELOG [Unreleased]) | Medium | S | Release |
| 21 | Dependabot reviewers/assignees config once owner states a preference (pending TODO row) | Low | S | Configuration |
| 22 | Answer "may docs sessions populate `.config/metadata.yaml` tags?" (owner policy; owner identified, decision open) | Low | S | Process |
| 23 | SystemNix migration kill: enumerate remaining SystemNix lib consumers, delete fork copies helper-by-helper (ROADMAP theme 1; parity runner stands guard) | High | L | Migration |
| 24 | Auto-generate module README option tables from options-json (ROADMAP; drift guard already exists) | Medium | L | Documentation |
| 25 | Renovate app for flake inputs (owner opt-in; ROADMAP) — would automate task #7's class | Medium | S | Dependency |
| 26 | Port-registry + gatus-coverage audit-gate modules: promote the shared scan surface into consumable audit modules (ROADMAP theme 3 remainder) | Medium | L | Feature |
| 27 | Upstream statix rule for the `f x.y` phantom-falsehood class (PARKED; only as upstream contribution) | Low | L | Quality |
| 28 | Extract the shared contract-test fixture host (fileSystems/boot.loader baseModules block repeated across 14 contract tests) — evaluate against the three-layer witnessing doctrine first | Low | M | Refactor |
| 29 | Verify README per-module "VM-tested (N scenarios)" claims against the actual test files (wifi-failover "5 scenarios" unverified this session) | Low | S | Documentation |
| 30 | Check whether the bootmirror negative group needs a `startlimit-pin-neutered` leg (the new `>= 20` assertion currently has no mutation leg of its own) | Medium | S | Quality |
| 31 | BuildFlow state DB 1.1 GB + cache 0.6 GB (infra-level): VACUUM/purge per the preflight's own advice | Low | S | Cleanup |
| 32 | `nix flake show` as a CI canary step (it degraded silently during the red window; 2 s cost) | Medium | S | Quality |
| 33 | Audit `modules/_*` helper space + `.docs-gates.json` (explicitly skipped this session) | Low | S | Cleanup |
| 34 | Confirm the daemon actually PUSHES or not (answers Not-verified #1; also decides whether task #3 needs a manual push ritual) | High | S | Process |
| 35 | Options-json/rendered-tables: add the 11th-class wording spot-check (README prose claims have no guard — only tables do) | Low | M | Documentation |
| 36 | Move the lib/README fork-ledger toward per-helper consumer counts (ROADMAP docs-automation idea) | Low | M | Documentation |
| 37 | wifi-failover + hot-tier VMs on the loaded-runner class: keep watching CI for the Ubuntu-26 race family (retry landed 2026-11-13; no new evidence this session) | Medium | S | Quality |
| 38 | Consider `warnings`-tolerant eval hygiene: the fixture hosts emit `system.stateVersion` warnings into every log tail — pairs with #14 | Low | S | Cleanup |
| 39 | Write the session-start ritual as a hook, not prose (pairs with e) #3): Crush hook or shellHook that gates entry on a green eval | Medium | S | Process |
| 40 | Re-run the full BuildFlow battery after tasks #1–#10 land and confirm the findings list shrank as expected (close the loop per BuildFlow skill step 7) | Medium | M | Quality |

## g) Questions I cannot figure out myself

1. **Does the auto-commit daemon ever PUSH master, or is push strictly manual?** I verified local commits only (`e8af019` carries the fix). If the daemon never pushes, CI never saw the red window and "CI green" claims only describe manual pushes — which changes how much trust CI's greenness buys and whether task #3/#34 are the same action.
2. **For the 75-minute red window: is gate-before-commit acceptable at the daemon level (refuse/defer commit when `nix flake check --no-build` fails), or is the daemon deliberately commit-unconditional by design** (e.g. so crash debris is never lost)? The fix differs radically: a refusing daemon would have prevented today's incident; a preserving daemon needs the WIP-marker convention instead.
3. **Is there a fleet policy for advisories (vulnix) and stale-pin bands (ADR-0003 warn >30 d) in repos whose closures are TEST-ONLY** — fix immediately, schedule, or ignore-with-note? Today's battery flagged 56 advisories + 5 stale pins in a repo that ships no runtime artifacts; the right response depends on whether test-closure exposure is in scope for the fleet's security posture at all.

---

*Report written 2026-11-22 19:23 CET. Verification transcripts for every claim live in this session's shell history; the gate commands are reproducible from the AGENTS.md Commands section. Next step per skill contract: docs-health HARVEST over section (f) — then WAIT for instructions.*
