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
# usage: modloc [-l go|rust] [<repo> [<repo>...]]   (no <repo> = current dir)
set -euo pipefail

usage() {
	cat <<'EOF'
usage: modloc [-l go|rust] [<repo> [<repo>...]]

Count code lines per logical module (the nearest go.mod or Cargo.toml), not
per repository.

  -l go|rust   attribute by go.mod (default) or by Cargo.toml
  -h, --help   show this help and exit

Options may appear anywhere. With no <repo>, the current directory is
scanned. Exit codes: 0 ok, 1 a path is not a directory, 2 usage error.
EOF
}

usage_error() {
	echo "modloc: $*" >&2
	echo "run 'modloc --help' for usage" >&2
	exit 2
}

lang="go"
repos=()
while [[ $# -gt 0 ]]; do
	case "$1" in
	-l)
		[[ $# -ge 2 ]] || usage_error "option -l needs a value (go or rust)"
		lang="$2"
		shift 2
		;;
	-h | --help)
		usage
		exit 0
		;;
	--)
		shift
		repos+=("$@")
		break
		;;
	-*)
		usage_error "unknown option: $1 (use -- before a path that starts with -)"
		;;
	*)
		repos+=("$1")
		shift
		;;
	esac
done

case "$lang" in
go)
	ext="go"
	marker="go.mod"
	other="rust"
	;;
rust)
	ext="rs"
	marker="Cargo.toml"
	other="go"
	;;
*)
	usage_error "unknown language '$lang' for -l (expected go or rust)"
	;;
esac

[[ ${#repos[@]} -gt 0 ]] || repos=(".")

for repo in "${repos[@]}"; do
	if [[ ! -d "$repo" ]]; then
		echo "modloc: not a directory: $repo" >&2
		exit 1
	fi
done

printf 'repo\tmodule\tfiles\tcode\tcomment\tblank\tlines\n'

for repo in "${repos[@]}"; do
	mods=$(
		cd -- "$repo" &&
			{
				find . \( -name vendor -o -name target -o -name node_modules -o -name .git \) -prune -o -name "$marker" -print ||
				echo "modloc: unreadable paths under '$repo' were skipped; the table covers the readable tree" >&2
			} |
				sed -e 's|/[^/]*$||' -e 's|^\./||' -e 's|^\.$|.|' | sort -u | jq -Rsc 'split("\n")[:-1]'
	)

	rows=$(
		(cd -- "$repo" && scc --by-file --format json .) |
			jq -r --arg repo "$repo" --argjson mods "$mods" --arg ext ".$ext" '
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
	)
	if [[ -n "$rows" ]]; then
		printf '%s\n' "$rows"
	else
		echo "modloc: no .$ext files under '$repo'; for $other run: modloc -l $other '$repo'" >&2
	fi
done
