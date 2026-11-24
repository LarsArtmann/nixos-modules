# Functional contract check for the modloc module: the REAL wrapped binary
# (writeShellApplication over modloc.sh with scc + jq) runs against
# nested-module fixture trees with known line counts, in BOTH languages, and
# the full TSV body is diffed against the expected rows — pinning the
# nearest-marker semantics: the nested go.mod claims ONLY its own subtree,
# root-module files land on ".", Rust workspace-root strays land on the
# workspace row, files outside EVERY marker land on "OTHER", and rows sort by
# code lines descending.
#
# The CLI legs pin the argument contract added after the first live run
# (2026-11-24: a bare `modloc` printed only the header and exited 0, read as
# "does not work"): no <repo> means the current directory, -l and -h/--help
# parse anywhere, every path is validated BEFORE the header is printed
# (exit 1), a usage error exits 2, an empty scan says so on stderr, and an
# unreadable subdirectory degrades the scan instead of aborting it. Every leg
# fails with its own `modloc contract:` marker so the negative harness can
# prove each one bites (tests/negative/run.sh, group modloc).
#
# The eval leg pins that enabling the module puts the package on
# environment.systemPackages.
{
  lib,
  pkgs,
  module,
}: let
  # Fixture: root go.mod + nested go.mod + cargo workspace. Line counts are
  # chosen so every expected row is distinct (no sort ties → no jq
  # stability dependence in the pinned output).
  #   go:   "." 3 code (main.go 1 + internal/x/x.go 2), "internal/y" 2 (y.go + deep/d.go)
  #   rust: "." 3 (src/root.rs), "crates/one" 2, "crates/two" 1
  fixture = pkgs.runCommand "modloc-fixture" {} ''
    mkdir -p $out/internal/x $out/internal/y/deep $out/crates/one/src $out/crates/two/src $out/src
    printf '%s\n' 'module example.com/root' > $out/go.mod
    printf '%s\n' 'package main' > $out/main.go
    printf '%s\n' 'package x' 'func X() {}' > $out/internal/x/x.go
    printf '%s\n' 'module example.com/root/y' > $out/internal/y/go.mod
    printf '%s\n' 'package y' > $out/internal/y/y.go
    printf '%s\n' 'package d' > $out/internal/y/deep/d.go
    printf '%s\n' '[workspace]' 'members = ["crates/one", "crates/two"]' > $out/Cargo.toml
    printf '%s\n' '[package]' 'name = "one"' > $out/crates/one/Cargo.toml
    printf '%s\n' 'fn a() {}' 'fn b() {}' > $out/crates/one/src/lib.rs
    printf '%s\n' '[package]' 'name = "two"' > $out/crates/two/Cargo.toml
    printf '%s\n' 'pub fn two() {}' > $out/crates/two/src/lib.rs
    printf '%s\n' 'fn r1() {}' 'fn r2() {}' 'fn r3() {}' > $out/src/root.rs
  '';

  # Marker-less root: only sub/ carries a go.mod, so the root stray (3 code)
  # lands on "OTHER" ahead of "sub" (2 code).
  stray = pkgs.runCommand "modloc-stray-fixture" {} ''
    mkdir -p $out/sub
    printf '%s\n' 'package stray' 'func S1() {}' 'func S2() {}' > $out/stray.go
    printf '%s\n' 'module example.com/stray/sub' > $out/sub/go.mod
    printf '%s\n' 'package sub' 'func B() {}' > $out/sub/b.go
  '';

  eval = lib.nixosSystem {
    system = "x86_64-linux";
    modules = [
      module
      {
        programs.modloc.enable = true;
        fileSystems."/" = {
          device = "/dev/vda1";
          fsType = "ext4";
        };
        boot.loader.grub.devices = ["nodev"];
      }
    ];
  };

  modlocPkg = eval.config.programs.modloc.package;
  onPath = builtins.any (p: p == modlocPkg) eval.config.environment.systemPackages;

  tsvRow = repo: mod: files: code:
    lib.concatStringsSep "\t" [repo mod (toString files) (toString code) "0" "0" (toString code)];
  header = lib.concatStringsSep "\t" ["repo" "module" "files" "code" "comment" "blank" "lines"];

  # table <repo-label> <rows>: the header followed by the given rows, in order.
  table = repo: rows:
    (lib.concatStringsSep "\n" ([header] ++ map (row: tsvRow repo row.module row.files row.code) rows))
    + "\n";

  goRows = [
    {
      module = ".";
      files = 2;
      code = 3;
    }
    {
      module = "internal/y";
      files = 2;
      code = 2;
    }
  ];
  rustRows = [
    {
      module = ".";
      files = 1;
      code = 3;
    }
    {
      module = "crates/one";
      files = 1;
      code = 2;
    }
    {
      module = "crates/two";
      files = 1;
      code = 1;
    }
  ];

  expectedGo = pkgs.writeText "modloc-expected-go" (table fixture goRows);
  expectedGoDot = pkgs.writeText "modloc-expected-go-dot" (table "." goRows);
  expectedRust = pkgs.writeText "modloc-expected-rust" (table fixture rustRows);
  expectedStray =
    pkgs.writeText "modloc-expected-stray"
    (table stray [
      {
        module = "OTHER";
        files = 1;
        code = 3;
      }
      {
        module = "sub";
        files = 1;
        code = 2;
      }
    ]);
  headerOnly = pkgs.writeText "modloc-header-only" (header + "\n");
  expectedDegraded =
    pkgs.writeText "modloc-expected-degraded"
    (table "tree" [
      {
        module = ".";
        files = 1;
        code = 2;
      }
    ]);
  expectedDash =
    pkgs.writeText "modloc-expected-dash"
    (table "-dash" [
      {
        module = ".";
        files = 1;
        code = 1;
      }
    ]);

  contract =
    lib.throwIf (!onPath)
    "modloc contract: programs.modloc.enable must put the package on environment.systemPackages"
    (builtins.toJSON {inherit onPath;});
