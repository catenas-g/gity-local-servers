{ config, pkgs, ... }:
{
  services.github-runners.default = {
    enable = true;
    url = "https://github.com/catenas-g";
    tokenFile = "/var/lib/secrets/github-runner-token";
    name = config.networking.hostName;
    replace = true;
    extraLabels = [
      "self-hosted"
      "nixos"
      "nix"
      config.networking.hostName
    ];
    extraPackages = with pkgs; [
      nix
      docker
      git
      curl
      jq
      gnutar
      gzip
    ];
    serviceOverrides = {
      PrivateDevices = false;
      PrivateUsers = false;
      RestrictNamespaces = false;
      SupplementaryGroups = [ "docker" ];
      BindPaths = [ "/var/run/docker.sock" ];
    };
  };

  virtualisation.docker.enable = true;

  nix.settings.allowed-users = [ "github-runner-default" ];
}
