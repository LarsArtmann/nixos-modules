#!/usr/bin/env bash
# tests/negative/run.sh — copy-mutate-prove harness for collection modules.
#
# Method ported verbatim from SystemNix scripts/negative-test-lints.sh (the
# 2026-08-27 round-2 harness): copy the git-tracked file set with working-tree
# contents but WITHOUT .git (a plain-directory flake sees ALL files, so
# mutations always take effect), apply ONE mutation per case, then
# `nix build --impure` the contract check FROM THE COPY and assert:
#   expect=fail → build fails AND the log contains the contract marker
#                 (an unrelated eval error does NOT count)
#   expect=pass → build succeeds (green controls)
#
# Never trust an exit-0 check you wrote without proving it FAILS on the
# historical bug shape it was built from.
#
# Usage:
#   bash tests/negative/run.sh                  # all cases
#   CASES=bootmirror bash tests/negative/run.sh # filter by case group
#   KEEP=1 bash tests/negative/run.sh           # keep workdir for triage
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SYSTEM="$(uname -m)-linux"
WORK="$(mktemp -d "${XDG_CACHE_HOME:-$HOME/.cache}/negative-collection.XXXXXX")"
[ "${KEEP:-0}" = "1" ] || trap 'rm -rf "$WORK"' EXIT

# Sweep stale workdirs from runs whose session died before the EXIT trap
# fired; scratch is rebuildable, 48h is past any triage window, and a live
# run's own mtime is always fresh — concurrency-safe.
find "${XDG_CACHE_HOME:-$HOME/.cache}" -maxdepth 1 -type d \
	-name 'negative-collection.*' -mmin +2880 -exec rm -rf {} + 2>/dev/null

FILTER="${CASES:-}"
passed=0
failed=0

LOG="${CASES_LOG:-$HOME/.cache/negative-collection/cases.log}"
mkdir -p "$(dirname "$LOG")"
: >"$LOG"

say() {
	printf '%s\n' "$*"
	printf '%s\n' "$*" >>"$LOG"
}

make_copy() {
	local dir="$WORK/$1"
	mkdir -p "$dir"
	(cd "$REPO_ROOT" && git ls-files -z | rsync -a --files-from=- --from0 . "$dir/")
	printf '%s' "$dir"
}

build_check() {
	local dir="$1" check="$2"
	nix build --impure -L --no-link --print-out-paths \
		--expr "(builtins.getFlake \"path:$dir\").checks.$SYSTEM.$check" 2>&1
}

# run_case <group> <name> <check> <expect: fail|pass> <marker-regex> <sed-file> <sed-expr>|-
run_case() {
	local group="$1" name="$2" check="$3" expect="$4" marker="$5" file="$6" expr="$7"

	if [ -n "$FILTER" ] && [[ ",$FILTER," != *",$group,"* ]]; then
		return 0
	fi

	local dir
	dir=$(make_copy "$group-$name")

	if [ "$expr" != "-" ]; then
		if ! sed -i "$expr" "$dir/$file"; then
			say "FAIL [$group/$name]: harness bug — sed failed on $file"
			failed=$((failed + 1))
			return 0
		elif ! cmp -s "$REPO_ROOT/$file" "$dir/$file"; then :; else
			say "FAIL [$group/$name]: harness bug — mutation was a no-op on $file"
			failed=$((failed + 1))
			return 0
		fi
	fi

	local out status=0
	out=$(build_check "$dir" "$check") || status=$?

	case "$expect" in
	fail)
		if [ "$status" -eq 0 ]; then
			say "FAIL [$group/$name]: mutation PASSED the $check build — phantom-green contract (marker: $marker)"
			failed=$((failed + 1))
		elif ! grep -qE "$marker" <<<"$out"; then
			say "FAIL [$group/$name]: build failed but marker '$marker' absent — caught by accident, not the contract:"
			grep -m3 'error:' <<<"$out" | sed 's/^/    /'
			failed=$((failed + 1))
		else
			say "PASS [$group/$name]: $check failed with the expected marker"
			passed=$((passed + 1))
		fi
		;;
	pass)
		if [ "$status" -eq 0 ]; then
			say "PASS [$group/$name]: $check correctly stayed green"
			passed=$((passed + 1))
		else
			say "FAIL [$group/$name]: $check should have stayed green but failed:"
			grep -m3 -E 'error:|contract' <<<"$out" | sed 's/^/    /'
			failed=$((failed + 1))
		fi
		;;
	*)
		say "FAIL [$group/$name]: harness bug — unknown expect value '$expect' (silent fall-through class)"
		failed=$((failed + 1))
		;;
	esac
}

# ── bootmirror: the 2026-10-17 gen-922 stale-boot class ──
# These legs moved from SystemNix scripts/negative-test-lints.sh when the
# module was delegated to the collection (the mutations target the module
# source, which now lives HERE).
run_case bootmirror green-control boot-mirror-contract pass - \
	'modules/boot-mirror/default.nix' '-'
run_case bootmirror watcher-dropped boot-mirror-contract fail 'PathChanged must watch' \
	'modules/boot-mirror/default.nix' 's|loader/entries"\];|loader/entriez"];|'
# The condition mutation trips the module's OWN self-pinned assertion (its
# message wins over the test pin — the contract gate surfaces module
# assertions first), so the marker is the module's wording.
run_case bootmirror condition-dropped boot-mirror-contract fail 'the mount condition must stay' \
	'modules/boot-mirror/default.nix' 's|ConditionPathIsMountPoint = mirror;|ConditionPathIsMountPoint = src;|'
