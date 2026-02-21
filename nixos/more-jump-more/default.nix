# NixOS configuration for more-jump-more (Raspberry Pi 4 jump server)
{ outputs, pkgs, ... }:
{
  imports = [
    ./hardware-configuration.nix
    ../../modules/common/nixpkgs.nix
  ]
  ++ (with outputs.modules.nixos; [
    headscale
    caddy-l4
    tailscale
    cloudflare-ddns
    ssh-server
  ]);

  # --- Caddy L4/L7 routing configuration ---
  services.caddy.settings = {
    apps = {
      # Layer 7: HTTP/HTTPS reverse proxy with automatic TLS
      http.servers.web = {
        listen = [ ":443" ];
        routes = [
          {
            match = [
              { host = [ "app.example.com" ]; } # TODO: Replace
            ];
            handle = [
              {
                handler = "reverse_proxy";
                upstreams = [ { dial = "100.64.0.2:8080"; } ]; # TODO: Replace
              }
            ];
          }
          {
            match = [
              { host = [ "api.example.com" ]; } # TODO: Replace
            ];
            handle = [
              {
                handler = "reverse_proxy";
                upstreams = [ { dial = "100.64.0.3:3000"; } ]; # TODO: Replace
              }
            ];
          }
        ];
      };

      # Layer 4: TCP/UDP proxy (protocol-agnostic)
      layer4.servers = {
        ssh = {
          listen = [ "0.0.0.0:2222" ];
          routes = [
            {
              handle = [
                {
                  handler = "proxy";
                  upstreams = [ { dial = [ "100.64.0.2:22" ]; } ]; # TODO: Replace
                }
              ];
            }
          ];
        };
        postgres = {
          listen = [ "0.0.0.0:5432" ];
          routes = [
            {
              handle = [
                {
                  handler = "proxy";
                  upstreams = [ { dial = [ "100.64.0.3:5432" ]; } ]; # TODO: Replace
                }
              ];
            }
          ];
        };
        game_udp = {
          listen = [ "udp/0.0.0.0:27015" ];
          routes = [
            {
              handle = [
                {
                  handler = "proxy";
                  upstreams = [ { dial = [ "udp/100.64.0.4:27015" ]; } ]; # TODO: Replace
                }
              ];
            }
          ];
        };
      };
    };
  };

  # --- Networking ---
  networking = {
    hostName = "more-jump-more";
    networkmanager.enable = true;
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
    useGlobalPkgs = true;
    useUserPackages = true;
    users.gity = {
      programs.git.enable = true;
      home.stateVersion = "25.11";
    };
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
