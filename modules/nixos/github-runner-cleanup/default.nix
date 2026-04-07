{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.custom.github-runner-cleanup;

  cleanupScript = pkgs.writeShellScript "github-runner-cleanup" ''
    set -euo pipefail

    TOKEN_FILE="${cfg.tokenFile}"
    ORG="${cfg.orgName}"

    if [ ! -f "$TOKEN_FILE" ]; then
      echo "Token file not found: $TOKEN_FILE" >&2
      exit 1
    fi

    PAT=$(cat "$TOKEN_FILE")

    echo "Fetching offline runners for org: $ORG"

    # Paginate through all runners and collect offline runner IDs
    page=1
    deleted=0
    while true; do
      response=$(${pkgs.curl}/bin/curl -s \
        -H "Authorization: token $PAT" \
        -H "Accept: application/vnd.github+json" \
        "https://api.github.com/orgs/$ORG/actions/runners?per_page=100&page=$page")

      # Extract offline runner IDs
      ids=$(echo "$response" | ${pkgs.jq}/bin/jq -r '.runners[] | select(.status == "offline") | .id' 2>/dev/null)

      if [ -z "$ids" ]; then
        # No more offline runners on this page
        total=$(echo "$response" | ${pkgs.jq}/bin/jq -r '.total_count // 0' 2>/dev/null)
        fetched=$(echo "$response" | ${pkgs.jq}/bin/jq -r '.runners | length' 2>/dev/null)
        if [ "$fetched" = "0" ] || [ "$fetched" = "null" ]; then
          break
        fi
        page=$((page + 1))
        continue
      fi

      for id in $ids; do
        echo "Deleting offline runner: $id"
        ${pkgs.curl}/bin/curl -s -X DELETE \
          -H "Authorization: token $PAT" \
          -H "Accept: application/vnd.github+json" \
          "https://api.github.com/orgs/$ORG/actions/runners/$id" || true
        deleted=$((deleted + 1))
      done

      page=$((page + 1))
    done

    echo "Cleanup complete. Deleted $deleted offline runner(s)."
  '';
in
{
  options.custom.github-runner-cleanup = {
    enable = lib.mkEnableOption "Periodic cleanup of offline GitHub Actions runners";

    orgName = lib.mkOption {
      type = lib.types.str;
      default = "catenas-g";
      description = "GitHub organization name.";
    };

    tokenFile = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/secrets/github-runner-token";
      description = "Path to file containing the GitHub PAT with runner management permissions.";
    };

    interval = lib.mkOption {
      type = lib.types.str;
      default = "hourly";
      description = "Systemd calendar expression for cleanup frequency.";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.github-runner-cleanup = {
      description = "Cleanup offline GitHub Actions runners";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = cleanupScript;
      };
    };

    systemd.timers.github-runner-cleanup = {
      description = "Periodic cleanup of offline GitHub Actions runners";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = cfg.interval;
        Persistent = true;
        RandomizedDelaySec = "5m";
      };
    };
  };
}
