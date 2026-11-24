# modloc — lines of code per logical module (nearest go.mod / Cargo.toml),
# not per repository.
#
# PROBLEM: repo-wide counters (scc, tokei, cloc) report ONE total for a
# monorepo; "how much Go code lives in each go.mod submodule / Cargo crate"
# needs per-file attribution, and running a counter once per module
# directory double-counts nested modules.
#
# SOLUTION: the colocated modloc.sh (wrapped via writeShellApplication with
# scc + jq) runs one `scc --by-file --format json` scan per repo and
# attributes every file to its NEAREST enclosing marker directory (longest
# prefix wins; vendor/target/node_modules pruned). This module only puts it
# on PATH — the counting engine is nixpkgs' scc, so language coverage
# follows the channel. First programs.* module in the collection: a PATH
# tool is not a service; options-readme-drift derives the prefix from the
# declared surface so both conventions coexist.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.programs.modloc;
  inherit (lib) mkEnableOption mkIf mkOption types;

  modloc = pkgs.writeShellApplication {
    name = "modloc";
    runtimeInputs = [
      pkgs.scc
      pkgs.jq
    ];
    text = builtins.readFile ./modloc.sh;
  };
in {
  options.programs.modloc = {
    enable = mkEnableOption "modloc, a per-module (go.mod / Cargo.toml) lines-of-code counter backed by scc";

    package = mkOption {
      type = types.package;
      default = modloc;
      defaultText = "writeShellApplication over the module's modloc.sh (scc + jq)";
      description = "The modloc derivation to put on PATH.";
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [cfg.package];
  };
}
