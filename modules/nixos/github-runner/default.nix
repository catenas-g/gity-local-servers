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
  runnerUser = "github-runner";
  runnerGroup = "github-runner";
in
{
  options.custom.github-runner.count = lib.mkOption {
    type = lib.types.ints.positive;
    default = 1;
    description = "Number of GitHub Actions runner instances to launch in parallel.";
  };

  config = {
    users.users.${runnerUser} = {
      isSystemUser = true;
      group = runnerGroup;
      home = "/var/lib/github-runner";
      createHome = true;
    };
    users.groups.${runnerGroup} = { };

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
          # Explicit user/group disables DynamicUser, avoiding tmpfs ENOSPC
          user = runnerUser;
          group = runnerGroup;
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
            SupplementaryGroups = [ "docker" ];
            BindPaths = [ "/var/run/docker.sock" ];
          };
        };
      }) indices
    );

    # Ensure workDir directories exist with correct ownership
    systemd.tmpfiles.rules = map (
      i: "d /var/lib/github-runner-work/${hostname}-${toString i} 0750 ${runnerUser} ${runnerGroup} -"
    ) indices;

    virtualisation.docker.enable = true;

    nix.settings.allowed-users = [ runnerUser ];
    nix.settings.trusted-users = [ runnerUser ];
  };
}
