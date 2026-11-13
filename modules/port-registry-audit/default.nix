# Eval-time audit: every TCP port literal in systemd unit text must be a
# value from the consumer's port registry — the "never hardcode
# localhost:PORT" Critical Rule, finally ENFORCED instead of remembered.
#
# Why this exists: port collisions and forgotten ports are the "missing
# config" class. Nothing checks that ports actually USED by services are IN
# the registry: a new service wiring `127.0.0.1:8150` inline collides with
# nothing at eval time and is only discovered at runtime.
#
# Fleet-agnostic shape (the split contract, lib/README): the registry lives
# CONSUMER-side — this module takes it as an option (SystemNix feeds its
# lib/ports.nix; the collection never hardcodes fleet ports). The registry
# ALSO gets the collision half here: two names claiming the same port fail
# eval (SystemNix's lib threw at construction; asserting here keeps the
# delegation layer fork-free).
#
# What is scanned per service: Exec{Start,StartPre,StartPost,Stop,StopPost,
# Reload,Condition} and Environment (list or attrset form), stringified.
# Extraction forms (mirrors how port literals are actually written):
#   host-form   127.0.0.1:8099 / localhost 25 / 0.0.0.0:53
#   colon-form  <non-alnum>:<digits>   (listen=:8100, http://host:8080/x)
#   flag-form   --port 8100 / --port=8100
# Deliberately NOT scanned: EnvironmentFile contents, Caddy/gatus/compose
# configs (own modules), anything inside script bodies (opaque).
#
# Justified exceptions (upstream-owned units etc.):
#   services.port-registry-audit.allowPorts = [ 8150 ];  # + comment why
#
# Non-goals: UDP ranges written space-separated, ports in nested config
# files. This is a regression guard over the dominant literal forms, not a
# total net — a port that slips past every form is invisible to this audit.
# The one known FALSE-POSITIVE class: word:NNN tokens whose NNN collides
# with no registered port ("DELAY:300") fire; host:port and word:NNN are
# lexically identical, so allowPorts is the sanctioned escape.
#
# Provenance: moved from SystemNix modules/nixos/services/port-registry-audit.nix
# (2026-11-13, SUPERB T14); that file is now a delegation layer importing
# this module and feeding the registry option.
{
  config,
  lib,
  ...
}: let
  cfg = config.services.port-registry-audit;
  inherit
    (import ../../lib/default.nix lib)
    unitExecText
    extractPortLiterals
    ;

  # Collision half: registry name -> port; two names on one port is the
  # exact accident the registry exists to prevent.
  byPort =
    lib.foldl'
    (
      acc: name: let
        port = toString cfg.registry.${name};
      in
        acc // {${port} = (acc.${port} or []) ++ [name];}
    )
    {}
    (lib.attrNames cfg.registry);
  duplicatePorts = lib.filterAttrs (_: names: builtins.length names > 1) byPort;
  duplicateReport = lib.concatStringsSep "\n" (
    lib.mapAttrsToList
    (port: names: "  ${port}: ${lib.concatStringsSep ", " names}")
    duplicatePorts
  );

  allowedPorts = builtins.attrValues cfg.registry ++ cfg.allowPorts;

  # tryEval: a unit whose Exec text cannot be coerced (exotic
  # self-referential config) must never break eval — it is skipped.
  offenders =
    lib.filterAttrs (
      _name: svc: let
        text = builtins.tryEval (unitExecText svc);
        unregistered =
          if !text.success
          then []
          else lib.subtractLists allowedPorts (extractPortLiterals text.value);
      in
        unregistered != []
    )
    config.systemd.services;

  offenderReport = lib.concatStringsSep "\n" (
    lib.mapAttrsToList (
      name: svc: let
        text = builtins.tryEval (unitExecText svc);
        unregistered = lib.subtractLists allowedPorts (extractPortLiterals text.value);
      in "  ${name}: ${lib.concatStringsSep ", " (map toString unregistered)}"
    )
    offenders
  );
in {
  options.services.port-registry-audit = {
    enable = lib.mkEnableOption "the port-registry audit (registry membership + collision enforcement over unit Exec text)";

    registry = lib.mkOption {
      type = lib.types.attrsOf lib.types.port;
      default = {};
      example = {
        myapp = 8099;
      };
      description = ''
        The consumer's port registry: service name -> TCP port. Every port
        literal found in any systemd unit's Exec*/Environment text must be a
        value here (or in allowPorts), and no two names may claim the same
        port — both fail eval with the offender named.
      '';
    };

    allowPorts = lib.mkOption {
      type = lib.types.listOf lib.types.port;
      default = [];
      description = ''
        Port numbers exempt from the registry requirement (upstream-owned
        units, protocol-fixed ports that do not belong in the registry, and
        the word:NNN false-positive class). Every entry MUST carry a
        justification comment where it is set.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = duplicatePorts == {};
        message = ''
          port-registry-audit: registry port collision(s):
          ${duplicateReport}
          A port serves exactly one service — the registry exists so this
          class dies at eval time, not as a runtime EADDRINUSE.
        '';
      }
      {
        assertion = offenders == {};
        message = ''
          port-registry-audit: port literal(s) not registered:
          ${offenderReport}
          Every port a service binds or dials must live in the registry so
          collisions are caught at eval time and the port map stays complete.
          Fix: add the port to the registry and reference it, or — for a
          justified exemption — extend:
            services.port-registry-audit.allowPorts = [ <port> ];
          with a comment explaining why it must stay out of the registry.
        '';
      }
    ];
  };
}
