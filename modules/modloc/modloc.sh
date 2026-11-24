#!/usr/bin/env bash
# modloc — count code per logical module (nearest go.mod / Cargo.toml), not per repo.
#
# PROBLEM: monorepos hold zero-to-many nested modules (go.mod submodules,
# Cargo workspace crates). Repo-wide counters (scc, tokei, cloc) report ONE
# total; "how much Go code lives in each module" needs per-file attribution,
# and running a counter once per module directory double-counts everything
# nested (a submodule's files belong to it, not to the enclosing module).
#
# SOLUTION: one `scc --by-file --format json` scan per repo, then attribute
# every file to its NEAREST enclosing marker directory (longest-prefix wins;
# vendor/target/node_modules pruned from the marker walk). Files with no
# enclosing marker land on "." when the repo root is itself a module, else
# "OTHER". Semantics proven against a real multi-module monorepo and pinned
# by tests/modloc-contract.nix.
#
# usage: modloc [-l go|rust] <repo> [<repo>...]
set -euo pipefail

lang="go"
if [[ "${1:-}" == "-l" ]]; then lang="$2"; shift 2; fi
case "$lang" in
  go)   ext="go"; marker="go.mod" ;;
  rust) ext="rs"; marker="Cargo.toml" ;;
  *) echo "usage: modloc [-l go|rust] <repo> [<repo>...]" >&2; exit 2 ;;
esac

printf 'repo\tmodule\tfiles\tcode\tcomment\tblank\tlines\n'

for repo in "$@"; do
  mods=$(cd "$repo" && find . \( -name vendor -o -name target -o -name node_modules -o -name .git \) -prune -o -name "$marker" -print \
    | sed -e 's|/[^/]*$||' -e 's|^\./||' -e 's|^\.$|.|' | sort -u | jq -Rsc 'split("\n")[:-1]')

  (cd "$repo" && scc --by-file --format json .) \
    | jq -r --arg repo "$repo" --argjson mods "$mods" --arg ext ".$ext" '
        def moddir($f):
          [$mods[]
           | . as $m
           | select($f | startswith($m + "/"))]
          | (map(length) | max) as $len
          | if ($len // 0) == 0
            then (if ($mods | index(".")) then "." else "OTHER" end)
            else map(select(length == $len)) | .[0]
            end;

        [ .[].Files[]
          | (.Location | ltrimstr("./")) as $loc
          | select($loc | endswith($ext))
          | { mod: moddir($loc), lines: .Lines, code: .Code, comment: .Comment, blank: .Blank } ]
        | group_by(.mod)
        | map({ module: .[0].mod, files: length,
                code:    (map(.code)    | add // 0),
                comment: (map(.comment) | add // 0),
                blank:   (map(.blank)   | add // 0),
                lines:   (map(.lines)   | add // 0) })
        | sort_by(-.code)[]
        | [$repo, .module, (.files|tostring), (.code|tostring), (.comment|tostring), (.blank|tostring), (.lines|tostring)]
        | @tsv
      '
done
