# Eval-contract check for the port-registry-audit module: the registry
# membership + collision halves must FLAG their offenders exactly (naming
# unit + port / both colliding names), allowPorts must be a real escape,
# the word:NNN false-positive class must stay DETECTED (its sanctioned
# silence is allowPorts, not a scan gap), and an un-enabled import must
# stay silent (inert-until-enable). The negative legs in tests/negative/
# neuter the module's detection and strip the offender from this fixture —
# both must break the build.
{
  lib,
  pkgs,
  module,
}: let
  baseModules = [
    module
    {
      fileSystems."/" = {
        device = "/dev/vda1";
        fsType = "ext4";
      };
      boot.loader.grub.devices = ["nodev"];
    }
  ];
  auditFailures = modules:
    map (a: a.message)
    (lib.filter
      (a: !a.assertion && lib.hasPrefix "port-registry-audit:" a.message)
      (lib.nixosSystem {
        system = "x86_64-linux";
        inherit modules;
      })
      .config
      .assertions);

  enabled = {
    services.port-registry-audit = {
      enable = true;
      registry = {
        app = 8099;
        api = 8443;
      };
    };
  };
  # All three extraction forms, all registered: the clean host.
  usesRegisteredPorts = {
    systemd.services.app.serviceConfig.ExecStart = "/bin/app --listen 127.0.0.1:8099 --api http://127.0.0.1:8443";
  };
  # flag-form + host-form literals on one unit, both unregistered.
  offender = {
    systemd.services.port-offender.serviceConfig.ExecStart = "/bin/rogue --port 8150 --also 0.0.0.0:8151";
  };

  cleanFailures = auditFailures (baseModules ++ [enabled usesRegisteredPorts]);
  offenderFailures = auditFailures (baseModules ++ [enabled offender]);
  escapeFailures = auditFailures (
    baseModules
    ++ [
      enabled
      offender
      {services.port-registry-audit.allowPorts = [8150 8151];}
    ]
  );
  duplicateFailures = auditFailures (
    baseModules
    ++ [
      {
        services.port-registry-audit = {
          enable = true;
          registry = {
            first = 8150;
            second = 8150;
          };
        };
      }
    ]
  );
  inertFailures = auditFailures (baseModules ++ [offender]);
  # The KNOWN false-positive class, pinned as DETECTED: "DELAY:300" is
  # lexically host:port. The escape is allowPorts — never a scan gap.
  wordFailures = auditFailures (
    baseModules
    ++ [
      enabled
      {
        systemd.services.word-tokens.serviceConfig.Environment = "DELAY:300";
      }
    ]
  );

  oneFailureWith = fragment:
    lib.throwIfNot (
      builtins.length offenderFailures
      == 1
      && lib.hasInfix fragment (builtins.head offenderFailures)
    )
    "port-registry-audit contract: the membership half must flag the offender naming it (wanted '${fragment}' in: ${lib.concatStringsSep " | " offenderFailures})";

  contract =
    lib.throwIfNot (cleanFailures == [])
    "port-registry-audit contract: false positives on a clean host: ${lib.concatStringsSep " | " cleanFailures}"
    (oneFailureWith "port-offender: 8150, 8151"
      (lib.throwIfNot (escapeFailures == [])
        "port-registry-audit contract: allowPorts must silence a justified exemption: ${lib.concatStringsSep " | " escapeFailures}"
        (lib.throwIfNot (
            builtins.length duplicateFailures
            == 1
            && lib.hasInfix "first" (builtins.head duplicateFailures)
            && lib.hasInfix "second" (builtins.head duplicateFailures)
          )
          "port-registry-audit contract: the collision half must name both claimants (got: ${lib.concatStringsSep " | " duplicateFailures})"
          (lib.throwIfNot (inertFailures == [])
            "port-registry-audit contract: an un-enabled import must stay silent: ${lib.concatStringsSep " | " inertFailures}"
            (lib.throwIfNot (
                builtins.length wordFailures
                == 1
                && lib.hasInfix "300" (builtins.head wordFailures)
              )
              "port-registry-audit contract: the word:NNN class must stay detected (got: ${lib.concatStringsSep " | " wordFailures})"
              (builtins.toJSON {
                membership = true;
                collision = true;
                allowPorts = true;
                inert = true;
                wordClass = true;
              }))))));
in
  pkgs.runCommand "port-registry-audit-contract" {
    inherit contract;
    passAsFile = ["contract"];
  } ''
    cp "$contractPath" $out
    echo "port-registry-audit-contract: membership+collision flag, escapes honored, inert-until-enable" >&2
  ''
