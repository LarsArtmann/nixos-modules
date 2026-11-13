# Status Report — TODO-List Execution Batch + Brutal Self-Review

**Date:** 2026-11-13 22:00 (Friday)
**Session scope:** Execute the actionable TODO_LIST.md rows (7 of 10; 3 owner-blocked), full manual gate flow, docs sync. This report covers ONLY this session's run and what I noticed in passing.

---

## a) FULLY DONE (verified, not assumed)

| # | Item                                                                                | Proof                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       |
| - | ----------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1 | **SystemNix `flake.lib` anomaly — root-caused AND fixed** (was "flagged for owner") | Reproduced live (`attribute 'genAttrs' missing` through `.lib.harden`), isolated with marker probes (captured lib was literally `["lib"]`-shaped), root cause: `import ./lib { inherit (nixpkgs) lib; }` passes the WRAPPER attrset to a SIMPLE `lib:` parameter (simple params bind the whole argument; only `{ lib }:` patterns select the field). Fixed SystemNix-side to `import ./lib lib` (their flake.nix:1696) with the trap documented at the call site; `.lib.harden` + `.lib.serviceOneshotDefaults` verified through the flake output; lib-parse-memory NOTE rewritten mystery→root cause; parity 22/22 green before AND after. |
| 2 | **docs-gates pinned as flake input** (locked rev `eb2fa6bc`)                        | flake input + `docs-gates run .` bare in `nix develop` + `nix run .#docs-gates -- run .` app; devShell builds (x86_64), binary runs, aarch64 eval passes; floating `github:` ref fully removed (flake.nix, devShell hook, AGENTS). Battery 5/5 PASS over the current corpus.                                                                                                                                                                                                                                                                                                                                                                |
| 3 | **Negative harness per-group transcripts**                                          | Outcome lines + build-output tails to `~/.cache/negative-collection/groups/<group>.log`; failing groups print in full after the summary; green runs delete the dir. Verified green (optionsjson group) AND forced-failure (broken marker → transcript surfaced + kept).                                                                                                                                                                                                                                                                                                                                                                     |
| 4 | **boot-mirror diff-gate eval pin + mutation leg**                                   | Sync script hoisted to `syncText`; module self-asserts the gate's invocation shape + refusal message; `diffgate-stripped` leg proves it (group 7/7 green); boot-mirror-vm re-proven green after the hoist; README contract list updated.                                                                                                                                                                                                                                                                                                                                                                                                    |
| 5 | **Parity-diff cadence documented in CI**                                            | check.yml header documents both standing manual gates (parity needs the SystemNix sibling; harness needs `--impure`) + always-green `::notice` reminder step. YAML validated.                                                                                                                                                                                                                                                                                                                                                                                                                                                               |
| 6 | **`nix flake update` manual flow**                                                  | Lock refreshed — every tip already current (nixpkgs `d4f25a3e`, treefmt-nix `0d6d739a`, docs-gates `eb2fa6bc`; no-op rev-wise, lock gained docs-gates' transitive closure). Gates: `nix flake check -L` GREEN (5 VMs + all pure checks incl. the parallel session's new audit contracts), aarch64 `--all-systems --no-build` green, parity 22/22, harness **63/63**.                                                                                                                                                                                                                                                                        |
| 7 | **Docs sync**                                                                       | CHANGELOG bullet (7 shipped items), TODO_LIST rewritten (7 rows removed → "Shipped" section; 3 blocked rows remain), AGENTS updated (anomaly gotcha → root cause + fix; docs-gates pinned invocation; harness transcript hint). dprint.json drift-readd trashed (deliberately removed in 1701745, resurrected by heuristic auto-commit 9148c0d — restored the documented state).                                                                                                                                                                                                                                                            |

---

## b) PARTIALLY DONE

