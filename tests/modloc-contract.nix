# Functional contract check for the modloc module: the REAL wrapped binary
# (writeShellApplication over modloc.sh with scc + jq) runs against a
# nested-module fixture tree with known line counts, in BOTH languages, and
# the full TSV body is diffed against the expected rows — pinning the
# nearest-marker semantics: the nested go.mod claims ONLY its own subtree,
# root-module files land on ".", Rust workspace-root strays land on the
# workspace row, and rows sort by code lines descending. The eval leg pins
# that enabling the module puts the package on environment.systemPackages.
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

  expectedGo = pkgs.writeText "modloc-expected-go" (
    lib.concatStringsSep "\n" [
      header
      (tsvRow "${fixture}" "." 2 3)
      (tsvRow "${fixture}" "internal/y" 2 2)
    ]
  );
  expectedRust = pkgs.writeText "modloc-expected-rust" (
    lib.concatStringsSep "\n" [
      header
      (tsvRow "${fixture}" "." 1 3)
      (tsvRow "${fixture}" "crates/one" 1 2)
      (tsvRow "${fixture}" "crates/two" 1 1)
    ]
  );

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

    ${modlocPkg}/bin/modloc ${fixture} > go.out
    diff -u ${expectedGo} go.out

    ${modlocPkg}/bin/modloc -l rust ${fixture} > rust.out
    diff -u ${expectedRust} rust.out

    echo "modloc-contract: nearest-marker attribution pinned (go + rust legs, eval PATH leg)" >&2
  ''
