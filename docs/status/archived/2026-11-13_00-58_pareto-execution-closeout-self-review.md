# Session status — pareto execution close-out + brutal self-review (2026-11-13 00:58)

**Scope line.** This report covers the plan-execution session (all 18 tasks
of `docs/planning/2026-11-12_22-04_SUPERB-pareto-trust-first-execution-plan.md`)
plus its close-out, based on what THIS session did and noticed — no new
research. VERIFIED fresh at close-out: full `nix flake check` (all checks
passed, twice); `nix flake check --all-systems --no-build` (passed);
`bash tests/negative/run.sh` (22/22, twice); `nix build --rebuild` on all 4
VM checks (green — see d.7 for the overclaim caveat); one unambiguous fully
fresh wifi-failover-vm build (new derivation hash after the watch.sh edit);
docs-gates battery (5/5 PASS, twice — before and after the 00:25 report
archive); annotate gates clean on both archived reports; relative-link check
across all living docs (zero broken); `git status` clean; v0.1.0 tag points
at HEAD (`git rev-parse` match). Computed at write time: TODO_LIST = 11 task
rows (8 TODO + 3 BLOCKED); ROADMAP = 17 raw-idea bullets; AGENTS.md = 10,341
bytes (within the 5-15 KB budget — the size-check TODO row was answered and
removed on sight).

## a) FULLY DONE

