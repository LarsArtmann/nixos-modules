# Collection lib

The systemd hardening spine, extracted from SystemNix `lib/default.nix`
(portable half only — everything here depends on nixpkgs lib and nothing else).

## Split contract (R2, 2026-11-11)

**Moved here:** `harden`, `hardenUser`, `serviceDefaults*`,
`serviceOneshotDefaults*`, `onFailure`/`onFailureP0` (NOTE: they reference
`notify-failure@%n.service` template units — providing those templates is a
consumer-side concern), `serviceTypes` (generic option helpers only),
`mkPortGuard`, `mkStateDir`, `mkPoolDirUnit`, `mkSqliteBackupUnit`,
`mkMetricTextfileCollector`, `unitExecText`, `extractPortLiterals`,
`mkSecretCheck`, `mkDesktopNotifyService`, `ioTier`, `wrapWithMemoryLimit`,
`mkFilesystem` (`filesystems.nix`, moved 2026-11-12 — the cross-filesystem
mount-option contamination guard).

**Stayed SystemNix (fleet-bound):** `mkOidcGate`, `mkDnsGate` (dnsblockd
budget semantics), `ports` registry, `mkHttpCheck`/`discordAlert` (gatus
fleet monitoring), `rocm`, buildcache helpers, the Pocket ID
`oidcClientType` (lib/types.nix keeps it SystemNix-side).

## Forked-during-migration

SystemNix `lib/default.nix` KEEPS its local copies while its not-yet-migrated
modules consume them (109 files import `harden` from the SystemNix path; recount 2026-11-12);
`lib/filesystems.nix` is forked the same way (SystemNix keeps its own
`mkFilesystem` copy until its consumers move). The copies are deleted
helper-by-helper as consumers migrate to the collection module imports; the
final kill (re-pointing SystemNix `lib/default.nix` at this lib via the flake
input) happens when the last consumer moves. Parity diffs + negative-test
legs guard against value drift between the copies in the meantime.

**Divergence ledger (the standing parity diff must absorb or bless these):**

- `parseMemoryBytes` bare-byte fix — CLOSED both sides 2026-11-13 (SystemNix
  carries the identical fix + a `lib-parse-memory` regression check).
- `mkDesktopNotifyService` harden-call shape (mkMerge-wrapper-as-args →
  plain attrset union) — CLOSED both sides 2026-11-13, found by the
  collection's lib-eval contracts (T4).
- `watch.sh` GW-comment wording — OPEN: comment-only, the SystemNix copy's
  wording is locally true for its wiring (SUPERB plan T6 blesses or absorbs).