- **SystemNix fix — verified narrowly, not fleet-wide.** I proved `.lib.harden`/`serviceOneshotDefaults` through the output and ran parity; I did NOT run SystemNix's own full `nix flake check` (their docs say one eval walk costs ~20GB RSS / 4-7min) and did not eval every `.lib` consumer. Risk is low (the output was BROKEN before — the fix can hardly regress what never worked), but the claim "fixed" rests on two probes + parity, not their whole check suite.
- **CHANGELOG bullet quality.** Written before the final harness run; I had to patch a stale case count ("49" vs the true 63/63 with A1b groups) AFTER the fact. Caught in self-review, fixed — but it shipped wrong for ~30 minutes inside the session.

---

## c) NOT STARTED (owner-blocked, not forgotten)

- **v0.1.1 patch tag decision** (owner question g3) — content exists, tag doesn't. Now arguably v0.2.0-scale given the A1b wave + this batch.
- **`.config/metadata.yaml` owner/generator** (§g Q3) — I did not investigate this session (explicitly out of scope).
- **Dependabot reviewers/assignees config** — owner preference unknown.

---

## d) TOTALLY FUCKED UP (honest ledger)

1. **The anomaly hunt: I forgot basic Nix call semantics under pressure.** The very first probe (`__capturedLibAttrs = ["lib"]`) carried the answer — attrNames of the _argument wrapper_. I then observed `import file {lib={a=1;}}` → `names=["lib"]` in a clean file and called it "impossible"/"quantum weirdness", then burned significant time theorizing about flake-parts module-system wrapping, `types.unique`, nix output wrappers — even building a minimal flake-parts repro that was _never the culprit_. The minimal flake-parts repro DID have value (ruled out SystemNix-specific causes) but the true decisive test (`arg: {...}` called with `{arg=X}` returns `["arg"]` — correct simple-param semantics) sat in front of me for a long stretch. **Root cause of the confusion: I conflated `param: body` with `{param}: body` while debugging.**
2. **Risky probe workflow in a foreign repo.** I edited SystemNix's flake.nix/lib with temporary markers while an auto-commit daemon runs there. It happened to not commit mid-probe (verified), but the window existed. Should have used non-file probes (separate eval expressions) or a single fast edit-revert.
3. **First diffgate mutation was phantom-green and I nearly shipped it.** My first sed (`s|diff -r|diff -q|`) matched BOTH the script and the pin's copy of the fragment — mutating them consistently so the assertion still passed. The harness's own phantom-green detector caught it (working as designed). I then documented the anchored-mutation rule in the case comment — good recovery, sloppy first attempt.
4. **Botched edit placement mid-fix.** One SystemNix edit landed as nested `flake.flake.lib` (wrong indentation context in my old_string) — caught and fixed immediately by re-reading, but it's the exact class the AGENTS whitespace rules warn about.

---

## e) WHAT WE SHOULD IMPROVE (systemic, from this run)

