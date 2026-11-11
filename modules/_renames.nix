# Migration ledger — rename/removal tombstones for collection options.
# Policy (NuschtOS-style): every breaking option change lands here as a
# mkRenamedOptionModule / mkChangedOptionModule / mkRemovedOptionModule entry
# WITH a reason string; aliases are effectively permanent once shipped because
# consumers pin by rev. Consumers opt in by adding this file to imports while
# migrating; keep entries forever (nixpkgs rename.nix still carries 2023
# removals). Caveats: renames do not work across types.raw; the target option
# must already be declared.
{ ... }:
{
  imports = [ ];
}
