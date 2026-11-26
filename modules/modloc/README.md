# modloc

Lines of code per **logical module** — the nearest enclosing `go.mod` /
`Cargo.toml` — instead of per repository. One `scc --by-file --format json`
scan per repo; every file is attributed to its deepest enclosing module
directory, so nested modules never double-count, workspace-root strays land
on the root module row (`.`), and files with no enclosing marker at all land
on `OTHER`. `vendor/`, `target/`, and `node_modules/` are pruned from the
marker walk. The counting engine is nixpkgs' `scc`, so language and comment
detection follow the channel.

> **Frozen since 2026-11-26.** This bash CLI is superseded by the standalone
> Go repository [`LarsArtmann/modloc`](https://github.com/LarsArtmann/modloc),
> which prints this same table and adds typed flags, a real `--help` and
> `--version`, and more output formats. The module stays here, unchanged and
> working, until its consumer cuts over; then it is retired through
> `modules/_renames.nix`. New CLI features land in the successor. The steps
> and their order: [Successor and cutover](#successor-and-cutover).

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

## Successor and cutover

Why a Go successor: this script shipped three argument-parsing bug classes
in two days (a bare run printed only the header, `--help` was read as a
path, `cd` read a leading `-` as an option, an unbound `$2`), each of which
typed flags prevent by construction; and it was the collection's only
application code inside a pure-module flake library. The successor keeps
`scc` as its counting engine, run as a process, so the channel promise
above is unchanged. Parity at decision time (2026-11-26): identical stdout
and exit codes on 10 cases, both contract fixtures included. Decision
record: `docs/status/2026-11-26_06-05_modloc-extraction-decision-go-repo-scaffold-self-review.md`.

Order matters. Retiring this module before every consumer has switched
turns each consumer's evaluation red (`nixosModules.modloc` stops
existing), and SystemNix floats on this repository's `master`.

1. **Consumer cutover (owner-gated; happens in the consumer's own repo).**
   In SystemNix, add the input beside `nixos-modules` in `flake.nix`:
   ```nix
   modloc = {
     url = "github:LarsArtmann/modloc";
     inputs.nixpkgs.follows = "nixpkgs";
   };
   ```
   Lock it with `nix flake update modloc`. Every sub-input the new flake
   brings needs a `follows` line, like the ones `nixos-modules` already
   has: the lock-audit gate rejects deep copies of inputs the root already
   pins. Then in `systems/evo-x2.nix` replace
   `inputs.nixos-modules.nixosModules.modloc` with
   `inputs.modloc.nixosModules.modloc`; the `programs.modloc.enable = true;`
   line stays, the successor declares the same option. Deploy, then prove
   it on the host: `modloc --version` prints the successor's version, and a
   bare `modloc` inside a repository prints its module rows.
2. **Retire here, only after step 1 is live.** Remove `modules/modloc/` and
   `tests/modloc-contract.nix`; drop the `modloc-contract` entry from
   `flake.nix` and "and the modloc per-module LOC CLI" from the flake
   description; drop the `modloc` group and its two `ALL_GROUPS` mentions
   from `tests/negative/run.sh`; drop the module row from `FEATURES.md` and
   its entry in `README.md`; re-pin the harness counts (16 groups, 67
   cases, 16 green controls). In `tests/readme-drift.nix`, reword the
   comment that cites this module as the example for a `programs.<name>.`
   module; the logic stays, it derives the prefix from the declared
   surface. Add the tombstone to `modules/_renames.nix` so a consumer that
   still sets the option gets a named reason instead of a silent no-op:
   ```nix
   {lib}: {
     imports = [
       (lib.mkRemovedOptionModule ["programs" "modloc"]
         "modloc moved to github:LarsArtmann/modloc on 2026-11-26; import its nixosModules.modloc, which declares the same programs.modloc.enable")
     ];
   }
   ```
   A consumer that switched in step 1 must not import that entry: the
   successor declares the option, and the two would collide.
3. **Gates after step 2:** `nix flake check`, the negative harness
   (`bash tests/negative/run.sh`), and `nix flake check --all-systems
   --no-build`.
