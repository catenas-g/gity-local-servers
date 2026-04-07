{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.custom.fireactions;

  cniConflist = pkgs.writeText "10-fireactions.conflist" (
    builtins.toJSON {
      cniVersion = "0.4.0";
      name = "fireactions";
      plugins = [
        {
          type = "bridge";
          bridge = "fireactions-br0";
          isDefaultGateway = true;
          ipMasq = true;
          hairpinMode = true;
          mtu = 1500;
          ipam = {
            type = "host-local";
            subnet = cfg.cniSubnet;
            dataDir = "/var/run/cni";
            resolvConf = "/etc/resolv.conf";
          };
        }
        { type = "firewall"; }
        { type = "tc-redirect-tap"; }
      ];
    }
  );

  fireactionsConfig = pkgs.writeText "fireactions-config.yaml" (
    builtins.toJSON {
      bind_address = cfg.bindAddress;
      log_level = cfg.logLevel;
      github = {
        app_id = cfg.github.appId;
        # app_private_key is substituted at runtime from the key file
        app_private_key = "@GITHUB_APP_PRIVATE_KEY@";
      };
      containerd = {
        address = "/run/containerd/containerd.sock";
        namespace = "fireactions";
      };
      pools = map (pool: {
        name = pool.name;
        replicas = pool.replicas;
        shutdown_on_exit = true;
        runner = {
          inherit (pool)
            name
            image
            organization
            labels
            ;
          image_pull_policy = pool.imagePullPolicy;
          group_id = pool.groupId;
        };
        firecracker = {
          binary_path = "${pkgs.firecracker}/bin/firecracker";
          kernel_image_path = cfg.kernelImagePath;
          kernel_args = cfg.kernelArgs;
          machine_config = {
            vcpu_count = pool.vcpuCount;
            mem_size_mib = pool.memSizeMib;
          };
          metadata = { };
        };
      }) cfg.pools;
    }
  );
in
{
  options.custom.fireactions = {
    enable = lib.mkEnableOption "Fireactions GitHub Actions runner orchestrator";

    bindAddress = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1:8080";
      description = "Address for the Fireactions API server.";
    };

    logLevel = lib.mkOption {
      type = lib.types.enum [
        "debug"
        "info"
        "warn"
        "error"
      ];
      default = "info";
    };

    cniSubnet = lib.mkOption {
      type = lib.types.str;
      default = "10.0.100.0/24";
      description = "Subnet for microVM networking. Must not conflict with host LAN.";
    };

    kernelImagePath = lib.mkOption {
      type = lib.types.str;
      default = "${pkgs.linuxPackages.kernel.dev}/vmlinux";
      description = "Path to the uncompressed vmlinux kernel for Firecracker.";
    };

    kernelArgs = lib.mkOption {
      type = lib.types.str;
      default = "console=ttyS0 reboot=k panic=1 pci=off nomodules rw";
    };

    github = {
      appId = lib.mkOption {
        type = lib.types.int;
        description = "GitHub App ID for Fireactions.";
      };

      appPrivateKeyFile = lib.mkOption {
        type = lib.types.path;
        description = "Path to the GitHub App private key PEM file.";
      };
    };

    pools = lib.mkOption {
      type = lib.types.listOf (
        lib.types.submodule {
          options = {
            name = lib.mkOption {
              type = lib.types.str;
              description = "Pool name (also used as runner name prefix).";
            };
            replicas = lib.mkOption {
              type = lib.types.ints.positive;
              default = 1;
            };
            image = lib.mkOption {
              type = lib.types.str;
              default = "ghcr.io/hostinger/fireactions-images/ubuntu24.04:latest";
            };
            imagePullPolicy = lib.mkOption {
              type = lib.types.enum [
                "Always"
                "IfNotPresent"
                "Never"
              ];
              default = "IfNotPresent";
            };
            organization = lib.mkOption {
              type = lib.types.str;
              description = "GitHub organization name.";
            };
            groupId = lib.mkOption {
              type = lib.types.int;
              default = 1;
              description = "GitHub runner group ID.";
            };
            labels = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ "self-hosted" ];
            };
            vcpuCount = lib.mkOption {
              type = lib.types.ints.positive;
              default = 2;
            };
            memSizeMib = lib.mkOption {
              type = lib.types.ints.positive;
              default = 2048;
            };
          };
        }
      );
      default = [ ];
    };
  };

  config = lib.mkIf cfg.enable {
    # --- Firecracker ---
    environment.systemPackages = [ pkgs.firecracker ];

    # --- KVM access ---
    boot.kernelModules = [
      "kvm-intel"
      "kvm-amd"
    ];

    # --- IP forwarding ---
    boot.kernel.sysctl = {
      "net.ipv4.ip_forward" = 1;
      "net.ipv4.conf.all.forwarding" = 1;
    };

    # --- containerd with devmapper snapshotter ---
    virtualisation.containerd = {
      enable = true;
      settings = {
        plugins."io.containerd.snapshotter.v1.devmapper" = {
          pool_name = "containerd-thinpool";
          root_path = "/var/lib/containerd/devmapper";
          base_image_size = "30GB";
          discard_blocks = true;
        };
      };
    };

    # --- LVM thin provisioning ---
    services.lvm.boot.thin.enable = true;

    # --- CNI configuration ---
    environment.etc."cni/net.d/10-fireactions.conflist".source = cniConflist;

    # --- Fireactions service ---
    systemd.services.fireactions = {
      description = "Fireactions GitHub Actions Runner Orchestrator";
      after = [
        "network-online.target"
        "containerd.service"
      ];
      requires = [ "containerd.service" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];

      path = [
        pkgs.firecracker
        pkgs.containerd
        pkgs.cni-plugins
        pkgs.tc-redirect-tap
        pkgs.iptables
        pkgs.iproute2
      ];

      environment = {
        CNI_PATH = lib.makeBinPath [
          pkgs.cni-plugins
          pkgs.tc-redirect-tap
        ];
      };

      serviceConfig = {
        Type = "simple";
        Restart = "always";
        RestartSec = 10;
        KillMode = "process";

        ExecStartPre = pkgs.writeShellScript "fireactions-setup" ''
          # Substitute the GitHub App private key into the config
          mkdir -p /run/fireactions
          ${pkgs.gnused}/bin/sed \
            "s|@GITHUB_APP_PRIVATE_KEY@|$(cat ${cfg.github.appPrivateKeyFile})|" \
            ${fireactionsConfig} > /run/fireactions/config.yaml
          chmod 600 /run/fireactions/config.yaml
        '';

        ExecStart = "${pkgs.fireactions}/bin/fireactions server --config /run/fireactions/config.yaml";
      };
    };
  };
}