1. **T1 gate re-proof** — full check green after the parallel landing; one
   real red fixed (parallel session's unformatted contract test).
2. **T2 doc-sync modules 3+4** — lib/README split contract, FEATURES usage
   map, AGENTS signatures, DOMAIN_LANGUAGE +8 terms.
3. **T3 evidence classes** — 3 mechanical classes; statuses now a function
   of class; serviceTypes 🟡→🟢.
4. **T4 wifi-failover legs** — new eval-contract + `wififailover` group; the
   harness caught my assertion-ordering bug before it shipped.
5. **T5-T8 lib-eval** — 53 pure lib contracts + `lib` harness group; found a
   REAL bug (parseMemoryBytes bare-byte crash) on its first run.
6. **T6 aarch64** — all pure checks evaluate on aarch64; VMs stay x86_64.
7. **T9 options-json** — provenance mechanically proven (4 modules, 40
   options); import-apply spike dropped with documented reasoning.
8. **T10 CI** — workflow shipped; SECURITY.md truthful again.
9. **T11 tooling** — dprint removed (hermeticity), deadnix+statix wired,
   .gitignore curated, description honest.
10. **T12 harness UX** — `nix run .#negative-tests` verified end-to-end;
    fresh VM evidence (with the d.7 caveat).
11. **T13 count audit** — 4 drifts fixed; archived-report gates re-run.
12. **T14 README** — MIT section, design-rules pointer, current commands.
13. **T15 docs-gates** — adopted, seeded, baseline all-green after harvest.
14. **T16 watch.sh comment** — fixed; divergence documented.
15. **T17 v0.1.0** — CHANGELOG wrapped; annotated tag created locally and
    re-pointed to the final tip; push deliberately withheld (owner-only).
16. **T18 re-score** — 00:25 report written; 21:40 report annotated (19
    DONE/RESOLVED + 8 ROUTED + Q1/Q2), gated, archived; Accuracy 8.5→9.5,
    Fitness 6.0→8.5.
17. **This report's harvest** — §f routed: 7 new TODO rows + 3 ROADMAP
    bullets; the answerable AGENTS-size row answered and never listed.

## b) PARTIALLY DONE

1. **CI pipeline** — shipped, YAML-valid, NEVER executed by a runner; action
   refs (`actions/checkout@v5`, `nix-installer-action@v17`) not verified
   against the marketplace; FEATURES honestly carries 🟡.
2. **VM re-proofs** — wifi-failover-vm has one unambiguous fresh run; the
   other three rely on `nix build --rebuild` whose semantics I did not
   verify (see d.7) — weaker evidence than my CHANGELOG wording claimed.
3. **lib-eval coverage** — 53 contracts, but 5 helpers remain Class-B-only
   (mkSecretCheck, mkDesktopNotifyService, mkStateDir, wrapWithMemoryLimit,
   ioTier-direct); mergeIt's types.anything approximation undocumented.
4. **options-json** — positive provenance proof only; no bite-proof leg.

## c) NOT STARTED

- The full ROADMAP tier (now explicitly listed there): kill path, standing
  parity diff, dual-wan, audit-gate modules, boot-mirror single-sourcing,
  options-table drift guard, boot-mirror VM leg, renovate, test-net
  ergonomics, docs automation, the select-parenthesization lint.
- SystemNix-side fixes (parseMemoryBytes, watch.sh comment absorb) —
  external repo, BLOCKED TODO rows.
- Pushing master + tag (owner decision).

## d) TOTALLY FUCKED UP (radical honesty — including two the 00:25 report missed)

1. **Archived a report through a FAILED gate.** I piped `check-rows` through
   `tail`, the pipeline exit was tail's 0, and the `&&` chain happily ran
   `git mv` on a gate that had just printed "incomplete". Caught it one
   command later, reverted, fixed, re-gated. The masking pattern was INVISIBLE
   to me until the gate text contradicted the flow.
2. **"EXIT: 0" lies in my own verification output.** The same pipe-masking
   shape appeared in several `cmd | tail; echo "EXIT: $?"` transcripts — the
   printed EXIT was tail's, not the command's. I never acted on a wrong
   verdict (error text was visible), but the numbers I printed were not the
   numbers I claimed.
3. **Count-from-memory failed TWICE more.** AGENTS test-file count churned
   7→8→10 across three writes; and the 00:25 report — the document ABOUT
   count discipline — claimed "TODO_LIST is 5 rows" when it had 4. Fixed in
   both places; the irony is not lost.
4. **Nix parse-ambiguity phantom chase.** `(f x y).attr` vs `f x y .attr`
   silently evaluated false; I spent two build iterations blaming type
   equality before a 3-way probe isolated the parse. Every select over an
   application is now parenthesized; the lesson is not mechanized.
5. **CHANGELOG head mangled by my own python one-liner** — entry landed above
   the title; caught on immediate head-check.
6. **Daemon-race retries.** ~4 "modified since last read" failures; once I
   retried without re-reading (edit failed; no damage).
7. **`--rebuild` overclaim.** CHANGELOG/00:25-report say "deterministic
   re-run, all green" — the output ("checking outputs of...") may mean
   output-comparison, not VM re-execution. I did not verify the semantics
   before claiming; only wifi-failover-vm has unambiguous fresh-run evidence.
   ~~Open caveat.~~ RESOLVED 2026-11-13 (SUPERB T3): `--rebuild` on nix
   2.34.9 re-EXECUTES the builder and compares the fresh result against the
   existing store paths (`-L` shows the runCommand stdout re-emitted; exit 0
   = identical). The v0.1.0 "deterministic re-run" wording is accurate.
8. **mergeIt trust.** lib-eval merges serviceConfig via `types.anything` and
   I asserted generator shapes through it without documenting that this is
   an approximation of the real NixOS option merge.

**Verdicts:** Forgot? — d.1/d.2 went unrecorded in the 00:25 report's §d
(added here); the SUPERB plan file still lacks an EXECUTED banner (TODO row).
Ghost systems? — `.config/metadata.yaml` remains unowned (Q3). Split brains?
— none created; the plan file's leg-count erratum was appended, not rewritten.
Lied? — not intentionally, but d.2/d.7 are claims-shaped-like-facts that were
weaker than stated; both corrected here and in TODO evidence text. Removed
something useful? — dprint.json and the buildflow .gitignore block, both
documented deletions.

## e) WHAT WE SHOULD IMPROVE

1. **`set -o pipefail` (or no pipe) around every gate/verification command**
   — the tail-masking class bit once invisibly (d.1) and polluted transcripts
   several more times (d.2). No exceptions.
2. **Compute counts with a grep AT WRITE TIME, every time** — two more
   violations this session (d.3); the rule exists, the habit doesn't.
3. **Verify tool semantics before claiming results** (--rebuild, d.7) —
   "green" must name WHAT ran.
4. **Parenthesize every select over an application** (d.4) — and mechanize
   it eventually (ROADMAP lint bullet).
5. **Re-read before EVERY edit under the auto-commit daemon** (d.6) — the
   failure is free, the habit is cheap.
6. **Ship the bite-proof leg in the same task as the check** — the harness
   caught two author bugs this session (assertion ordering, marker
   specificity); any check without a leg is a claim, not a gate.
7. **Keep docs-gates in the close-out loop** — its freshness output located
   the 2 unharvested items faster than my manual sweep; it also forced the
   ROADMAP parked-tier gap into the open.
8. **Answer answerable TODO rows on sight** (the AGENTS-size row never needed
   to exist — one `wc -c` answered it).

## f) Next tasks (ranked; routed — TODO_LIST 11 rows / ROADMAP 17 bullets after this harvest)

| #  | Task                                                                        | Impact | Effort | Route                       |
| -- | --------------------------------------------------------------------------- | ------ | ------ | --------------------------- |
| ~~1~~ done — master pushed; v0.1.0 tag live on origin | ~~Push master + v0.1.0 tag (explicit owner request required)~~ | ~~High~~ | ~~S~~ | ~~§g Q1~~ |
| ~~2~~ done — CI green runs 43338694884 + 43447887478; FEATURES flipped | ~~Verify CI first run on push; flip FEATURES 🟡→🟢; verify action refs exist~~ | ~~Med~~ | ~~S~~ | ~~TODO_LIST~~ |
| ~~3~~ done — SystemNix master 592592293 (cross-repo, not a hash here) | ~~Apply parseMemoryBytes fix to the SystemNix fork~~ | ~~Med~~ | ~~S~~ | ~~TODO_LIST (BLOCKED)~~ |
| ~~4~~ done — divergence dissolved: SystemNix delegated wifi-failover wholesale (T6) | ~~Absorb watch.sh comment divergence SystemNix-side~~ | ~~Low~~ | ~~S~~ | ~~TODO_LIST (BLOCKED)~~ |
| 5 **→ open — owner lane (TODO_LIST BLOCKED row)** | `.config/metadata.yaml` ownership | Low | S | TODO_LIST (BLOCKED) + §g Q2 |
| ~~6~~ done — T3: optionsjson harness group | ~~options-json bite-proof leg~~ | ~~Med~~ | ~~S~~ | ~~TODO_LIST~~ |
| ~~7~~ done — T4: 76 contracts, Class A | ~~lib-eval: 5 remaining Class-B-only helpers~~ | ~~Med~~ | ~~M~~ | ~~TODO_LIST~~ |
| ~~8~~ done — T3: honest mergeIt note | ~~Document mergeIt approximation in the test header~~ | ~~Low~~ | ~~S~~ | ~~TODO_LIST~~ |
| ~~9~~ done — T3: --rebuild semantics established | ~~Investigate + document --rebuild semantics; re-word the VM evidence claims~~ | ~~Low~~ | ~~S~~ | ~~TODO_LIST~~ |
| ~~10~~ done — T5: EXECUTED banner present | ~~Mark the SUPERB plan EXECUTED (header banner)~~ | ~~Low~~ | ~~S~~ | ~~TODO_LIST~~ |
| ~~11~~ done — T5: [0.1.0] heading links the tag | ~~CHANGELOG [0.1.0] tag-ref link + version-bump flow doc~~ | ~~Low~~ | ~~S~~ | ~~TODO_LIST~~ |
| ~~12~~ done — T7: tests/parity, 22 probes identical | ~~Standing SystemNix parity diff (carries 2 divergences)~~ | ~~Med~~ | ~~M~~ | ~~ROADMAP t1~~ |
| 13 **→ open — the kill awaits consumer batches (ROADMAP direction)** | Consumer migration batches → the kill (109 harden files) | Med | L | ROADMAP t1 |
| ~~14~~ done — T13: dropped with retirement evidence (ROADMAP) | ~~dual-wan module migration~~ | ~~Med~~ | ~~L~~ | ~~ROADMAP t2~~ |
| ~~15~~ done — T14: module + contract + 5 legs | ~~Port-registry audit module~~ | ~~Med~~ | ~~L~~ | ~~ROADMAP t3~~ |
| ~~16~~ done — T15: module + contract + 4 legs + bridge 8c108bdef | ~~Gatus-coverage audit module (shared scan surface)~~ | ~~Med~~ | ~~L~~ | ~~ROADMAP t3~~ |
| ~~17~~ done — T10: PARKED with verdict (ROADMAP) | ~~boot-mirror contract single-sourcing / drift gate~~ | ~~Med~~ | ~~M~~ | ~~ROADMAP t2~~ |
| ~~18~~ done — T11: options-readme-drift check | ~~Module README options-table drift guard~~ | ~~Low~~ | ~~M~~ | ~~ROADMAP t2~~ |
| ~~19~~ done — T12: boot-mirror-vm green, CI 43447887478 | ~~boot-mirror runtime VM leg~~ | ~~Med~~ | ~~L~~ | ~~ROADMAP t2~~ |
| ~~20~~ done — T8: Dependabot live; Renovate owner-opt-in (ROADMAP) | ~~Renovate/Dependabot for flake inputs (+ CI action pinning, §g Q3)~~ | ~~Low~~ | ~~M~~ | ~~ROADMAP t2~~ |
| ~~21~~ done — T9: devShell + --help + PARALLEL | ~~Harness devShell (bash/git/rsync) + run.sh --help + parallel legs~~ | ~~Low~~ | ~~M~~ | ~~ROADMAP (ergonomics)~~ |
| ~~22~~ done — T9: tests-wiring check | ~~Auto-count check: tests/*.nix vs flake wiring (kills the d.3 class)~~ | ~~Low~~ | ~~S~~ | ~~ROADMAP (ergonomics)~~ |
| 23 **→ open — ROADMAP docs-automation idea** | Per-module option tables generated from options-json output | Low | M | ROADMAP (docs automation) |
| ~~24~~ done — FEATURES testing/infra sections split | ~~FEATURES infra table split shipped vs pending~~ | ~~Low~~ | ~~S~~ | ~~ROADMAP (docs automation)~~ |
| 25 **→ open — ROADMAP docs-automation idea** | lib/README fork ledger with per-helper SystemNix consumer counts, generated | Low | M | ROADMAP (docs automation) |
| ~~26~~ done — T16: parked with evidence — statix has no custom-rule API (ROADMAP) | ~~Statix custom rule: unparenthesized select over application~~ | ~~Low~~ | ~~M~~ | ~~ROADMAP~~ |

## g) Questions (cannot be answered from this repo)

1. **Push now?** origin/master is ~8 commits behind and v0.1.0 exists only
   locally. The standing rule (never push without an explicit request) plus
   the CI-first-run dependency both wait on one word from you. SHA-pinning
   preference for the workflow's actions is part of Q3 below.
2. **`.config/metadata.yaml`** (carried, third report asking): which tool
   owns/generates it, and may docs sessions populate `tags`, or would that
   collide with its generator?
3. **CI action pinning policy:** floating major tags (`@v5`, `@v17`) as
   shipped, or SHA-pinned refs (supply-chain hygiene at the cost of manual
   bumps until Renovate lands)? This is a policy call, not a fact I can look
   up for you.

— End of report. Waiting for instructions.
