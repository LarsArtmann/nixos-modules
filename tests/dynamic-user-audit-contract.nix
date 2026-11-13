# Eval-contract check for the dynamic-user-audit module: the guard must FLAG
# a sops secret AND a sops template owned by a DynamicUser service name,
# must stay silent for root-owned secrets and non-dynamic owners, and must
# not explode on a host with no sops options at all (the tryEval path). The
# fixture declares sops-shaped options locally so the check is self-contained
# — the audit only needs config.sops.{secrets,templates} to EXIST. The
# negative legs in tests/negative/ neuter the module's detection and strip
# the offender from this fixture — both must break the build.
{
  lib,
  pkgs,
  module,
}: let
  sopsShape = {
    options = {
      sops.secrets = lib.mkOption {
        type = lib.types.attrsOf (lib.types.submodule {
          options.owner = lib.mkOption {
            type = lib.types.str;
            default = "root";
          };
        });
        default = {};
      };
      sops.templates = lib.mkOption {
        type = lib.types.attrsOf (lib.types.submodule {
          options.owner = lib.mkOption {
            type = lib.types.str;
            default = "root";
          };
        });
        default = {};
      };
    };
  };
  baseModules = [
    module
    sopsShape
    {
      fileSystems."/" = {
        device = "/dev/vda1";
        fsType = "ext4";
      };
      boot.loader.grub.devices = ["nodev"];
      systemd.services.dynapp.serviceConfig.DynamicUser = true;
    }
  ];
  auditFailures = modules:
    map (a: a.message)
    (lib.filter (a: !a.assertion)
      (lib.nixosSystem {
        system = "x86_64-linux";
        inherit modules;
      })
      .config
      .assertions);
  offenderFailures = auditFailures (
    baseModules
    ++ [
      {
        sops.secrets.dynapp-env.owner = "dynapp";
      }
    ]
  );
  templateFailures = auditFailures (
    baseModules
    ++ [
      {
        sops.templates.dynapp-tpl.owner = "dynapp";
      }
    ]
  );
  rootOwnedFailures = auditFailures (
    baseModules
    ++ [
      {
        sops.secrets.dynapp-env.owner = "root";
      }
    ]
  );
  foreignOwnerFailures = auditFailures (
    baseModules
    ++ [
      {
        sops.secrets.human-env.owner = "somehuman";
      }
    ]
  );
  # No sops options at all: the tryEval path must keep the audit silent.
  bareFailures = auditFailures [
    module
    {
      fileSystems."/" = {
        device = "/dev/vda1";
        fsType = "ext4";
      };
      boot.loader.grub.devices = ["nodev"];
      systemd.services.dynapp.serviceConfig.DynamicUser = true;
    }
  ];
  contract =
    lib.throwIfNot (builtins.length offenderFailures == 1)
    "dynamic-user-audit contract: the guard must flag a secret owned by a DynamicUser name (got ${toString (builtins.length offenderFailures)}) — sops decrypt fails and blocks ALL secrets atomically"
    (lib.throwIfNot (builtins.length templateFailures == 1)
      "dynamic-user-audit contract: the template half must flag too (got ${toString (builtins.length templateFailures)})"
      (lib.throwIfNot (rootOwnedFailures == [])
        "dynamic-user-audit contract: root-owned secrets must pass: ${lib.concatStringsSep " | " rootOwnedFailures}"
        (lib.throwIfNot (foreignOwnerFailures == [])
          "dynamic-user-audit contract: non-dynamic owners are none of this audit's business: ${lib.concatStringsSep " | " foreignOwnerFailures}"
          (lib.throwIfNot (bareFailures == [])
            "dynamic-user-audit contract: hosts without sops options must stay silent: ${lib.concatStringsSep " | " bareFailures}"
            (builtins.toJSON {
              secretFlagged = builtins.length offenderFailures;
              templateFlagged = builtins.length templateFailures;
              rootPasses = true;
              foreignPasses = true;
              barePasses = true;
            })))));
in
  pkgs.runCommand "dynamic-user-audit-contract" {
    inherit contract;
    passAsFile = ["contract"];
  } ''
    cp "$contractPath" $out
    echo "dynamic-user-audit-contract: secret + template flagged, root/foreign/bare silent" >&2
  ''
