# Attic watch-store: automatically push built paths to binary cache
{ pkgs, ... }:
let
  serverUrl = "http://192.168.128.199:8080";
  cacheName = "gity";
in
{
  environment.systemPackages = [ pkgs.attic-client ];

  systemd.services.attic-watch-store = {
    description = "Attic watch-store - auto push to binary cache";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      EnvironmentFile = "/var/lib/secrets/attic-watch-store.env";
      ExecStart = "${pkgs.writeShellScript "attic-watch-store" ''
        ${pkgs.attic-client}/bin/attic login ${cacheName} ${serverUrl} $ATTIC_TOKEN
        exec ${pkgs.attic-client}/bin/attic watch-store ${cacheName}:${cacheName}
      ''}";
      Restart = "always";
      RestartSec = 10;
    };
  };
}
