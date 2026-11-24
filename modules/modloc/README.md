# modloc

Lines of code per **logical module** — the nearest enclosing `go.mod` /
`Cargo.toml` — instead of per repository. One `scc --by-file --format json`
scan per repo; every file is attributed to its deepest enclosing module
directory, so nested modules never double-count, workspace-root strays land
on the root module row (`.`), and files with no enclosing marker at all land
on `OTHER`. `vendor/`, `target/`, and `node_modules/` are pruned from the
marker walk. The counting engine is nixpkgs' `scc`, so language and comment
detection follow the channel.

## Usage

```console
$ cd ~/projects/some-monorepo && modloc
repo      module    files  code  comment  blank  lines
.         cmd/foo     537   7344     1012   1333   9690
...
$ modloc ~/projects/some-monorepo             # explicit path(s): same table
$ modloc -l rust ~/projects/collector-utils
$ modloc ~/projects/a ~/projects/b -l rust    # options may appear anywhere
$ modloc --help
```

With no `<repo>`, the current directory is scanned. Every path is validated
before anything is printed: a path that is not a directory exits 1 and is
named, a usage problem exits 2. A scan that matches no file still prints the
header and says so on stderr, and an unreadable subdirectory drops only its
own subtree (one line on stderr) instead of aborting the scan.

Columns: `repo module files code comment blank lines`, sorted by code lines
descending.

## Options

| Option    | Type    | Default                         | Description                      |
| --------- | ------- | ------------------------------- | -------------------------------- |
| `enable`  | bool    | `false`                         | Put modloc on the system PATH    |
| `package` | package | wrapped `writeShellApplication` | The modloc derivation to install |

## Consumption

```nix
{
  inputs.nixos-modules.url = "github:LarsArtmann/nixos-modules";
}
```

```nix
{
  programs.modloc.enable = true;
}
```

Attribution semantics and the CLI contract above are pinned by
`checks.*.modloc-contract`: the real wrapped binary runs against nested-module
fixtures in both languages, the full TSV body is diffed against the expected
rows, and every CLI behavior carries its own failure marker. The `modloc`
group of `tests/negative/run.sh` mutates each of those behaviors away and
requires the check to fail.
