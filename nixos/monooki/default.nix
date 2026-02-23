# NixOS configuration for monooki (x86_64 NextCloud server)
{
  inputs,
  outputs,
  pkgs,
  ...
}:
{
  imports = [
    ./hardware-configuration.nix
    ../../modules/common/nixpkgs.nix
  ]
  ++ (with outputs.modules.nixos; [
    # tailscale
    ssh-server
  ]);

  # --- Boot ---
  boot.initrd.supportedFilesystems = [ "btrfs" ];
  boot.loader = {
    grub = {
      enable = true;
      efiSupport = true;
      device = "nodev";
    };
    efi.canTouchEfiVariables = true;
  };

  # --- NextCloud ---
  # Ensure admin password file exists before nextcloud-setup runs
  system.activationScripts.nextcloud-admin-pass = ''
    mkdir -p /var/lib/secrets
    if [ ! -f /var/lib/secrets/nextcloud-admin-pass ]; then
      ${pkgs.openssl}/bin/openssl rand -base64 32 > /var/lib/secrets/nextcloud-admin-pass
    fi
    chmod 600 /var/lib/secrets/nextcloud-admin-pass
  '';

  services.nextcloud = {
    enable = true;
    hostName = "cloud.example.com"; # TODO: Replace with your domain
    package = pkgs.nextcloud31;
    https = true;

    configureRedis = true;
    database.createLocally = true;

    config = {
      dbtype = "pgsql";
      adminpassFile = "/var/lib/secrets/nextcloud-admin-pass";
    };

    settings = {
      # Headscale は現在使用停止中
      # trusted_proxies = [
      #   "100.64.0.0/10" # Tailscale/Headscale network
      # ];
      trusted_domains = [
        "192.168.128.199"
      ];
      overwriteprotocol = "https";
    };

    maxUploadSize = "16G";
  };

  # --- Btrfs RAID1 ---
  services.btrfs.autoScrub = {
    enable = true;
    interval = "monthly";
    fileSystems = [ "/" ];
  };

  environment.systemPackages = with pkgs; [
    btrfs-progs
    compsize
  ];

  # --- Networking ---
  networking = {
    hostName = "monooki";
    networkmanager = {
      enable = true;
      ensureProfiles.profiles.static-ens2s0 = {
        connection = {
          id = "static-ens2s0";
          type = "ethernet";
          interface-name = "ens2s0";
          autoconnect = "true";
        };
        ipv4 = {
          method = "manual";
          addresses = "192.168.128.199/24";
          gateway = "192.168.128.1";
          dns = "192.168.128.1";
        };
      };
    };
    firewall.allowedTCPPorts = [
      80 # HTTP (nginx for NextCloud)
    ];
  };

  # --- User ---
  users.users.gity = {
    isNormalUser = true;
    extraGroups = [
      "wheel"
      "networkmanager"
    ];
    initialPassword = "password";
    shell = pkgs.fish;
    openssh.authorizedKeys.keys = [
      # TODO: Add your SSH public key
      # "ssh-ed25519 AAAA... user@host"
    ];
  };

  programs.fish.enable = true;

  # --- Home Manager ---
  home-manager = {
    extraSpecialArgs = { inherit inputs outputs; };
    users.gity = import ../../home-manager/gity;
  };

  security.sudo.wheelNeedsPassword = false;

  # --- Nix ---
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  # --- Locale ---
  time.timeZone = "Asia/Tokyo";

  system.stateVersion = "25.11";
}
