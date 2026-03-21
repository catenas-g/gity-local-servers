{ config, pkgs, ... }:
{
  services.github-runners.default = {
    enable = true;
    url = "https://github.com/catenas-g";
    tokenFile = "/var/lib/secrets/github-runner-token";
    name = config.networking.hostName;
    replace = true;
    extraLabels = [
      "nixos"
      "nix"
    ];
    extraPackages = with pkgs; [
      nix
      git
      curl
      jq
      gnutar
      gzip
    ];
  };

  nix.settings.allowed-users = [ "github-runner-default" ];
}
