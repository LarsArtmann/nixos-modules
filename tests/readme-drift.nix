# options-readme-drift: every module's README `## Options` table must name
# exactly the option surface the module declares (rendered from the same
# eval machinery as checks.options-json). Drift bites BOTH directions: a
# new option nobody documented, and a README row for an option that no
# longer exists. Types/defaults are prose — the NAME SET is the contract
# (the drift class that bites is add/remove/rename, not wording).
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
      isOwn = o: lib.hasPrefix prefix o.name && !(lib.hasInfix "._module." o.name);
      docList = lib.optionAttrSetToDocList eval.options;
      relative =
        map
        (o: lib.removePrefix prefix o.name)
        (lib.filter isOwn docList);

      readme = builtins.readFile (path + "/README.md");
      # The `## Options` section runs to the next `## ` heading (split
      # yields the segments BETWEEN headings).
      section =
        lib.findFirst
        (p: lib.hasPrefix "Options" (builtins.substring 0 7 p))
        null
        (lib.filter builtins.isString (builtins.split "\n## " readme));
      # First-column backticked names of the table rows (| `name` | ...).
      documented =
        lib.concatMap
        (
          line:
            if lib.hasPrefix "| `" line
            then [
              (builtins.head (
                lib.filter (x: x != "")
                (lib.splitString "`" (lib.removePrefix "| `" line))
              ))
            ]
            else []
        )
        (lib.splitString "\n" section);
    in {
      inherit name;
      missing = lib.subtractLists documented relative;
      stale = lib.subtractLists relative (lib.unique documented);
      noTable = !(lib.hasPrefix "Options" (builtins.substring 0 7 section));
    })
    modules;

  broken =
    lib.filter
    (m: m.noTable || m.missing != [] || m.stale != [])
    perModule;

  report =
    if broken == []
    then null
    else
      lib.concatStringsSep "\n" (
        lib.mapAttrsToList
        (_: m:
          lib.optionalString m.noTable "${m.name}: README has no ## Options section\n"
          + lib.optionalString (m.missing != []) "${m.name}: undocumented option(s): ${lib.concatStringsSep ", " m.missing}\n"
          + lib.optionalString (m.stale != []) "${m.name}: README documents option(s) that do not exist: ${lib.concatStringsSep ", " m.stale}")
        (builtins.listToAttrs (map (m: lib.nameValuePair m.name m) broken))
      );
in
  if broken != []
  then throw "options-readme-drift:\n${report}"
  else
    pkgs.runCommand "options-readme-drift" {} ''
      echo "options-readme-drift: README option tables match the declared surface for ${toString (builtins.length perModule)} modules" > $out
    ''