run_case bootmirror nofail-dropped boot-mirror-contract fail 'stay nofail' \
	'modules/boot-mirror/default.nix' 's|"nofail"|"nofail-mutated"|'
run_case bootmirror tier-stripped boot-mirror-contract fail 'background IO tier' \
	'modules/boot-mirror/default.nix' 's|^          ioTier.background$|          { }|'

# ── hottier: the wants-not-requires + *Directory= trap classes ──
run_case hottier green-control hot-tier-contract pass - \
	'modules/hot-tier/default.nix' '-'
run_case hottier wants-dropped hot-tier-contract fail 'must want \(NOT require\) the journal mount' \
	'modules/hot-tier/default.nix' 's|^            wants = \[(mountUnit m.mountPoint)\];$|            # wants stripped for negative test|'
run_case hottier neutralization-dropped hot-tier-contract fail 'must neutralize the upstream LogsDirectory' \
	'modules/hot-tier/default.nix' 's|^                LogsDirectory = lib.mkForce \[\];$|                # neutralization stripped for negative test|'
run_case hottier heal-renamed hot-tier-contract fail 'ownership-heal chown ExecStartPre must be present' \
	'modules/hot-tier/default.nix' 's|logdir-own|logdir-mutated|'
run_case hottier nofail-dropped hot-tier-contract fail 'mount options must stay exactly' \
	'modules/hot-tier/default.nix' 's|^        "nofail"$|        "nofail-mutated"|'

# ── hotdirmigrate: the live-writer guard, 226/NAMESPACE, phantom-binary,
#    and boot-gating classes ──
run_case hotdirmigrate green-control hot-dir-migrate-contract pass - \
	'modules/hot-dir-migrate/default.nix' '-'
run_case hotdirmigrate liveness-stripped hot-dir-migrate-contract fail 'liveness sweep must be present' \
	'modules/hot-dir-migrate/default.nix' 's|pidDir in /proc|pidDir in /procX|'
run_case hotdirmigrate rwpaths-narrowed hot-dir-migrate-contract fail 'ReadWritePaths must be exactly' \
	'modules/hot-dir-migrate/default.nix' 's|^              cfg.projectsDir$|              "/projects-mutated"|'
run_case hotdirmigrate bootgated-restored hot-dir-migrate-contract fail 'must NOT be boot-gated' \
	'modules/hot-dir-migrate/default.nix' 's|^        unitConfig.RequiresMountsFor = \[cfg.mountPoint\];$|        wantedBy = ["multi-user.target"];\n        unitConfig.RequiresMountsFor = [cfg.mountPoint];|'
run_case hotdirmigrate cap-stripped hot-dir-migrate-contract fail "CAP_SYS_PTRACE" \
	'modules/hot-dir-migrate/default.nix' 's|CAP_CHOWN CAP_FOWNER CAP_DAC_OVERRIDE CAP_SYS_PTRACE|CAP_CHOWN CAP_FOWNER CAP_DAC_OVERRIDE|'
run_case hotdirmigrate flock-dropped hot-dir-migrate-contract fail 'must carry util-linux' \
	'modules/hot-dir-migrate/default.nix' 's|^          pkgs.util-linux$|          # util-linux stripped|'

# ── wififailover: the gateway-resolution + dual-wan conflict classes ──
# The mutations build the VIOLATING CONFIG in the contract fixture (the
# module's assertions must throw); the check itself is wifi-failover-contract.
run_case wififailover green-control wifi-failover-contract pass - \
	'tests/wifi-failover-contract.nix' '-'
run_case wififailover gateway-null wifi-failover-contract fail 'needs a gateway' \
	'tests/wifi-failover-contract.nix' 's|gateway = "192.168.9.1";|gateway = null;|'
run_case wififailover dual-wan-conflict wifi-failover-contract fail 'conflicts with services.dual-wan' \
	'tests/wifi-failover-contract.nix' 's|dualWanEnabled = false;|dualWanEnabled = true;|'

# ── lib: the pure-eval contracts (tests/lib-eval.nix) must bite ──
run_case lib green-control lib-eval pass - \
	'lib/systemd.nix' '-'
run_case lib lifecycle-guard-stripped lib-eval fail 'lifecycle keys must throw' \
	'lib/systemd.nix' 's|^    "ExecStart"$|    "ExecStartMutated"|'
run_case lib fs-guard-stripped lib-eval fail 'contamination guard must throw' \
	'lib/filesystems.nix' 's|prefix = "discard=async";|prefix = "discard=asyncMutated";|'
run_case lib iotier-drifted lib-eval fail 'ioTier.build must stay BE/7' \
	'lib/default.nix' 's|IOSchedulingPriority = 7;|IOSchedulingPriority = 3;|'

# ── optionsjson: the path-provenance proof (tests/options-json.nix) must
#    bite — a wrong expected-suffix makes every declaration "outside
#    territory" and the provenance throw fires ──
run_case optionsjson green-control options-json pass - \
	'tests/options-json.nix' '-'
run_case optionsjson provenance-broken options-json fail 'provenance broken for' \
	'tests/options-json.nix' 's|hasSuffix "/modules/|hasSuffix "/modules-mutated/|'

say "----"
say "passed=$passed failed=$failed"
[ "$failed" -eq 0 ]
