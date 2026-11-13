# Eval-time assertion: sops secrets for DynamicUser services MUST be root-owned.
#
# DynamicUser creates the service user at startup — it does NOT exist when
# sops-nix runs its activation script. A sops secret with owner="<dynuser>"
# fails with "failed to lookup user" which blocks ALL secrets atomically.
#
# This module auto-discovers every DynamicUser service at eval time and
# cross-references sops secret ownership. It replaces the hardcoded bash-grep
# check that used to live in SystemNix's pre-commit hook (which only knew
# about atticd + gatus).
#
# Bug class history: Gatus (DynamicUser couldn't own LoadCredential file),
# crush-daily (sops owner mismatch blocked all secrets), Attic (same pattern).
#
# The sops options are read through builtins.tryEval: on hosts without
# sops-nix imported, config.sops.secrets does not exist and the audit stays
# silent — importable everywhere, bites exactly where secrets exist.
#
# Provenance: moved verbatim from SystemNix modules/nixos/services/dynamic-user-audit.nix
# (2026-11-13, plan wave A1b); that file is now a delegation layer importing
# this module. No options — the invariant is absolute.
{
  lib,
  config,
  options,
  ...
}: let
  # Source of truth: services where DynamicUser=true at eval time.
  # Catches nixpkgs upstream modules (atticd, gatus, searx) AND any
  # future consumer service that enables DynamicUser.
  dynamicUserServices =
    lib.filterAttrs (
      _name: svc: svc.serviceConfig.DynamicUser or false
    )
    config.systemd.services;

  dynamicUserNames = builtins.attrNames dynamicUserServices;

  # Find sops secrets owned by a non-root user matching a DynamicUser name.
  # Guarded by `options ?` — NOT builtins.tryEval: under Nix 2.34 the
  # missing-option error (attribute 'sops' missing) escapes tryEval through
  # the seq-checked config fixpoint (proven by this module's own contract
  # bare-host leg, 2026-11-13). On hosts without sops-nix the audit stays
  # silent; it bites exactly where secrets exist.
  sopsSecrets =
    if options ? sops.secrets
    then config.sops.secrets
    else {};

  violatingSecrets =
    lib.filterAttrs (
      _name: secret: let
        owner = secret.owner or "root";
      in
        owner != "root" && builtins.elem owner dynamicUserNames
    )
    sopsSecrets;

  # Also check sops templates — same atomic-block failure mode
  sopsTemplates =
    if options ? sops.templates
    then config.sops.templates
    else {};

  violatingTemplates =
    lib.filterAttrs (
      _name: template: let
        owner = template.owner or "root";
      in
        owner != "root" && builtins.elem owner dynamicUserNames
    )
    sopsTemplates;
in {
  config.assertions =
    (lib.mapAttrsToList (
        name: secret: let
          owner = secret.owner or "root";
        in {
          assertion = false;
          message = ''
            sops secret "${name}" has owner="${owner}" but "${owner}" is a
            DynamicUser service — the user does not exist at sops-decrypt time
            and cannot own files. Set owner="root" (systemd reads EnvironmentFile
            as PID 1 and injects vars into the process). This bug class hit
            Gatus, crush-daily, and Attic.
          '';
        }
      )
      violatingSecrets)
    ++ (lib.mapAttrsToList (
        name: template: let
          owner = template.owner or "root";
        in {
          assertion = false;
          message = ''
            sops template "${name}" has owner="${owner}" but "${owner}" is a
            DynamicUser service — the user does not exist at sops-decrypt time.
            Set owner="root".
          '';
        }
      )
      violatingTemplates);
}
