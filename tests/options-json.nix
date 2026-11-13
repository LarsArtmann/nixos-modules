# options.json render + provenance check: for every discovered module, render
# its own options (services.<name>.*) to JSON and mechanically prove the
# path-provenance claim from flake.nix — every option's declarations resolve
# inside modules/<name>/, never an import-application artifact.
#
# Layering note (why there is no import-apply negative leg): the collection's
# modules are FUNCTIONS ({config, lib, ...}: ...), so an import-applied
# `nixosModules.<name> = import ./modules/<name>/default.nix;` cannot even
# evaluate (a bare function is not a module) — flake.nix's `modulesArePaths`
# assert and eval semantics already make that shape unreachable. This check
# pins the remaining claim the assert does NOT cover: that the option
# declarations of the PATH-exposed modules carry their real module-file
# provenance (what options.json browsers and search tools display).
{
  lib,
  pkgs,
  modules,
}: let
  perModule =
    lib.mapAttrsToList (name: path: let
      eval = lib.nixosSystem {
        system = "x86_64-linux";
        modules = [path];
      };
      prefix = "services.${name}.";
      # _module.* internals (args/check/freeformType/specialArgs) are declared
      # by nixpkgs's lib/modules.nix inside every submodule — not module-owned
      # options; exclude them from both the count and the provenance proof.
      isOwn = o: lib.hasPrefix prefix o.name && !(lib.hasInfix "._module." o.name);
      docList = lib.optionAttrSetToDocList eval.options;
      own = lib.filter isOwn docList;
      outsideTerritory =
        lib.filter (
          o:
            !(lib.any (
                d: lib.hasSuffix "/modules/${name}" (toString d)
              )
              o.declarations)
        )
        own;
      # Render declarations relative to the module directory: the JSON stays
      # context-free (a toJSON'd store path loses its string context and the
      # embedded absolute path can dangle after GC) and options browsers read
      # it better. Foreign declarations keep their absolute form — the
      # provenance check below throws on them before the JSON ships.
      relDecl = d: lib.removePrefix "${toString path}/" (toString d);
      rendered =
        builtins.toJSON
        (map (o: o // {declarations = map relDecl o.declarations;}) own);
    in {
      inherit name;
      ownCount = builtins.length own;
      outsideCount = builtins.length outsideTerritory;
      json = pkgs.writeText "${name}-options.json" rendered;
    })
    modules;

  # Provenance violations only. ownCount == 0 is NOT broken: assert-only
  # modules (the A1a audit gates) legitimately declare zero options, and a
  # module with no options has no provenance to lose — an import-applied or
  # re-exported option ALWAYS shows up as outside-territory instead.
  broken =
    lib.filter (m: m.outsideCount > 0) perModule;
  totalOptions = lib.foldl' (acc: m: acc + m.ownCount) 0 perModule;
  summary =
    if broken != []
    then
      throw ''
        options-json: provenance broken for: ${
          lib.concatStringsSep ", " (map (m: "${m.name} (own=${toString m.ownCount}, outside-territory=${toString m.outsideCount})") broken)
        }
        Every services.<name>.* option must be declared inside modules/<name>/ —
        import-applied or re-exported options lose their "declared in" provenance
        in every options browser.
      ''
    else "ok: ${toString (builtins.length perModule)} modules, ${toString totalOptions} options, all declarations inside their module paths";
  jsons = lib.concatStringsSep " " (map (m: "${m.json}") perModule);
in
  pkgs.runCommand "options-json" {
    summaryText = summary;
    passAsFile = ["summaryText"];
    inherit jsons;
  } ''
    mkdir -p $out/options
    cp "$summaryTextPath" $out/summary.txt
    for j in $jsons; do cp "$j" "$out/options/$(basename "$j")"; done
    echo "options-json: $summaryText" >&2
  ''
