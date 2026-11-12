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
run_case bootmirror condition-dropped boot-mirror-contract fail 'ConditionPathIsMountPoint' \
  'modules/boot-mirror/default.nix' 's|ConditionPathIsMountPoint = mirror;|ConditionPathIsMountPoint = src;|'
run_case bootmirror nofail-dropped boot-mirror-contract fail 'stay nofail' \
  'modules/boot-mirror/default.nix' 's|"nofail"|"nofail-mutated"|'
run_case bootmirror tier-stripped boot-mirror-contract fail 'background IO tier' \
  'modules/boot-mirror/default.nix' 's|^      ioTier.background$|      { }|'

say "----"
say "passed=$passed failed=$failed"
[ "$failed" -eq 0 ]
