# Collection lib — the systemd hardening spine.
# Populated in R2 from SystemNix lib/ (harden, serviceDefaults*, onFailure*,
# unit generators). Everything here must depend on nixpkgs lib ONLY: if a
# helper needs `config` or fleet state it belongs in a module option, not here.
{ lib }:
{ }
