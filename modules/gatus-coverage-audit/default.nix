# Eval-time audit: MONITORING COVERAGE — the "every service MUST be
# monitored" doctrine, finally ENFORCED instead of remembered.
#
# Two directions over the RESOLVED config (no source greps), sharing the
# port-registry-audit scan surface (unitExecText + extractPortLiterals, the
# same consumer-fed registry):
#
#   A. Coverage: every port that is (a) extracted from live unit
#      Exec*/Environment text AND (b) registered must appear as :<port> in
#      at least one gatus endpoint URL — else the service serves a port
#      nothing watches (silent failures are unacceptable). Only enforced
#      when gatus itself is enabled on the host.
#
#   B. Reverse: every gatus URL that targets LOOPBACK must carry a port in
#      the registry (external upstream checks such as
#      tcp://dot.mullvad.net:853 are exempt — 853 is Mullvad's port, not
#      ours). Catches registry drift in the monitor itself.
#
# Justified exceptions (with a comment where set): allowPorts. Sanctioned
# exception classes, carried over from the fleet consumer:
#   - prohibited-to-probe sockets (each probe holds a connection slot the
#     real clients need — FastFlowLM :52625 churned slots 2026-08-18);
#     liveness goes via system-health metrics instead
#   - vHost-monitored services: the check hits https://<sub>.<domain>/ through
#     the reverse proxy, so the backend port never appears in a URL
#
# Fleet-agnostic shape (the split contract, lib/README): the registry and
# the gatus config both live CONSUMER-side — SystemNix feeds its
# lib/ports.nix and runs real gatus; this module reads whatever
# services.gatus the consumer declares and stays silent without it.
#
# Provenance: moved from SystemNix modules/nixos/services/gatus-coverage-audit.nix
# (2026-11-13, SUPERB T15); that file is now a delegation layer importing
# this module and feeding the registry option.
{
  config,
  lib,
  ...
}: let
  cfg = config.services.gatus-coverage-audit;
  inherit
    (import ../../lib/default.nix lib)
    unitExecText
    extractPortLiterals
    ;

  registeredPorts = builtins.attrValues cfg.registry;
  allowed = registeredPorts ++ cfg.allowPorts;

  # (a) in-use ports with owning units, restricted to registered ones
  # (registry membership is enforced by port-registry-audit; this keeps
  # word:NNN scan residue out of the coverage signal).
  gatusEnabled = config.services.gatus.enable or false;
  inUseWithOwner =
    lib.optionals gatusEnabled
    (
      lib.concatLists (
        lib.mapAttrsToList (
          name: svc: let
            t = builtins.tryEval (unitExecText svc);
          in
            if !t.success
            then []
            else
              map (p: {
                port = p;
                owner = name;
              }) (builtins.filter (p: builtins.elem p registeredPorts) (extractPortLiterals t.value))
        )
        config.systemd.services
      )
    );
  inUsePorts = lib.unique (map (x: x.port) inUseWithOwner);
  owners = p:
    lib.concatStringsSep ", " (
      lib.unique (map (x: x.owner) (lib.filter (x: x.port == p) inUseWithOwner))
    );

  gatusEndpoints = config.services.gatus.settings.endpoints or [];
  gatusUrls = map (ep: toString (ep.url or "")) gatusEndpoints;

  urlPorts = url: let
    parts = builtins.split "[:]([0-9]{2,5})([^0-9]|$)" url;
    groups =
      builtins.filter (g: builtins.isString g && builtins.match "[0-9]+" g != null)
      (lib.flatten (map (x:
        if builtins.isList x
        then x
        else [])
      parts));
  in
    map lib.toInt groups;
  coveredPorts = lib.unique (lib.concatMap urlPorts gatusUrls);

  # --- class A: in-use but unmonitored ---
  uncovered = lib.subtractLists (coveredPorts ++ cfg.allowPorts) inUsePorts;
  uncoveredReport = map (p: "  ${toString p} (referenced by: ${owners p})") uncovered;

  # --- class B: loopback gatus URLs must use registered ports ---
  # IPv6 [::1] literals are not matched — POSIX ERE rejects the \[ escape,
  # and no known consumer uses IPv6 loopback in a gatus URL.
  loopbackUrlPorts =
    lib.concatLists
    (
      map (
        url: let
          isLoopback = builtins.match "(http|https|tcp)://(127\\.0\\.0\\.1|localhost).*" url != null;
        in
          lib.optionals isLoopback (urlPorts url)
      )
      gatusUrls
    );
  unregisteredLoopback = lib.unique (lib.subtractLists allowed loopbackUrlPorts);
in {
  options.services.gatus-coverage-audit = {
    enable = lib.mkEnableOption "the gatus monitoring-coverage audit (uncovered listeners + monitor-side registry drift)";

    registry = lib.mkOption {
      type = lib.types.attrsOf lib.types.port;
      default = {};
      example = {
        myapp = 8099;
      };
      description = ''
        The consumer's port registry (same map fed to port-registry-audit):
        service name -> TCP port. In-use registered ports must appear in a
        gatus endpoint URL, and loopback gatus URLs must use registered
        ports.
      '';
    };

    allowPorts = lib.mkOption {
      type = lib.types.listOf lib.types.port;
      default = [];
      description = ''
        Ports exempt from the coverage requirement (prohibited-to-probe
        sockets, vHost-monitored backends). Every entry MUST carry a
        justification comment where it is set.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = lib.optionals gatusEnabled [
      {
        assertion = uncovered == [];
        message = ''
          gatus-coverage-audit: registered port(s) referenced by live units but never probed by any gatus endpoint:
          ${lib.concatStringsSep "\n" uncoveredReport}
          "Every new service MUST be monitored — silent failures are unacceptable."
          Fix: add a gatus endpoint for the port, or — for a justified
          exemption (prohibited-to-probe socket, vHost-monitored backend) —
          extend:
            services.gatus-coverage-audit.allowPorts = [ <port> ];
          with a comment explaining why a direct probe is wrong.
        '';
      }
      {
        assertion = unregisteredLoopback == [];
        message = ''
          gatus-coverage-audit: loopback gatus URL(s) use unregistered port(s):
          ${lib.concatStringsSep ", " (map toString unregisteredLoopback)}
          Ports OUR services serve must live in the registry so collisions
          are caught at eval time. External upstream checks (dot.mullvad.net,
          1.1.1.1, ...) are exempt by design.
        '';
      }
    ];
  };
}
