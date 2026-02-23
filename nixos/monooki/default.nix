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
    tailscale
    ssh-server
  ]);

  # --- NextCloud ---
  services.nextcloud = {
    enable = true;
    hostName = "cloud.example.com"; # TODO: Replace with your domain
    package = pkgs.nextcloud31;
    https = true; # Behind Caddy reverse proxy on more-jump-more

    configureRedis = true;
    database.createLocally = true;

    config = {
      dbtype = "pgsql";
      adminpassFile = "/var/lib/secrets/nextcloud-admin-pass";
    };

    settings = {
      trusted_proxies = [
        "100.64.0.0/10" # Tailscale/Headscale network
      ];
      overwriteprotocol = "https";
    };

    maxUploadSize = "16G";
  };

  # --- Networking ---
  networking = {
    hostName = "monooki";
    networkmanager.enable = true;
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
