# TOMORU application deployment on monooki (local network, IP-based access)
#
# Access:
#   http://192.168.128.199:3000  -- Web (public site)
#   http://192.168.128.199:3001  -- Admin (management dashboard)
#   http://192.168.128.199:3002  -- Kiosk (in-location display)
#   http://192.168.128.199:8081  -- API
#   http://192.168.128.199:8180  -- Keycloak (auth)
#
# NOTE: NEXT_PUBLIC_API_BASE_URL is set as a runtime env var for SSR,
# but client-side JS uses the build-time value. If browser API calls fail,
# rebuild tomoru packages with: nextPublicApiBaseUrl = "http://192.168.128.199:8081"
{
  inputs,
  lib,
  pkgs,
  ...
}:
let
  monookiIp = "192.168.128.199";
in
{
  imports = [ inputs.tomoru.nixosModules.default ];

  # --- TOMORU Application Stack ---
  services.tomoru = {
    enable = true;

    # Required by module but unused (IP-based access, no domain routing)
    domain = "tomoru.internal";
    acmeEmail = "unused@example.com";

    api = {
      port = 8081; # 8080 is used by Attic

      environmentFile = "/var/lib/secrets/tomoru-api.env";

      allowedOrigins = [
        "http://${monookiIp}:3000"
        "http://${monookiIp}:3001"
        "http://${monookiIp}:3002"
      ];

      oidc = {
        issuerUrl = "http://${monookiIp}:8180/realms/tomoru";
        publicUrl = "http://${monookiIp}:8180/realms/tomoru";
        redirectUrl = "http://${monookiIp}:8081/api/auth/callback";
      };
    };

    # Point frontends to IP-based API URL
    web.apiPublicBaseUrl = "http://${monookiIp}:8081";
    admin.apiPublicBaseUrl = "http://${monookiIp}:8081";
    kiosk.apiPublicBaseUrl = "http://${monookiIp}:8081";
  };

  # --- Overrides for IP-based local deployment ---

  # Session cookie domain must match how users access the site
  systemd.services.tomoru-api.environment.SESSION_COOKIE_DOMAIN = lib.mkForce monookiIp;

  # Keycloak: listen on all interfaces and use IP-based hostname
  # (module defaults to 127.0.0.1 assuming nginx proxy)
  services.keycloak = {
    settings = {
      hostname = lib.mkForce "http://${monookiIp}:8180";
      http-host = lib.mkForce "0.0.0.0";
    };
    database.passwordFile = "/var/lib/secrets/keycloak-db-pass";
  };

  # Disable ACME/SSL on all tomoru nginx virtual hosts (local network, no TLS needed)
  services.nginx.virtualHosts = {
    "tomoru.internal" = {
      enableACME = lib.mkForce false;
      forceSSL = lib.mkForce false;
    };
    "admin.tomoru.internal" = {
      enableACME = lib.mkForce false;
      forceSSL = lib.mkForce false;
    };
    "kiosk.tomoru.internal" = {
      enableACME = lib.mkForce false;
      forceSSL = lib.mkForce false;
    };
    "api.tomoru.internal" = {
      enableACME = lib.mkForce false;
      forceSSL = lib.mkForce false;
    };
    "auth.tomoru.internal" = {
      enableACME = lib.mkForce false;
      forceSSL = lib.mkForce false;
    };
  };

  # Resolve PostgreSQL package conflict (NextCloud may use a different default)
  services.postgresql.package = lib.mkForce pkgs.postgresql_17;

  # --- Firewall: open ports for direct IP access ---
  networking.firewall.allowedTCPPorts = [
    3000 # TOMORU web
    3001 # TOMORU admin
    3002 # TOMORU kiosk
    8081 # TOMORU API
    8180 # Keycloak
  ];

  # --- Secrets auto-generation (first boot) ---
  system.activationScripts.tomoru-secrets = ''
    mkdir -p /var/lib/secrets

    if [ ! -f /var/lib/secrets/tomoru-api.env ]; then
      SESSION_KEY=$(${pkgs.openssl}/bin/openssl rand -hex 32)
      cat > /var/lib/secrets/tomoru-api.env <<ENVEOF
    SESSION_ENCRYPTION_KEY=$SESSION_KEY
    OIDC_CLIENT_SECRET=changeme
    ENVEOF
      chmod 600 /var/lib/secrets/tomoru-api.env
    fi

    if [ ! -f /var/lib/secrets/keycloak-db-pass ]; then
      ${pkgs.openssl}/bin/openssl rand -base64 32 > /var/lib/secrets/keycloak-db-pass
      chmod 600 /var/lib/secrets/keycloak-db-pass
    fi
  '';
}