1. **A "simple-parameter vs attrset-pattern" lint/lesson is missing.** The SystemNix bug lived for weeks because the mis-call shape is invisible to every formatter. The lesson is now in AGENTS (both repos' context), but a statix-style lexical check (`import <path> { inherit (x) lib; }` against a file whose first token is a bare `lib:`) is authorable — parked unless it recurs.
2. **docs-gates lock bloat vs isolation.** Pinning grew flake.lock from 3 nodes to 24 (docs-gates' transitive Go-dep closure). I deliberately did NOT add `follows` (their pins may be load-bearing for their FODs; SystemNix's infra-follows doctrine covers eval-only deps only). The tradeoff is undocumented anywhere — should be one line in AGENTS or reversed deliberately.
3. **Text-shape pins are reformat-brittle.** The diff-gate pin fires on legitimate flag reordering of the diff invocation. Acceptable (documented), but if it false-positives once, the pin fragments should move to a canonical constant both the script and the assert read.
4. **The harness transcript tail includes stateVersion warning spam** — cosmetic noise in every transcript; a `grep -v` filter would raise signal.
5. **Deprecation hygiene:** used `nix flake lock --update-input` (deprecated alias) once; should be `nix flake update <input>`.
6. **App meta warnings** (`app lacks attribute 'meta'`) — house pattern, pre-existing for all three apps; nix 2.34 wants `meta` on app defs. Cheap to add.

---

## f) NEXT — up to 50 things, ranked

1. **Owner: v0.1.1 vs v0.2.0 tag decision** (blocked; the batch + A1b wave is v0.2.0-scale content).
2. Fix FEATURES.md: add rows for this batch (harness transcripts, docs-gates pin, diff-gate leg) — not done this session.
3. SystemNix: run their `nix flake check --no-build` once to bless the flake.lib fix beyond the two probes.
4. SystemNix: their working tree also carries a bank-sync lock bump I didn't author — needs an owner eyeball before push.
5. Add `meta` to the three flake apps (silences nix 2.34 warnings).
6. Filter `stateVersion` warning spam from harness transcripts.
7. Decide + document docs-gates `follows` policy (lock bloat vs upstream-pin isolation).
8. `metadata.yaml` §g Q3: identify generator (owner answer or a 10-min file-content/proc investigation next session).
9. Dependabot reviewers/assignees (owner preference).
10. boot-mirror: consider a runtime VM scenario where the diff gate itself fires (rsync-success-but-divergent simulation) — the eval pin proves presence, not runtime firing.
11. Author the simple-param-vs-pattern lexical lint (parked; only on recurrence).
12. Consider `nix flake update docs-gates` cadence note in AGENTS dependency policy (single-input bumps).
13. The A1b session still owes SystemNix delegation layers + parity re-run (their stated plan; not mine to do).
14. Sweep AGENTS "Commands" for `--update-input` deprecations (none documented, keep it that way).
15. options-json: the transcript warning spam also appears there — same grep-v filter could apply to `build_check` output generally.
16. ROADMAP: record the "consistent-mutation phantom-green" trap as a harness-authoring rule candidate (formalize anchor-on-script-only-context).
17. Pin or vendor the `.docs-gates.json` `$schema` URL (points at main — floats).
18. aarch64 BUILD proof of the devShell (eval-only today; needs aarch64 builders).
19. Consider wiring `docs-gates` battery as an optional flake check (`--impure`? likely impossible — document why not instead).
20. CHANGELOG: my batch bullet is a wall of text; future bullets should split per-item lines.
21. (Room for 29 more — deliberately not padded: everything else I noticed is already covered above or is the other session's scope.)

---

## g) QUESTIONS I CANNOT ANSWER MYSELF (max 3)

1. **Tag decision:** cut `v0.1.1` now (two lib fixes only, per the original row) or `v0.2.0` once the A1b audit wave + this batch are pushed? The content is CI-green either way; version semantics are yours.
2. **metadata.yaml (§g Q3):** which tool created `.config/metadata.yaml` (2026-11-12 14:23, `tags: []`, auto-commit 229f441), and may docs sessions populate `tags`? If you didn't create it manually, say so and I'll investigate the generator next session.
3. **docs-gates lock policy:** keep its 21 transitive lock nodes pinned to upstream's own pins (my choice: isolation, zero FOD risk) or collapse eval-only deps via `follows` (SystemNix infra-follows doctrine: smaller lock, but rebuilds the battery against OUR nixpkgs)?

---

## Verdict

7/7 actionable rows shipped, every gate green (`nix flake check -L`, aarch64 eval, parity 22/22, harness 63/63, docs-gates 5/5), one long-standing cross-repo bug actually root-caused instead of annotated. The cost: a debugging detour where I briefly forgot how function application works, one phantom-green harness leg caught by the harness itself, and a CHANGELOG count patched post-hoc. The system's guardrails (phantom-green detection, marker forcing, parity) caught every mistake I made before it shipped red.
