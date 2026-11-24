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
$ modloc ~/projects/some-monorepo
repo                    module   files  code  comment  blank  lines
/home/lars/proj/x       cmd/foo  537    7344  1012     1333   9690
...
$ modloc -l rust ~/projects/collector-utils
```

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

Attribution semantics are pinned by `checks.*.modloc-contract`: the real
wrapped binary runs against a nested-module fixture in both languages and
the full TSV body is diffed against the expected rows.
