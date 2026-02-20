{
  headscale = import ./headscale;
  caddy-l4 = import ./caddy-l4;
  tailscale = import ./tailscale;
  cloudflare-ddns = import ./cloudflare-ddns;
  ssh-server = import ./ssh-server;
}
