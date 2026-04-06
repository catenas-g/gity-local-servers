# TOMORU application deployment on monooki (local network, IP-based access)
#
# Access:
#   http://192.168.128.199:3000  -- Web (public site)
#   http://192.168.128.199:3001  -- Admin (management dashboard)
#   http://192.168.128.199:3002  -- Kiosk (in-location display)
#   http://192.168.128.199:8081  -- API (REST)
#   http://192.168.128.199:8180  -- Keycloak (auth, managed separately)
#
# Keycloak admin console: http://192.168.128.199:8180/admin/
#   Initial credentials: admin / changeme (change after first login)
#
# Secrets (stored outside git in /var/lib/secrets/):
#   /var/lib/secrets/tomoru-api.env              -- SESSION_ENCRYPTION_KEY + OIDC_CLIENT_SECRET
#   /var/lib/secrets/tomoru-keycloak-db-pass     -- Keycloak DB password
{
  inputs,
  lib,
  pkgs,
  ...
}:
let
  monookiIp = "192.168.128.199";
  realmFile = ./keycloak-tomoru-realm.json;
in
{
  imports = [ inputs.tomoru.nixosModules.default ];

  # --- TOMORU Application Stack ---
  services.tomoru = {
    enable = true;

    # Required by module but unused (IP-based access, no domain routing)
    domain = "tomoru.internal";
    acmeEmail = "unused@example.com";

    # Disable SSL for local network HTTP access
    useSSL = false;

    # --- Secrets ---
    secrets.autoGenerate = true;

    # --- API ---
    api = {
      port = 8081; # 8080 is used by Attic
      logLevel = "info";

      allowedOrigins = [
        "http://${monookiIp}:3000"
        "http://${monookiIp}:3001"
        "http://${monookiIp}:3002"
      ];

      # Session cookies over plain HTTP
      sessionCookieSecure = false;

      oidc = {
        issuerUrl = "http://${monookiIp}:8180/realms/tomoru";
        publicUrl = "http://${monookiIp}:8180/realms/tomoru";
        clientId = "tomoru-admin";
        redirectUrl = "http://${monookiIp}:8081/api/auth/callback";
      };
    };

    # --- Frontends ---
    web = {
      hostname = monookiIp;
      apiPublicBaseUrl = "http://${monookiIp}:8081";
      apiInternalBaseUrl = "http://${monookiIp}:8081";
    };
    admin = {
      hostname = monookiIp;
      apiPublicBaseUrl = "http://${monookiIp}:8081";
      apiInternalBaseUrl = "http://${monookiIp}:8081";
    };
    kiosk = {
      hostname = monookiIp;
      apiPublicBaseUrl = "http://${monookiIp}:8081";
      apiInternalBaseUrl = "http://${monookiIp}:8081";
    };

    # --- nginx ---
    nginx.sslMode = "none";
  };

  # --- Keycloak (managed independently of TOMORU module) ---
  services.keycloak = {
    enable = true;
    initialAdminPassword = "changeme"; # Change via admin console after first login

    settings = {
      hostname = "http://${monookiIp}:8180";
      http-host = "0.0.0.0";
      http-port = 8180;
      proxy-headers = "xforwarded";
      http-enabled = true;
    };

    database = {
      type = "postgresql";
      createLocally = true;
      passwordFile = "/var/lib/secrets/tomoru-keycloak-db-pass";
    };
  };

  # Auto-generate Keycloak DB password on first boot
  system.activationScripts.keycloak-secrets = ''
    mkdir -p /var/lib/secrets

    if [ ! -f /var/lib/secrets/tomoru-keycloak-db-pass ]; then
      ${pkgs.openssl}/bin/openssl rand -base64 32 | tr -d '\n' \
        > /var/lib/secrets/tomoru-keycloak-db-pass
      chmod 600 /var/lib/secrets/tomoru-keycloak-db-pass
      echo "[keycloak-secrets] Generated tomoru-keycloak-db-pass"
    fi
  '';

  # --- Keycloak realm import (runs once after Keycloak starts) ---
  systemd.services.keycloak-import-realm = {
    description = "Import TOMORU realm into Keycloak";
    after = [ "keycloak.service" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };

    path = with pkgs; [
      curl
      jq
      coreutils
    ];

    script = ''
      set -euo pipefail

      # Wait for Keycloak to become ready
      echo "Waiting for Keycloak..."
      elapsed=0
      while ! curl -sf http://127.0.0.1:8180/health/ready > /dev/null 2>&1; do
        if [ "$elapsed" -ge 120 ]; then
          echo "ERROR: Keycloak did not become ready within 120s" >&2
          exit 1
        fi
        sleep 2
        elapsed=$((elapsed + 2))
      done
      echo "Keycloak is ready"

      # Check if realm already exists
      if curl -sf http://127.0.0.1:8180/realms/tomoru > /dev/null 2>&1; then
        echo "Realm 'tomoru' already exists, skipping import"
        exit 0
      fi

      # Get admin token
      TOKEN=$(curl -sf -X POST "http://127.0.0.1:8180/realms/master/protocol/openid-connect/token" \
        -d "grant_type=password" \
        -d "client_id=admin-cli" \
        -d "username=admin" \
        --data-urlencode "password=changeme" \
        | jq -r '.access_token')

      if [ -z "$TOKEN" ] || [ "$TOKEN" = "null" ]; then
        echo "ERROR: Failed to get admin token. If the admin password was changed, import the realm manually." >&2
        exit 1
      fi

      # Import realm
      HTTP_CODE=$(curl -s -o /dev/null -w '%{http_code}' -X POST "http://127.0.0.1:8180/admin/realms" \
        -H "Authorization: Bearer $TOKEN" \
        -H "Content-Type: application/json" \
        -d @${realmFile})

      if [ "$HTTP_CODE" = "201" ]; then
        echo "Realm 'tomoru' imported successfully"
      else
        echo "ERROR: Realm import failed with HTTP $HTTP_CODE" >&2
        exit 1
      fi
    '';
  };

  # --- OIDC client secret fetch (runs after realm import) ---
  # Fetches the client secret from Keycloak and writes it to tomoru-api.env
  systemd.services.tomoru-fetch-oidc-secret = {
    description = "Fetch TOMORU OIDC client secret from Keycloak";
    after = [ "keycloak-import-realm.service" ];
    requires = [ "keycloak-import-realm.service" ];
    before = [ "tomoru-api.service" ];
    requiredBy = [ "tomoru-api.service" ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };

    path = with pkgs; [
      curl
      jq
      coreutils
      gnugrep
    ];

    script = ''
      set -euo pipefail

      ENV_FILE="/var/lib/secrets/tomoru-api.env"

      # Skip if OIDC_CLIENT_SECRET is already present
      if grep -q '^OIDC_CLIENT_SECRET=' "$ENV_FILE" 2>/dev/null; then
        echo "OIDC_CLIENT_SECRET already present, skipping"
        exit 0
      fi

      # Get admin token
      TOKEN=$(curl -sf -X POST "http://127.0.0.1:8180/realms/master/protocol/openid-connect/token" \
        -d "grant_type=password" \
        -d "client_id=admin-cli" \
        -d "username=admin" \
        --data-urlencode "password=changeme" \
        | jq -r '.access_token')

      if [ -z "$TOKEN" ] || [ "$TOKEN" = "null" ]; then
        echo "ERROR: Failed to get admin token" >&2
        exit 1
      fi

      # Get client UUID
      CLIENT_UUID=$(curl -sf -H "Authorization: Bearer $TOKEN" \
        "http://127.0.0.1:8180/admin/realms/tomoru/clients?clientId=tomoru-admin" \
        | jq -r '.[0].id')

      if [ -z "$CLIENT_UUID" ] || [ "$CLIENT_UUID" = "null" ]; then
        echo "ERROR: Client 'tomoru-admin' not found" >&2
        exit 1
      fi

      # Get client secret
      CLIENT_SECRET=$(curl -sf -H "Authorization: Bearer $TOKEN" \
        "http://127.0.0.1:8180/admin/realms/tomoru/clients/$CLIENT_UUID/client-secret" \
        | jq -r '.value')

      if [ -z "$CLIENT_SECRET" ] || [ "$CLIENT_SECRET" = "null" ]; then
        echo "ERROR: Failed to retrieve client secret" >&2
        exit 1
      fi

      # Append to env file
      printf 'OIDC_CLIENT_SECRET=%s\n' "$CLIENT_SECRET" >> "$ENV_FILE"
      echo "OIDC_CLIENT_SECRET written successfully"
    '';
  };

  # --- Overrides for IP-based local deployment ---

  # Session cookie domain must match how users access the site
  systemd.services.tomoru-api.environment.SESSION_COOKIE_DOMAIN = lib.mkForce monookiIp;

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
}
