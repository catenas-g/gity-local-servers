{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.custom.github-runner-docker;
  hostname = config.networking.hostName;

  workDir = "/tmp/github-runner";
  projectDir = "/var/lib/github-runner-docker";

  dockerfile = ./Dockerfile;

  composeFile = pkgs.writeText "compose.yml" ''
    services:
      runner:
        build: .
        restart: unless-stopped
        environment:
          RUNNER_SCOPE: org
          ORG_NAME: "${cfg.orgName}"
          LABELS: "${lib.concatStringsSep "," cfg.labels}"
          RUNNER_NAME_PREFIX: "${hostname}"
          EPHEMERAL: "true"
          START_DOCKER_SERVICE: "true"
          RUNNER_WORKDIR: "${workDir}"
        env_file:
          - .env
        volumes:
          - /var/run/docker.sock:/var/run/docker.sock
          - ${workDir}:${workDir}
        deploy:
          replicas: ${toString cfg.count}
  '';
in
{
  options.custom.github-runner-docker = {
    enable = lib.mkEnableOption "Docker-based GitHub Actions runner";

    count = lib.mkOption {
      type = lib.types.ints.positive;
      default = 1;
      description = "Number of GitHub Actions runner instances to launch in parallel.";
    };

    orgName = lib.mkOption {
      type = lib.types.str;
      default = "catenas-g";
      description = "GitHub organization name.";
    };

    labels = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "self-hosted"
        "ubuntu"
      ];
      description = "Labels for the runner instances.";
    };

    tokenFile = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/secrets/github-runner-token";
      description = "Path to file containing the GitHub runner registration token (PAT).";
    };
  };

  config = lib.mkIf cfg.enable {
    virtualisation.docker.enable = true;

    systemd.tmpfiles.rules = [
      "d ${projectDir} 0750 root root -"
      "d ${workDir} 0777 root root -"
    ];

    systemd.services.github-runner-docker = {
      description = "GitHub Actions Runner (Docker Compose)";
      after = [
        "docker.service"
        "network-online.target"
      ];
      requires = [ "docker.service" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];

      path = [ pkgs.docker ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        WorkingDirectory = projectDir;

        ExecStartPre = pkgs.writeShellScript "github-runner-docker-setup" ''
          # Deploy Dockerfile and compose.yml
          cp -f ${dockerfile} ${projectDir}/Dockerfile
          cp -f ${composeFile} ${projectDir}/compose.yml

          # Create .env from token file
          echo "ACCESS_TOKEN=$(cat ${cfg.tokenFile})" > ${projectDir}/.env
          chmod 600 ${projectDir}/.env
        '';

        ExecStart = "${pkgs.docker}/bin/docker compose up -d --build --remove-orphans";
        ExecStop = "${pkgs.docker}/bin/docker compose down";
      };
    };
  };
}
