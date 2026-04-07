{
  headscale = import ./headscale;
  caddy-l4 = import ./caddy-l4;
  tailscale = import ./tailscale;
  cloudflare-ddns = import ./cloudflare-ddns;
  ssh-server = import ./ssh-server;
  github-runner = import ./github-runner;
  github-runner-docker = import ./github-runner-docker;
  github-runner-cleanup = import ./github-runner-cleanup;
  fireactions = import ./fireactions;
  attic = import ./attic;
  attic-watch = import ./attic-watch;
  openvpn = import ./openvpn;
}
