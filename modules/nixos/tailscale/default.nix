{ ... }:
{
  services.tailscale = {
    enable = true;
    # Kernel mode (default) — required for Caddy to route to 100.64.0.x directly.
    # After first boot, register with:
    #   sudo tailscale up --login-server=http://localhost:8080
  };

  networking.firewall = {
    # WireGuard UDP port used by Tailscale
    allowedUDPPorts = [ 41641 ];
    # Trust traffic from the tailnet
    trustedInterfaces = [ "tailscale0" ];
  };
}
