{
  description = "LarsArtmann NixOS module collection — production modules (wifi failover, boot mirror, hot-disk tiering + migration), systemd hardening lib";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    treefmt-nix.url = "github:numtide/treefmt-nix";
  };

  outputs = {
    self,
    nixpkgs,
    treefmt-nix,
  }: let
    inherit (nixpkgs) lib;
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
        type
        == "directory"
        && !(lib.hasPrefix "_" name)
        && builtins.pathExists (./modules + "/${name}/default.nix")
    ) (builtins.readDir ./modules);
    nixosModules = lib.mapAttrs (name: _: ./modules + "/${name}") moduleDirs;
    modulesArePaths = builtins.all builtins.isPath (builtins.attrValues nixosModules);

    collectionLib = import ./lib lib;
  in
    assert modulesArePaths; {
      inherit nixosModules;

      lib = collectionLib;

      checks = forAllSystems (
        system: let
          pkgs = nixpkgs.legacyPackages.${system};
          treefmtEval = treefmt-nix.lib.evalModule pkgs ./treefmt.nix;
        in
          {
            formatting = treefmtEval.config.build.check self;
            # Portable checks — pure eval, no VM: run on every system. The
            # VM checks below stay x86_64-only (runNixOSTest qemu guests).
            lib-eval = import ./tests/lib-eval.nix {
              inherit lib pkgs;
              inherit collectionLib;
            };
            boot-mirror-contract = import ./tests/boot-mirror.nix {
              inherit lib pkgs;
              module = ./modules/boot-mirror;
            };
            hot-tier-contract = import ./tests/hot-tier-contract.nix {
              inherit lib pkgs;
              module = ./modules/hot-tier;
            };
            hot-dir-migrate-contract = import ./tests/hot-dir-migrate-contract.nix {
              inherit lib pkgs;
              module = ./modules/hot-dir-migrate;
            };
            wifi-failover-contract = import ./tests/wifi-failover-contract.nix {
              inherit lib pkgs;
              module = ./modules/wifi-failover;
            };
            module-list = pkgs.runCommand "module-list" {} ''
              # Forces evaluation of every discovered module path and records the
              # public surface; a change here shows up as a check-input diff.
              printf '%s\n' ${
                lib.concatStringsSep " " (lib.mapAttrsToList (name: path: "${name}=${toString path}") nixosModules)
              } > $out
              cat $out
            '';
            options-json = import ./tests/options-json.nix {
              inherit lib pkgs;
              modules = nixosModules;
            };
          }
          // lib.optionalAttrs (system == "x86_64-linux") {
            wifi-failover-vm = pkgs.testers.runNixOSTest (import ./tests/wifi-failover.nix {inherit pkgs;});
            hot-tier-journal-vm = pkgs.testers.runNixOSTest (import ./tests/hot-tier-journal.nix {inherit pkgs;});
            hot-tier-caddy-vm = pkgs.testers.runNixOSTest (import ./tests/hot-tier-caddy.nix {inherit pkgs;});
            hot-dir-migrate-vm = pkgs.testers.runNixOSTest (import ./tests/hot-dir-migrate.nix {inherit pkgs;});
          }
      );

      formatter = forAllSystems (
        system: let
          pkgs = nixpkgs.legacyPackages.${system};
          treefmtEval = treefmt-nix.lib.evalModule pkgs ./treefmt.nix;
        in
          treefmtEval.config.build.wrapper
      );
    };
}
