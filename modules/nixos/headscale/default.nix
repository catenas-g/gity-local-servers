{ config, ... }:
{
  services.headscale = {
    enable = true;
    address = "0.0.0.0";
    port = 8080;

    settings = {
      server_url = "https://hs.example.com"; # TODO: Replace with your domain

      prefixes = {
        v4 = "100.64.0.0/10";
        v6 = "fd7a:115c:a1e0::/48";
        allocation = "sequential";
      };

      dns = {
        magic_dns = true;
        base_domain = "tailnet.example.com"; # TODO: Replace with your domain
        nameservers.global = [
          "1.1.1.1"
          "1.0.0.1"
        ];
      };

      logtail.enabled = false;
    };
  };

  # Make headscale CLI available system-wide
  environment.systemPackages = [ config.services.headscale.package ];

  # ACL policy: only allow the Pi (Caddy) to reach backend services
  environment.etc."headscale/acl.json".text = builtins.toJSON {
    hosts = {
      raspberry-pi = "100.64.0.1";
      machine-a = "100.64.0.2"; # TODO: Replace with actual tailnet IPs
      machine-b = "100.64.0.3";
      machine-c = "100.64.0.4";
    };
    acls = [
      {
        action = "accept";
        src = [ "raspberry-pi" ];
        dst = [
          "machine-a:22"
          "machine-a:8080"
          "machine-b:3000"
          "machine-b:5432"
          "machine-c:27015"
        ];
      }
    ];
  };

  networking.firewall.allowedTCPPorts = [ 8080 ];
}
