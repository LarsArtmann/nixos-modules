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
input) happens when the last consumer moves. Parity is GUARDED MECHANICALLY
since 2026-11-13 (SUPERB T7):

```sh
bash tests/parity/run.sh            # or: nix run .#parity-diff
# SYSTEMNIX_PATH=/other/checkout bash tests/parity/run.sh
```

22 value-comparable helpers are called with identical inputs through both
libs (same nixpkgs instance), normalized (mkOverride unwrapped, derivations
→ names, store hashes → `<h>`), and required to render identical JSON —
byte diffs never matter, VALUE drift fails the run naming the probe and
both sides. `serviceTypes` and `ports` are skipped by design (option
constructors with type-function payloads — not value-comparable; covered by
lib-eval contracts on both sides). Bite-proven: a one-value fork mutation
fails the run. Run it after every lib change on either side.

**Divergence ledger (absorbed divergences the standing diff must stay aware of):**

- `parseMemoryBytes` bare-byte fix — CLOSED both sides 2026-11-13 (SystemNix
  carries the identical fix + a `lib-parse-memory` regression check).
- `mkDesktopNotifyService` harden-call shape (mkMerge-wrapper-as-args →
  plain attrset union) — CLOSED both sides 2026-11-13, found by the
  collection's lib-eval contracts (T4).
- `watch.sh` GW-comment wording — ABSORBED 2026-11-13: SystemNix no longer
  carries a copy at all (its wifi-failover module is fully delegated to this
  collection's flake input, rev-pinned in its lock; only the fleet-specific
  gateway feed `networking.local.gateway` remains SystemNix-side). No open
  divergences remain.
