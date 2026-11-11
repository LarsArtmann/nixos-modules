{
  description = "LarsArtmann NixOS module collection — pattern modules, eval-time audit gates, systemd hardening lib";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    treefmt-nix.url = "github:numtide/treefmt-nix";
  };

  outputs =
    {
      self,
      nixpkgs,
      treefmt-nix,
    }:
    let
      lib = nixpkgs.lib;
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = lib.genAttrs systems;

      # Auto-discover collection modules: every subdirectory of modules/ with a
      # default.nix becomes nixosModules.<dirname>. `_`-prefixed dirs are helpers
      # (renames ledger, shared fixtures) and are skipped.
      # Modules are exposed as PATHS, never import-applied: options rendered from
      # an import-applied module lose their "declared in" provenance in
      # options.json and every options browser (verified against
      # NuschtOS/search docs + nixos-hardware's `import = path: path` trick).
      # The assert below is the introspection leg: adding an import-applied
      # module fails `nix flake check` immediately.
      moduleDirs = lib.filterAttrs (
        name: type:
        type == "directory"
        && !(lib.hasPrefix "_" name)
        && builtins.pathExists (./modules + "/${name}/default.nix")
      ) (builtins.readDir ./modules);
      nixosModules = lib.mapAttrs (name: _: ./modules + "/${name}") moduleDirs;
      modulesArePaths = builtins.all builtins.isPath (builtins.attrValues nixosModules);

      collectionLib = import ./lib { inherit lib; };
    in
    assert modulesArePaths; {
      inherit nixosModules;

      lib = collectionLib;

      checks = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          treefmtEval = treefmt-nix.lib.evalModule pkgs ./treefmt.nix;
        in
        {
          formatting = treefmtEval.config.build.check self;
        }
        // lib.optionalAttrs (system == "x86_64-linux") {
          module-list = pkgs.runCommand "module-list" { } ''
            # Forces evaluation of every discovered module path and records the
            # public surface; a change here shows up as a check-input diff.
            printf '%s\n' ${
              lib.concatStringsSep " " (lib.mapAttrsToList (name: path: "${name}=${toString path}") nixosModules)
            } > $out
            cat $out
          '';
        }
      );

      formatter = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          treefmtEval = treefmt-nix.lib.evalModule pkgs ./treefmt.nix;
        in
        treefmtEval.config.build.wrapper
      );
    };
}
