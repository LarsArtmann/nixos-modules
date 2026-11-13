# Eval-contract check for the gatus-coverage-audit module: both audit
# directions must FLAG their offenders (class A: an in-use registered port
# no endpoint watches, naming port + owners; class B: a loopback gatus URL
# on an unregistered port), the external-upstream exemption and allowPorts
# must be real escapes, a gatus-less host and an un-enabled import must
# stay silent. The base eval carries nixpkgs' REAL gatus module — the audit
# reads the consumer's services.gatus exactly as deployed. The negative
# legs in tests/negative/ neuter both class detectors — each must break the
# build.
{
  lib,
  pkgs,
  module,
}: let
  # The base eval already carries nixpkgs' real gatus module
  # (services.monitoring.gatus): the fixture sets its actual options —
  # no test-only stand-in shape needed.
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
      (a: !a.assertion && lib.hasPrefix "gatus-coverage-audit:" a.message)
      (lib.nixosSystem {
        system = "x86_64-linux";
        inherit modules;
      })
      .config
      .assertions);

  audit = {
    enable = true;
    registry = {
      app = 8099;
    };
  };
  usesAppPort = {
    systemd.services.app.serviceConfig.ExecStart = "/bin/app --listen 127.0.0.1:8099";
  };
  watchesApp = {
    services.gatus = {
      enable = true;
      settings.endpoints = [{url = "http://127.0.0.1:8099/health";}];
    };
  };
  watchesExternalOnly = {
    services.gatus = {
      enable = true;
      settings.endpoints = [{url = "tcp://dot.mullvad.net:853";}];
    };
  };

  cleanFailures = auditFailures (baseModules ++ [{services.gatus-coverage-audit = audit;} usesAppPort watchesApp]);
  # Class A: app serves 8099, gatus only watches an external upstream.
  uncoveredFailures = auditFailures (baseModules ++ [{services.gatus-coverage-audit = audit;} usesAppPort watchesExternalOnly]);
  escapeFailures = auditFailures (
    baseModules
    ++ [
      {
        services.gatus-coverage-audit =
          audit
          // {
            allowPorts = [8099];
          };
      }
      usesAppPort
      watchesExternalOnly
    ]
  );
  # Class B: a loopback URL on an unregistered port (no unit uses it).
  unregisteredUrlFailures = auditFailures (
    baseModules
    ++ [
      {
        services.gatus-coverage-audit = audit;
      }
      {
        services.gatus = {
          enable = true;
          settings.endpoints = [{url = "http://127.0.0.1:9999/ping";}];
        };
      }
    ]
  );
  # The external-upstream exemption is structural (loopback-only rule):
  # watching ONLY externals with no in-use ports is clean.
  externalOnlyFailures = auditFailures (baseModules ++ [{services.gatus-coverage-audit = audit;} watchesExternalOnly]);
  # gatus disabled on the host: the audit stays silent (coverage is only
  # enforceable where a monitor exists).
  gatusDisabledFailures = auditFailures (
    baseModules
    ++ [
      {
        services.gatus-coverage-audit = audit;
      }
      usesAppPort
    ]
  );
  inertFailures = auditFailures (baseModules ++ [usesAppPort watchesExternalOnly]);

  exactlyOneWith = failures: fragment:
    builtins.length failures == 1 && lib.hasInfix fragment (builtins.head failures);

  contract =
    lib.throwIfNot (cleanFailures == [])
    "gatus-coverage-audit contract: false positives on a covered host: ${lib.concatStringsSep " | " cleanFailures}"
    (lib.throwIfNot (exactlyOneWith uncoveredFailures "8099 (referenced by: app)")
      "gatus-coverage-audit contract: class A must name the uncovered port and its owner (got: ${lib.concatStringsSep " | " uncoveredFailures})"
      (lib.throwIfNot (escapeFailures == [])
        "gatus-coverage-audit contract: allowPorts must silence a justified exemption: ${lib.concatStringsSep " | " escapeFailures}"
        (lib.throwIfNot (exactlyOneWith unregisteredUrlFailures "unregistered port")
          "gatus-coverage-audit contract: class B must flag the loopback URL's unregistered port (got: ${lib.concatStringsSep " | " unregisteredUrlFailures})"
          (lib.throwIfNot (externalOnlyFailures == [])
            "gatus-coverage-audit contract: external upstream checks must be exempt: ${lib.concatStringsSep " | " externalOnlyFailures}"
            (lib.throwIfNot (gatusDisabledFailures == [])
              "gatus-coverage-audit contract: coverage must not be enforced on a gatus-less host: ${lib.concatStringsSep " | " gatusDisabledFailures}"
              (lib.throwIfNot (inertFailures == [])
                "gatus-coverage-audit contract: an un-enabled import must stay silent: ${lib.concatStringsSep " | " inertFailures}"
                (builtins.toJSON {
                  classA = true;
                  classB = true;
                  allowPorts = true;
                  externalExempt = true;
                  gatusGate = true;
                  inert = true;
                })))))));
in
  pkgs.runCommand "gatus-coverage-audit-contract" {
    inherit contract;
    passAsFile = ["contract"];
  } ''
    cp "$contractPath" $out
    echo "gatus-coverage-audit-contract: both classes flag, escapes honored, inert-until-enable" >&2
  ''