in
  pkgs.runCommand "modloc-contract" {
    inherit contract;
    passAsFile = ["contract"];
  } ''
    cp "$contractPath" $out
    fail() {
      echo "modloc contract: $*" >&2
      exit 1
    }

    ${modlocPkg}/bin/modloc ${fixture} > go.out
    diff -u ${expectedGo} go.out || fail "nearest-marker attribution drifted (go)"

    ${modlocPkg}/bin/modloc -l rust ${fixture} > rust.out
    diff -u ${expectedRust} rust.out || fail "nearest-marker attribution drifted (rust)"

    ${modlocPkg}/bin/modloc ${stray} > stray.out
    diff -u ${expectedStray} stray.out || fail "files outside every marker must land on OTHER"

    (cd ${fixture} && ${modlocPkg}/bin/modloc) > bare.out
    diff -u ${expectedGoDot} bare.out || fail "a bare run must scan the current directory"

    ${modlocPkg}/bin/modloc ${fixture} -l rust > rust-late.out
    diff -u ${expectedRust} rust-late.out || fail "-l must be accepted after a repo argument"

    ${modlocPkg}/bin/modloc -- ${fixture} > dashdash.out
    diff -u ${expectedGo} dashdash.out || fail "-- must end the options"

    for flag in -h --help; do
      ${modlocPkg}/bin/modloc $flag > help.out 2> help.err || fail "help must exit 0"
      head -n 1 help.out | grep -Fqx 'usage: modloc [-l go|rust] [<repo> [<repo>...]]' || fail "help must print the usage line on stdout"
      grep -F 'current directory is' help.out || fail "help must document the current-directory default"
      [ ! -s help.err ] || fail "help must print nothing on stderr"
    done
    ${modlocPkg}/bin/modloc ${fixture} -h > help-late.out || fail "-h must be accepted after a repo argument"
    diff -u help.out help-late.out || fail "-h must print the same help wherever it appears"

    expect_usage() {
      marker="$1"
      shift
      rc=0
      ${modlocPkg}/bin/modloc "$@" > usage.out 2> usage.err || rc=$?
      [ "$rc" -eq 2 ] || fail "$marker (exit $rc, want 2)"
      [ ! -s usage.out ] || fail "$marker: a usage error must print nothing on stdout"
      grep -F "run 'modloc --help' for usage" usage.err || fail "$marker: stderr must point at --help"
    }
    expect_usage "-l without a value is a usage error" -l
    expect_usage "an unknown -l language is a usage error" -l bogus ${fixture}
    expect_usage "an unknown option is a usage error" --bogus

    rc=0
    ${modlocPkg}/bin/modloc ${fixture} /no/such/dir > bad.out 2> bad.err || rc=$?
    [ "$rc" -eq 1 ] || fail "a non-directory must exit 1"
    [ ! -s bad.out ] || fail "every path must be validated before the header is printed"
    grep -F 'modloc: not a directory: /no/such/dir' bad.err || fail "the offending path must be named"

    mkdir empty-tree
    (cd empty-tree && ${modlocPkg}/bin/modloc) > empty.out 2> empty.err || fail "an empty scan must exit 0"
    diff -u ${headerOnly} empty.out || fail "an empty scan must print the header and no rows"
    grep -F "modloc: no .go files under '.'" empty.err || fail "an empty scan must say so on stderr"
    (cd empty-tree && ${modlocPkg}/bin/modloc -l rust) > empty-rust.out 2> empty-rust.err
    grep -F "modloc: no .rs files under '.'; for go run: modloc -l go '.'" empty-rust.err || fail "the empty notice must name the other language"

    mkdir -- -dash
    printf '%s\n' 'module example.com/dash' > -dash/go.mod
    printf '%s\n' 'package dash' > -dash/d.go
    ${modlocPkg}/bin/modloc -- -dash > dash.out || fail "a path starting with - must scan after --"
    diff -u ${expectedDash} dash.out || fail "a path starting with - must scan after --"

    mkdir -p tree/inner
    printf '%s\n' 'module example.com/tree' > tree/go.mod
    printf '%s\n' 'package main' 'func F() {}' > tree/a.go
    printf '%s\n' 'module example.com/tree/inner' > tree/inner/go.mod
    printf '%s\n' 'package inner' > tree/inner/b.go
    chmod 000 tree/inner
    if [ -r tree/inner ]; then
      echo "modloc contract: unreadable-subtree leg is VACUOUS here (this builder reads a mode-000 directory)" >&2
    else
      ${modlocPkg}/bin/modloc tree > unreadable.out 2> unreadable.err || fail "an unreadable subdirectory must not abort the scan"
      diff -u ${expectedDegraded} unreadable.out || fail "an unreadable subdirectory must only drop its own subtree"
      grep -F 'were skipped; the table covers the readable tree' unreadable.err || fail "a degraded scan must say so on stderr"
    fi

    echo "modloc-contract: nearest-marker attribution + CLI contract pinned (go + rust legs, eval PATH leg)" >&2
  ''
