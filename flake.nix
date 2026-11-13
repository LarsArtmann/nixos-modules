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
            timeout-audit-contract = import ./tests/timeout-audit-contract.nix {
              inherit lib pkgs;
              module = ./modules/timeout-audit;
            };
            start-limit-audit-contract = import ./tests/start-limit-audit-contract.nix {
              inherit lib pkgs;
              module = ./modules/start-limit-audit;
            };
            tmp-cleaner-audit-contract = import ./tests/tmp-cleaner-audit-contract.nix {
              inherit lib pkgs;
              module = ./modules/tmp-cleaner-audit;
            };
            systemd-shape-audit-contract = import ./tests/systemd-shape-audit-contract.nix {
              inherit lib pkgs;
              module = ./modules/systemd-shape-audit;
            };
            module-list = pkgs.runCommand "module-list" {} ''
              # Forces evaluation of every discovered module path and records the
              # public surface; a change here shows up as a check-input diff.
              printf '%s\n' ${
                lib.concatStringsSep " " (lib.mapAttrsToList (name: path: "${name}=${path}") nixosModules)
              } > $out
              cat $out
            '';
            options-json = import ./tests/options-json.nix {
              inherit lib pkgs;
              modules = nixosModules;
            };
            # Count-drift guard: every tests/*.nix wired into this flake,
            # every flake reference resolving to a real file (mechanizes
            # the 7→8→10 hand-count churn class).
            tests-wiring = import ./tests/wiring.nix {
              inherit lib pkgs;
            };
            # README option-table drift guard: each module's ## Options
            # table names exactly the declared option surface.
            options-readme-drift = import ./tests/readme-drift.nix {
              inherit lib pkgs;
              modules = nixosModules;
            };
          }
          // lib.optionalAttrs (system == "x86_64-linux") {
            wifi-failover-vm = pkgs.testers.runNixOSTest (import ./tests/wifi-failover.nix {inherit pkgs;});
            hot-tier-journal-vm = pkgs.testers.runNixOSTest (import ./tests/hot-tier-journal.nix {inherit pkgs;});
            hot-tier-caddy-vm = pkgs.testers.runNixOSTest (import ./tests/hot-tier-caddy.nix {inherit pkgs;});
            hot-dir-migrate-vm = pkgs.testers.runNixOSTest (import ./tests/hot-dir-migrate.nix {inherit pkgs;});
            boot-mirror-vm = pkgs.testers.runNixOSTest (import ./tests/boot-mirror-vm.nix {inherit pkgs;});
          }
      );

      formatter = forAllSystems (
        system: let
          pkgs = nixpkgs.legacyPackages.${system};
          treefmtEval = treefmt-nix.lib.evalModule pkgs ./treefmt.nix;
        in
          treefmtEval.config.build.wrapper
      );

      # Harness/dev shell: the tools tests/negative + tests/parity need
      # (bash, git+rsync for the copy, nix for the builds, jq for parity
      # verdict rendering). `nix develop` → every gate runnable bare.
      devShells = forAllSystems (system: {
        default = nixpkgs.legacyPackages.${system}.mkShellNoCC {
          packages = with nixpkgs.legacyPackages.${system}; [
            bash
            git
            rsync
            jq
            nix
          ];
          shellHook = ''
            echo "nixos-modules devshell — gates:" >&2
            echo "  nix flake check            # everything (VMs on x86_64)" >&2
            echo "  bash tests/negative/run.sh # mutation harness (CASES=, KEEP=, PARALLEL=0)" >&2
            echo "  bash tests/parity/run.sh   # SystemNix parity diff (SYSTEMNIX_PATH=)" >&2
            echo "  nix run github:Artmann-Technologies/docs-gates -- run ." >&2
          '';
        };
      });

      # Manual (sibling-checkout-dependent) tools as flake apps: the negative
      # mutation harness and the SystemNix parity diff. Both copy/eval the
      # git-tracked tree, so they must run against a working checkout —
      # invoke from the repo root (CASES=/KEEP= and SYSTEMNIX_PATH/KEEP_JSON=
      # pass through the env).
      apps = forAllSystems (system: {
        negative-tests = {
          type = "app";
          program = toString (nixpkgs.legacyPackages.${system}.writeShellScript "negative-tests" ''
            if [ ! -f "$PWD/tests/negative/run.sh" ]; then
              echo "negative-tests: run from the repo root (or directly: bash tests/negative/run.sh)" >&2
              exit 1
            fi
            exec bash "$PWD/tests/negative/run.sh" "$@"
          '');
        };
        parity-diff = {
          type = "app";
          program = toString (nixpkgs.legacyPackages.${system}.writeShellScript "parity-diff" ''
            if [ ! -f "$PWD/tests/parity/run.sh" ]; then
              echo "parity-diff: run from the repo root (or directly: bash tests/parity/run.sh)" >&2
              exit 1
            fi
            exec bash "$PWD/tests/parity/run.sh" "$@"
          '');
        };
      });
    };
}
