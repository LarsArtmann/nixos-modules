# modloc "does not work in webphone": root cause, CLI hardening, contract + negative group, session status & self-review

**2026-11-25 01:05 CET · session-scope report (owner question → diagnosis → fix in nixos-modules → proof on the built binary; landing on evo-x2 in flight, not mine)**

Scope line (verified vs claimed): The session ran in the SystemNix crush
shell but every edit landed in **nixos-modules**, so this report lives there.
VERIFIED this session, each with the command named in the section —
reproduction on the deployed binary; `bash -n` + `shellcheck` clean on
`modules/modloc/modloc.sh` at nixos-modules `05b6917`;
`nix build .#checks.x86_64-linux.modloc-contract` rc=0 at `05b6917`
(`~/.cache/modloc-fix/09-contract-at-05b6917.log`, zero `modloc contract:`
failure markers); the REAL built package
`/nix/store/n5bcljvd6s2h4axi22qharzv073d8yaf-modloc` run bare inside
webphone → the two module rows, byte-identical to the old binary's
`modloc .` (`10-smoke-built.log`, 18-case matrix); negative harness
`CASES=modloc PARALLEL=0 bash tests/negative/run.sh` → `passed=8 failed=0`
(`04-negative-modloc.log`, tree state `5124049`, i.e. BEFORE the foreign
one-tab re-indent of `05b6917`); pure checks `formatting`,
`options-readme-drift`, `tests-wiring`, `module-list`, `modloc-contract`
rc=0 and `nix flake check --all-systems --no-build` → "all checks passed!"
(`06`/`07` logs, tree state `210eced`); `dprint check` clean on the five
edited markdown files; `nix run .#docs-gates -- run .` AFTER this report
and its harvest rows → rc=0, all ten gates PASS, 30 §f items parsed
(`11-docsgates-after.log`, 01:07); `git ls-remote origin master` =
`05b6917` (01:02).
Pinned: the code this report verified is nixos-modules `05b6917`; HEAD at
report time is `d983357` (= `05b6917` plus this report's first write).
SystemNix HEAD at report time is `1c2a3bf9f`; its committed lock reached
nixos-modules `210eced` by `caa2e0dab` (01:02:11) and its working-tree lock
was already `05b6917` at 01:03.
NOT verified — GitHub CI for `210eced` and `05b6917` (two runs
`in_progress` at 01:02, the first VM legs on this tree); every check I did
not build (lib-eval, the other contract checks, VM tests); the full negative
harness (only the `modloc` group ran); the fix LIVE on evo-x2's PATH (a
foreign `nix run .#deploy` started 01:02:46 and was still at step 1 at
01:08; live PATH still `kslmqjq6-modloc`, generation `system-1029`); behavior
inside the owner's interactive fish (probes ran in the agent bash tool
shell, `DIRENV_DIFF` set); parity diff (no `lib/` change); who re-indented
one line each in `modloc.sh` and the 08-58 report at 00:58:58.

Root cause in one paragraph: the owner typed bare `modloc` in webphone at
23:22:49 and `modloc --help` at 23:22:52 (`fish_history` 64236–64239; the
neighbouring history entry names a path that exists only in webphone).
`modloc` documented `<repo>` as a REQUIRED argument, so a zero-argument run
executed `for repo in "$@"` over nothing: it printed the table header and
exited 0. `--help` was parsed as a path (`cd --help` → exit 2, no stderr).
The tool worked only when given a path: `modloc .` in webphone returned the
two module rows (433 files / 68 850 code lines in the root module, 6 / 142
in `internal/arch/testdata/erraudit-rule-probes`). Nothing is specific to
webphone; every directory behaved the same.

---

## a) FULLY DONE

All items are committed by the auto-commit daemon and are on
`origin/master` (`git ls-remote` at 01:02; this session never ran
`git push`).

1. **Diagnosis** — reproduced every dead-end on the deployed binary
   `/nix/store/kslmqjq6…-modloc` (byte-identical to the repo source modulo
   the `writeShellApplication` preamble): bare run → header only, exit 0;
   `--help` → header + exit 2, empty stderr; `-h` → raw
   `cd: -h: invalid option`; `-l` → `$2: unbound variable`; a missing path
   → raw `cd` error; an empty directory → header only, exit 0; a tree with
   one unreadable subdirectory → `find: Permission denied`, exit 1, no rows.
