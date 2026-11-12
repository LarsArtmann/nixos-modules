<!-- docs/DOMAIN_LANGUAGE.md — the collection's ubiquitous language.
     Terms as the CODE uses them, not as a textbook would define them. -->

# Domain Language

Glossary of terms used across this collection and its consumer (SystemNix).
Definitions describe how the term is USED here, with where it lives.

## Glossary

| Term                        | Definition                                                                                                     | Where used                                             |
| --------------------------- | -------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------ |
| collection                  | This repository: reusable NixOS modules + the portable lib, consumed via flake inputs                            | `README.md`, everywhere                                |
| consumer                    | A host configuration (today: SystemNix) that imports collection modules/lib through a flake input at a pinned rev | `README.md`, module headers                            |
| fleet-bound                 | Helper logic tied to the LarsArtmann fleet (ports registry, gatus, OIDC/DNS gates, rocm, filesystems) — deliberately NOT in this collection | `lib/README.md` (split contract)                       |
| forked-during-migration     | The interim state where SystemNix keeps local copies of lib helpers while consumers move to collection imports; "the kill" is re-pointing SystemNix's lib at this flake once the last consumer moves | `lib/README.md`                                        |
| inert until enable          | Module design rule: a module changes nothing until `services.<name>.enable = true` is set                        | `README.md` design rules                               |
| delegation site             | The consumer-side place where a collection module is imported and fleet integrations (registry entries, monitoring) are layered on top | module headers, module READMEs                        |
| harden fragment            | The `harden {}` / `hardenUser {}` serviceConfig fragment carrying systemd sandboxing defaults                    | `lib/systemd.nix`                                      |
| lifecycle keys              | Unit keys that describe the service lifecycle (`ExecStart*`, `Type`, `Restart`, `RemainAfterExit`, …) — never legal inside a harden fragment; the fragment throws | `lib/systemd.nix`                                      |
| oneshot defaults            | `serviceOneshotDefaults`: Restart=no + a TimeoutStartSec floor — the only defaults valid for `Type=oneshot` units | `lib/systemd/service-defaults.nix`                     |
| berth pattern               | Port handoff discipline: never grant a berth because a process exited — release must be verified, and PID identity (start-time) must survive between check and signal | `lib/port-guard.nix` header                            |
| port guard                  | `mkPortGuard`: a `+`-privileged ExecStartPre script that kills FOREIGN listeners on a port, spares owner-unit listeners, and fails the start (named holder) if release cannot be verified | `lib/port-guard.nix`                                   |
| eval-contract check         | A check that evaluates a fixture host with a module enabled and pins observable unit shapes with `throwIfNot`; no VM needed when the contract is eval-observable | `tests/boot-mirror.nix`                                |
| negative leg / mutation leg | A test case that copies the tree, applies ONE mutation, and requires the build to FAIL with the specific contract marker — proving a green check actually bites | `tests/negative/run.sh`                                |
| green control               | The unmutated case in the negative harness: must stay green, proving the harness is wired to the right check      | `tests/negative/run.sh`                                |
| renames ledger              | `modules/_renames.nix`: permanent tombstones for breaking option changes (`mkRenamedOptionModule` / `mkRemovedOptionModule` + reason); consumers pin by rev, so aliases never expire | `modules/_renames.nix`                                 |
| byte-parity                 | Proof that an extracted helper is byte/semantically identical to the SystemNix original at extraction time       | `CHANGELOG.md`, `lib/README.md`                        |
| wants-not-requires          | systemd posture where a missing dependency (e.g. a detached mirror mount) condition-skips work instead of failing boot | `modules/boot-mirror/default.nix`                      |
| carrier                     | Physical link state readable at `/sys/class/net/<if>/carrier`; distinct from admin up/down — the kernel keeps static routes on carrier loss, which is the bug wifi-failover exists to fix | `modules/wifi-failover/`                               |
| ESP                         | EFI System Partition. boot-mirror keeps a 2nd ESP a verified byte-mirror of the primary, preserving per-ESP loader state (random-seed, boot counting) | `modules/boot-mirror/`                                 |
| boot counting               | systemd-boot's `+T` loader-entry suffix scheme: an entry rename per boot attempt, a blessing (suffix strip) once boot-complete.target is reached; boot-mirror reverse-propagates these renames so the mirror never resets a converging counter | `modules/boot-mirror/default.nix`                      |
| ioTier                      | BFQ I/O priority tier fragments (interactive → maintenance) merged into a unit's serviceConfig alongside `harden {}` | `lib/default.nix` (`ioTier`)                           |
| omit-on-error rule          | Metric collector discipline: when a source is unreadable, emit only the scrape_errors gauge and exit 0 — an omitted metric fails the alert, a frozen green one phantom-greens it | `lib/default.nix` (`mkMetricTextfileCollector`)        |

## Bounded contexts

| Context       | Term that shifts meaning                                                                                                                             |
| ------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------- |
| system vs user | `harden` vs `hardenUser` / `serviceDefaults` vs `serviceDefaultsUser`: the `*User` variants exist because Home Manager units reject `mkForce` priorities — same defaults, weaker merge priority |
| primary vs mirror | In boot-mirror, the PRIMARY ESP is the one the NixOS builder manages (sync source); the MIRROR is the 2nd disk copy (sync target). NixOS content flows primary → mirror only; loader-owned state flows mirror-side booted ESP → managed twin before the forward sync |
