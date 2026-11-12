# Changelog

All notable changes to the collection are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/).

---

- **wifi-failover: first module, extracted from SystemNix (2026-11-11/12)** — the pilot wave of the collection plan: `modules/wifi-failover/` (module + colocated `watch.sh` + README), the 5-scenario VM test (`checks.x86_64-linux.wifi-failover-vm`, veth peer admin-state = cable carrier), and the systemd lib spine (`lib/` — harden, serviceDefaults family, unit generators, `unitExecText`/`extractPortLiterals` audit scan surface; forked-during-migration from SystemNix's `lib/default.nix`, byte-parity proven at extraction). New vs the SystemNix original: a `gateway` option (nullOr str; null derives from `networking.defaultGateway`, eval-time assertion + graceful placeholder) replacing the `networking.local.gateway` fleet coupling. SystemNix consumes it at rev `0a8d9731` through a delegation layer; parity proven twice (semantic unit-diff empty + build-level script content identity). Rev `0a8d973` is the SystemNix-locked snapshot; later tree churn is formatting only.