2. **`modules/modloc/modloc.sh` CLI hardening** (`e627571`, `e7a8eca`) — no
   `<repo>` means the current directory; `-l go|rust`, `-h`/`--help` (usage
   on stdout, exit 0) and `--` parse anywhere; every path is validated
   BEFORE the header is printed (non-directory → exit 1, path named; usage
   problem → exit 2 with a pointer to `--help`); an empty scan prints the
   header and says so on stderr with the other language's command; an
   unreadable subdirectory drops only its own subtree and reports it, where
   the marker walk's `find` used to abort the whole scan through
   `pipefail`; `cd -- "$repo"` so a `-`-prefixed path works after `--`.
   Attribution math (the jq program) is byte-identical to the previous
   version (diffed).
3. **`tests/modloc-contract.nix`** (`e7a8eca`) — 15 legs with one
   `fail "<marker>"` line each: go + rust attribution, the until-now
   unexercised `OTHER` row, bare run = `.` (repo label `.`), `-l` after the
   path, `--`, `-h`/`--help` on stdout with empty stderr, `-h` after a
   path, three usage errors (exit 2, empty stdout), pre-validation (exit 1,
   empty stdout even with a valid path first), empty-scan notice, notice
   names the other language, `-`-prefixed path after `--`, unreadable
   subtree (degraded table + notice; probes its precondition and prints
   VACUOUS instead of passing silently on a privileged builder), eval PATH
   leg. Green at `05b6917`.
4. **Negative harness group `modloc`** (`tests/negative/run.sh`, `5124049`)
   — green control + 7 mutations, each required to fail the contract with
   its own marker: `cwd-default-dropped`, `help-dropped`,
   `prevalidate-dropped`, `dash-path-broken`, `other-relabeled`,
   `walk-tolerance-dropped`, `empty-notice-dropped`. Result `passed=8
   failed=0`. Harness totals by grep: 17 groups, 75 cases, 17 green
   controls.
5. **Docs** (`fa97d4b`, `81c28c7`, `210eced`) — module README usage
   section (bare run, options anywhere, exit codes, notices), README
   bullet, FEATURES (modloc row + harness counts 17/75/17), CHANGELOG
   `[Unreleased]` entry, AGENTS.md (stale "no application code, no CI"
   identity paragraph corrected, functional-check note, four gotchas:
   shellcheck-before-contract for mutations, zero-argument PATH tools,
   `cd --`, `find` under `pipefail`), a BLOCKED TODO row for the landing.
6. **Immediate answer for the owner** — `modloc .` works today with the
   deployed binary (verified 01:09 in webphone and in SystemNix, where the
   rows are `pkgs/ai-meter` and `pkgs/gatus-alert-relay`).
7. **Predecessor follow-ups closed by the above** (08-58 report rows):
   f.5 AGENTS.md identity, f.6 `OTHER` leg, f.7 invalid-`-l` + no-args
   legs, f.8 negative group, f.11 docs-gates run, f.15 usage/exit codes,
   f.16 `-l` anywhere. Observed already gone (not by this session): f.26
   `/tmp/bin/modloc`, `/tmp/bin/scc`, `/tmp/modloc-test` no longer exist.
8. **This report + its harvest** — `docs-gates freshness --dump-items`
   parses exactly the 30 §f rows of section f; every one is routed
   (TODO_LIST: the live-proof row (BLOCKED until the switch), the polish
   pass, CI watch, annotate, negative legs, two `(repo: SystemNix)` rows,
   four owner-call BLOCKED rows plus the extended tag-decision row, four
   hygiene rows; ROADMAP: the modloc feature ideas and
   `homeManagerModules`). The
   stale landing TODO row ("push, re-float") is corrected to what remains
   (post-switch proof), and the predecessor's unharvested row 22 is a
   BLOCKED row. The battery went from red (freshness + audit-all) to rc=0.

## b) PARTIALLY DONE

1. **Landing on evo-x2's PATH** — pushed (automation), SystemNix lock
   floated to `210eced` by 01:02:11 (committed in `caa2e0dab`; working
   tree already at `05b6917` at 01:03), a deploy started 01:02:46 that is
   not this session's (at step 2, configuration evaluation, 01:09). Open: the post-switch proof (bare `modloc` in webphone →
   rows; `/run/current-system` equals the newest `system-N-link`).
   Blocker: the foreign deploy must finish. Effort S once it switched.
2. **Polish pass on the new script** (planned, paused for this report) —
   `usage_error` hides that it exits (rename to `die_usage`); `other` is a
   vague name (`other_lang`); "not a directory" is said also for a path
   that does not exist (split into `no such directory`); no contract leg
   for a path containing spaces. Effort S; needs one contract + one
   negative-group re-run.
3. **Predecessor report annotation** — rows f.5/6/7/8/11/15/16 are done but
   the 08-58 report carries no `done at` marker (ANNOTATE not run).

## c) NOT STARTED

- CI result for the pushed tree (two runs in flight): VM legs, lib-eval,
  the other contract checks. CI is the first VM leg for this change.
