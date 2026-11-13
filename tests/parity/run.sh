#!/usr/bin/env bash
# tests/parity/run.sh — standing semantic parity diff between this
# collection's lib and the SystemNix fork. The mechanized guard behind
# lib/README.md's forked-during-migration contract (prose guard →
# standing check, SUPERB T7).
#
# Method: evaluate BOTH libs over the SAME nixpkgs instance, call every
# value-comparable helper with identical inputs (tests/parity/probe.nix),
# normalize (overrides unwrap, derivations → names, store hashes → <h>),
# and require identical JSON. Byte diffs are meaningless — comments and
# formatting diverge legitimately; VALUES must not.
#
# Usage:
#   bash tests/parity/run.sh                     # against the default checkout
#   SYSTEMNIX_PATH=/path/to/SystemNix bash tests/parity/run.sh
#   KEEP_JSON=1 bash tests/parity/run.sh         # keep the rendered probes
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SYSTEMNIX="${SYSTEMNIX_PATH:-$HOME/projects/SystemNix}"

if [ ! -f "$SYSTEMNIX/lib/default.nix" ]; then
	echo "parity-diff: no SystemNix checkout at $SYSTEMNIX (set SYSTEMNIX_PATH)" >&2
	exit 2
fi

OUT="$(mktemp -d "${XDG_CACHE_HOME:-$HOME/.cache}/parity-diff.XXXXXX")"
if [ "${KEEP_JSON:-0}" != "1" ]; then
	trap 'rm -rf "$OUT"' EXIT
else
	echo "parity-diff: probe JSON kept in $OUT" >&2
fi

SYSTEM="$(uname -m)-linux"

nix eval --impure --raw --expr "
  let
    flake = builtins.getFlake \"path:$REPO_ROOT\";
    lib = flake.inputs.nixpkgs.lib;
    pkgs = flake.inputs.nixpkgs.legacyPackages.$SYSTEM;
    verdict = import \"$REPO_ROOT/tests/parity/probe.nix\" {
      inherit lib pkgs;
      collectionLib = flake.lib;
      forkLib = import \"$SYSTEMNIX/lib\" lib;
    };
  in builtins.toJSON verdict
" > "$OUT/verdict.json"

summary="$(jq -r 'if .ok then "parity-diff: OK — \(.probes | length) helper probes semantically identical (collection lib vs SystemNix fork)" else .error end' "$OUT/verdict.json")"

if grep -q '"ok":true' "$OUT/verdict.json"; then
	echo "$summary"
else
	echo "parity-diff: DRIFT — see the probe output below:" >&2
	cat "$OUT/verdict.json" >&2
	exit 1
fi
