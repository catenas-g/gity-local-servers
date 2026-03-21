{ pkgs, ... }:
{
  services.atticd = {
    enable = true;
    environmentFile = "/var/lib/secrets/atticd.env";
    settings = {
      listen = "[::]:8080";
      compression.type = "zstd";
    };
  };

  # JWT RS256秘密鍵の自動生成（nextcloud-admin-passパターンに倣う）
  system.activationScripts.atticd-jwt-secret = ''
    mkdir -p /var/lib/secrets
    if [ ! -f /var/lib/secrets/atticd.env ]; then
      SECRET=$(${pkgs.openssl}/bin/openssl genrsa -traditional 4096 | ${pkgs.coreutils}/bin/base64 -w0)
      echo "ATTIC_SERVER_TOKEN_RS256_SECRET_BASE64=$SECRET" > /var/lib/secrets/atticd.env
    fi
    chmod 600 /var/lib/secrets/atticd.env
  '';

  environment.systemPackages = [ pkgs.attic-client ];

  networking.firewall.allowedTCPPorts = [ 8080 ];
}
