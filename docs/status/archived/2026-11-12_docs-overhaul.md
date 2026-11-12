# Docs overhaul — first docs-health audit (2026-11-12)

First full docs-health AUDIT of the collection (BUILD + VERIFY; HARVEST was a
no-op: no prior `docs/status/` reports existed to harvest). Quality gate green
at audit time: `nix flake check` — all checks passed; `tests/negative/run.sh`
— 5/5 PASS (green control + 4 mutation legs).

## Findings (all resolved in-audit)

1. ~~README.md "Modules" section was a scaffold placeholder ("populated as
   modules land") while two modules had already shipped~~ done — the section
   now lists wifi-failover and boot-mirror with links and test posture
   (README.md, "Modules").
2. ~~SECURITY.md claimed "Automated security scanning runs in CI" but the
   repository has no CI at all~~ done — replaced with the truthful statement
   that automated checks run through `nix flake check` (SECURITY.md,
   "Security Practices").
3. ~~CHANGELOG.md lacked entries for the boot-mirror extraction and the
   negative mutation harness (both shipped)~~ done — both entries appended,
   plus one entry for this docs overhaul (CHANGELOG.md, newest-first order).
4. ~~Living docs missing entirely: FEATURES.md, TODO_LIST.md, ROADMAP.md,
   docs/DOMAIN_LANGUAGE.md~~ done — all four built from code with mandatory
   evidence columns; FEATURES.md deliberately carries two
   PARTIALLY_FUNCTIONAL rows (serviceTypes, audit scan surface) instead of
   rounding up.
5. ~~AGENTS.md absent (no session context file)~~ done — created earlier the
   same day; verified by this audit: every documented command exercised, no
   temporal pollution, within the 5-15 KB size budget.

## §f) Follow-ups (all routed — none left to discover here)

- wifi-failover eval assertions have no negative mutation legs → routed:
  TODO_LIST.md, High impact, row 1.
- lib pure helpers lack in-repo eval tests (parity with SystemNix proven at
  extraction only) → routed: TODO_LIST.md, High impact, row 2.
- watch.sh header comment names the SystemNix-era gateway option
  (`config.networking.local.gateway`) instead of this repo's resolution →
  routed: TODO_LIST.md, Medium impact, row 1.
- aarch64-linux runs only the formatting check although two checks are pure
  eval and portable → routed: TODO_LIST.md, Medium impact, row 2.
- dprint.json is enforced by nothing (treefmt runs alejandra only) → routed:
  TODO_LIST.md, Low impact, row 1.
- negative harness reachable only by its raw path (no app/devShell entry) →
  routed: TODO_LIST.md, Low impact, row 2.

Archived at creation: every numbered finding above is resolved inline and
every follow-up is routed into TODO_LIST.md — the content is settled.
