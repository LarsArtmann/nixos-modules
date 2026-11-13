# tests-wiring: kills the count-drift class mechanically. Every top-level
# tests/*.nix file must be referenced by flake.nix (an unwired test file is
# a silent no-op — the 7→8→10 AGENTS-count churn was this class, found by
# hand three times before this check existed), and every ./tests/ reference
# in flake.nix must name an existing file (a dangling wiring rots after a
# rename). Both directions proven from the flake TEXT, not a duplicated
# list — the check cannot itself drift from the wiring it guards.
{
  lib,
  pkgs,
}: let
  flakeText = builtins.readFile ../flake.nix;
  testFiles =
    lib.filter
    (name: lib.hasSuffix ".nix" name)
    (builtins.attrNames (builtins.readDir ./.));

  referenced =
    lib.filter
    (name: lib.hasInfix "./tests/${name}" flakeText)
    testFiles;
  unwired = lib.subtractLists referenced testFiles;

  # Every ./tests/<x>.nix path literal in the flake text must exist on
  # disk (flake.nix uses unquoted Nix path literals for imports).
  mentioned = lib.split "\\./tests/\\([a-zA-Z0-9._-]+\\.nix\\)" flakeText;
  # split yields non-matched segments (strings) and matches (lists with the
  # capture at index 0); keep only captured file names.
  mentionedFiles =
    map
    (part:
      if builtins.isList part
      then builtins.head part
      else null)
    mentioned;
  mentionedNames = lib.filter (x: x != null) mentionedFiles;
  dangling = lib.subtractLists testFiles mentionedNames;
in
  if unwired != []
  then throw "tests-wiring: tests/ file(s) never wired into flake.nix: ${lib.concatStringsSep ", " unwired} — wire them or delete them (an unwired test is a silent no-op)"
  else if dangling != []
  then throw "tests-wiring: flake.nix references missing test file(s): ${lib.concatStringsSep ", " dangling} — fix the wiring after the rename"
  else
    pkgs.runCommand "tests-wiring" {} ''
      echo "tests-wiring: ${toString (builtins.length testFiles)} test files, all wired both ways (files→flake, flake→files)" > $out
    ''
