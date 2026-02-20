{ ... }:
{
  services.cloudflare-dyndns = {
    enable = true;
    apiTokenFile = "/var/lib/secrets/cloudflare-api-token";
    domains = [
      "hs.example.com" # TODO: Replace with your domains
      "app.example.com"
      "api.example.com"
    ];
    frequency = "*:0/5"; # Every 5 minutes
    ipv4 = true;
    ipv6 = false;
    proxied = false; # Must be false for L4 services (SSH, DB, etc.)
    deleteMissing = false;
  };
}