- Tag decision for the modloc era (`[0.2.0]` + annotated tag vs riding
  master) and folding the `[Unreleased]` entries into it. Owner call.
- Upstream scc issue-first PR (decision + `github-voice` draft). Owner call.
- modloc features from the predecessor list: `--format json`, `--sort` /
  `--top`, `--exclude-dir`, `-l all`, fleet sweep, `--version`.
- `homeManagerModules` surface for PATH tools (on real demand); modloc on
  more hosts (owner call).
- SystemNix side of the landing: CHANGELOG line + FEATURES check for the
  fixed CLI, full buildflow + features-drift eval, the
  `prune-done-todos.sh:126` buildflow finding (predecessor f.12–f.14).

## d) TOTALLY FUCKED UP

1. **The shipped tool dead-ended on its most common invocation.** From the
   gen-1028 deploy until the next switch, a bare `modloc` printed one
   header line and exited 0, and `modloc --help` exited 2 with no message.
   Severity: user-facing ("does not work"), no data risk. Root cause: a
   required argument plus a zero-iteration loop plus no help path.
   Mitigation: `modloc .` today; the fix is on `origin/master` and in
   SystemNix's committed lock.
2. **A green contract check covered none of the user's path.** The
   predecessor check pinned attribution math on two fixtures while the CLI
   was unusable bare. The check now pins the CLI surface and the negative
   group proves each leg bites.
3. **One unreadable subdirectory killed the whole scan** (pre-existing,
   found by probe): `find` exits 1 on any permission error, `pipefail`
   turned that into an abort with a bare header. Fixed and pinned.
4. **Unattributed edit to my file mid-session.** At 00:58:58 something
   re-indented one continuation line in `modloc.sh` (5 tabs → 4) and one
   list continuation in the 08-58 report (daemon commit `05b6917`,
   whitespace only, behavior unchanged, re-verified at `05b6917`). Not
   reverted; the actor is unknown. A second session or a fleet formatter is
   active in this tree.
5. **My own errors, all caught before or right after landing:**
   - The first version of the fix broke `--` for `-`-prefixed paths
     (`cd "$repo"` parsed `-dash` as options). My smoke matrix caught it;
     fixed with `cd --`, now a contract leg and a mutation leg.
   - The first mutation for the notice leg replaced an `echo` with `true`
     and tripped shellcheck SC2034 (`other` became unused), which would
     have failed the build "by accident". Caught by dry-running every
     mutation before adding it to the harness.
   - A verification one-liner overwrote `FEATURES.md` with the HEAD copy
     mid-check (wrong `cp` source). A cache backup restored it inside the
     same command; nothing was lost and the daemon did not commit the
     intermediate state. In a tree where the daemon commits whatever is on
     disk, probe copies belong in `~/.cache`, never at a repo path.
   - I edited docs while the negative-harness group was copying the tree
     per case (harmless for that check by analysis, but against the
     "do not edit while a background job reads the tree" rule).
   - The harness result at `5124049` was not re-run after the `05b6917`
     re-indent; the mutations do not anchor on leading whitespace, but
     that is reasoning, not a run.
6. **Pre-existing debt observed, not fixed:** the 08-58 report's 30
   follow-up rows were never harvested into TODO_LIST (docs-gates counted
   one unharvested because the others match tokens that merely appear in
   living docs); `tests/negative/run.sh` carries a shellcheck SC2016 info
   (predecessor line 175); CHANGELOG 2026-11-22 says `dprint.json` was
   deleted and gitignored, yet it is tracked today (`git ls-files`) and
   not ignored (`git check-ignore`); every contract-check eval prints a
   `system.stateVersion` warning; the flake `apps` lack `meta`.

## e) WHAT WE SHOULD IMPROVE

1. **Harvest at authoring time, for real.** The freshness gate passes a row
   when two distinctive tokens merely occur somewhere in living docs, so
   "gate green" does not mean "tracked". Write the TODO/ROADMAP row when
   the report row is written. Impact: f.15 sat open for a day and the owner
   hit the bug. Fix: this report harvests its own rows and the predecessor's.
2. **Contract checks for a CLI must include the bare invocation.** Rule now
   in AGENTS.md (zero-argument PATH tools default to the current directory
   and never exit 0 on a bare header). Fix applied: `modloc` pins it.
3. **Every daemon push costs a full VM battery.** My seven commits became
   two CI runs; this report will trigger a third for a docs-only change.
   Suggested fix: path filters in `check.yml` (skip the VM job when the
   push touches only `docs/`, `*.md`), or a docs-only commit marker.
4. **Cross-repo sessions have no report-location rule.** Session cwd was
   SystemNix, every edit was nixos-modules; the report follows the edits,
   SystemNix keeps no pointer. Suggested fix: an owner ruling (see g.3).
