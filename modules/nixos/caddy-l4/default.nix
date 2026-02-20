{ pkgs, ... }:
{
  services.caddy = {
    enable = true;

    # Custom build with L4 (layer 4) plugin for TCP/UDP proxying
    package = pkgs.caddy.withPlugins {
      plugins = [ "github.com/mholt/caddy-l4@v0.0.0-20260216070754-eca560d759c9" ];
      hash = "sha256-HhI0s8bi+T89dz0V0yfrTU/1NTK5wJUtxxn7Sg9Fi9g=";
    };
  };

  networking.firewall = {
    allowedTCPPorts = [
      80 # HTTP / ACME challenge
      443 # HTTPS (L7 reverse proxy)
      2222 # SSH relay (L4)
      5432 # PostgreSQL relay (L4)
    ];
    allowedUDPPorts = [
      27015 # Game server relay (L4)
    ];
  };
}
