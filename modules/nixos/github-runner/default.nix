{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.custom.github-runner;
  hostname = config.networking.hostName;
  indices = lib.range 1 cfg.count;
  runnerName = i: "${hostname}-${toString i}";
  serviceUser = i: "github-runner-${hostname}-${toString i}";
in
{
  options.custom.github-runner.count = lib.mkOption {
    type = lib.types.ints.positive;
    default = 1;
    description = "Number of GitHub Actions runner instances to launch in parallel.";
  };

  config = {
    services.github-runners = lib.listToAttrs (
      map (i: {
        name = "${hostname}-${toString i}";
        value = {
          enable = true;
          url = "https://github.com/catenas-g";
          tokenFile = "/var/lib/secrets/github-runner-token";
          name = runnerName i;
          replace = true;
          extraLabels = [
            "self-hosted"
            "nixos"
            hostname
          ];
          # Use persistent storage instead of tmpfs (RuntimeDirectory)
          # to avoid ENOSPC during pnpm install / nix build
          workDir = "/var/lib/github-runner-work/${hostname}-${toString i}";
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
            StateDirectory = [
              "github-runner/${hostname}-${toString i}"
              "github-runner-work/${hostname}-${toString i}"
            ];
            SupplementaryGroups = [ "docker" ];
            BindPaths = [ "/var/run/docker.sock" ];
          };
        };
      }) indices
    );

    virtualisation.docker.enable = true;

    nix.settings.allowed-users = map serviceUser indices;
    nix.settings.trusted-users = map serviceUser indices;
  };
}