5. **Mutation hygiene is checkable.** A small helper that dry-runs each
   `run_case` sed expression (file changed? `bash -n`? shellcheck clean?)
   before the build would have caught my SC2016 mutation in seconds.
6. **State the precondition of sandbox-dependent legs.** The unreadable
   subtree leg only bites in a sandboxed build; it now prints VACUOUS
   instead of passing silently. Copy that probe pattern.

## f) NEXT (prioritized; ⚠ = owner-gated, § = agent-runnable)

1. § Prove the modloc fix live on evo-x2 after the foreign deploy
   switched: bare `modloc` in webphone prints the two module rows and
   `/run/current-system` equals the newest `system-N-link`.
2. ⚠ Deploy decision if the 01:02:46 deploy blocks or fails: when to fire
   `nix run .#deploy` under the Tctl, PSI and quiescence gates.
3. § modloc polish pass: `die_usage` rename, `other_lang`, split `no such
   directory` from `not a directory`, spaced-path contract leg, re-run
   contract + `modloc` negative group.
4. § Watch CI for `210eced` and `05b6917` and read the VM legs (first VM
   run on this tree).
5. § ANNOTATE the 08-58 modloc report: rows f.5/6/7/8/11/15/16/26 done.
6. § Build `lib-eval` and the remaining contract checks once on the
   post-change tree (cheap, warm store).
7. § Add negative legs for `-l` after the path and for a spaced path
   (mutations must stay shellcheck-clean).
8. § SystemNix docs at the deploy: CHANGELOG line + FEATURES row check for
   the fixed CLI (doc-counts gate).
9. § modloc `--format json` per-module rows for tooling consumers.
10. § modloc `--sort code|lines|files|module` and `--top N`.
11. § modloc `--exclude-dir` extra prunes (default list stays).
12. § modloc `-l all` multi-language single pass.
13. § Fleet sweep: README note `modloc ~/projects/*` or a `--fleet` mode.
14. § `homeManagerModules` surface for PATH tools, on real demand.
15. § CI path filters: skip the VM battery on docs-only pushes.
16. ⚠ Tag decision for the modloc era: `[0.2.0]` + annotated tag vs riding
    master; folds the `[Unreleased]` entries.
17. ⚠ Upstream scc issue draft (`github-voice`) once the owner green-lights
    the issue-first PR.
18. ⚠ modloc on more hosts (rpi3-dns): probably no, desktop tool.
19. § (repo: SystemNix) run the full `buildflow` battery and the
    features-drift eval at the deploy.
20. § (repo: SystemNix) file or fix the `prune-done-todos.sh:126` buildflow
    finding (close-the-loop; verify pre-existence via `git log`).
21. § (repo: SystemNix) FEATURES: decide row + header re-stamp for modloc.
22. § Pin the negative-harness group and case counts cited in FEATURES
    (17 groups, 75 cases, 17 green controls today, grep-verified by hand).
23. § `modloc --version`.
24. § Set `system.stateVersion` in the contract-check fixtures to silence
    the eval warning every check prints.
25. § Add `meta` to the flake `apps` (`nix flake check` warns).
26. § Fix the SC2016 info at `tests/negative/run.sh:175` (escape the `$`
    in the sed expression).
27. § Reconcile `dprint.json`: CHANGELOG says deleted + gitignored, the
    file is tracked and not ignored.
28. ⚠ Report-location ruling for cross-repo sessions (report follows the
    edits vs the session's cwd repo).
29. § Trash `~/.cache/modloc-fix/` scratch after the live proof.
30. § `scc --by-module` design note for the upstream issue (marker set,
    nearest wins, formats), citing this check as the reference
    implementation.

## g) QUESTIONS (cannot be answered from the tree)

1. **Bare `modloc`: current directory, or usage error?** I shipped "no
   argument = scan the current directory" because that is how you typed it
   (bare run in webphone, 23:22:49) and because scc does the same. The
   predecessor report planned the opposite (`usage()` on no-args, f.15).
   Keep the default, or make a bare run print usage and exit 2?
2. **CI cost on this repo.** Every daemon push runs the full
   `nix flake check -L` including the VMs (two runs in flight for this
   session's commits, a third for this report). Do you want path-filtered
   CI that skips the VMs on docs-only pushes, or is a VM run per push the
   intended safety net?
3. **Where do cross-repo session reports belong?** This one is in
   nixos-modules because every edit landed there; SystemNix (the session's
   cwd, and the repo that deploys the fix) has no pointer. Rule wanted:
   report follows the edits (with or without a pointer row in the cwd
   repo), or report always goes to the cwd repo?
