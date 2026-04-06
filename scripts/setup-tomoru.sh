#!/usr/bin/env bash
# TOMORU アプリケーションスタックのシークレット設置・管理スクリプト
# 使い方: ./scripts/setup-tomoru.sh --help
set -euo pipefail

SECRETS_DIR="/var/lib/secrets"
KC_ADMIN_ENV="$SECRETS_DIR/tomoru-keycloak-admin.env"
KC_DB_PASS="$SECRETS_DIR/tomoru-keycloak-db-pass"
API_ENV="$SECRETS_DIR/tomoru-api.env"

usage() {
  cat <<'EOF'
Usage: setup-tomoru.sh <command> <ssh-host> [args...]

Commands:
  init <ssh-host>                  全シークレットを生成して設置 (初回デプロイ用)
  deploy-secret <ssh-host> <name>  個別シークレットを対話入力して設置
  status <ssh-host>                シークレットとサービスの状態を確認

Secret names (deploy-secret 用):
  keycloak-admin    Keycloak 管理者パスワード
  keycloak-db       Keycloak DB パスワード
  session-key       TOMORU API セッション暗号化キー
  oidc-secret       OIDC client secret

Examples:
  ./scripts/setup-tomoru.sh init gity@192.168.128.199
  ./scripts/setup-tomoru.sh deploy-secret gity@192.168.128.199 oidc-secret
  ./scripts/setup-tomoru.sh status gity@192.168.128.199

Notes:
  - init は既存シークレットを上書きしません (安全)
  - deploy-secret は既存値を上書きします
  - OIDC client secret は Keycloak 管理コンソールまたは realm JSON から取得してください
EOF
}

# --- ヘルパー ---

generate_secret() {
  openssl rand -base64 24 | tr -d '\n'
}

generate_hex_key() {
  openssl rand -hex 32
}

deploy_file() {
  local host="$1"
  local path="$2"
  local content="$3"

  printf '%s' "$content" |
    ssh "$host" 'sudo mkdir -p '"$SECRETS_DIR"' && sudo tee '"$path"' >/dev/null && sudo chmod 600 '"$path"
}

# --- コマンド ---

cmd_init() {
  local host="$1"

  echo "TOMORU シークレットを $host に設置します..."
  echo ""

  # Keycloak admin
  echo "--- Keycloak 管理者認証情報 ---"
  local kc_exists
  kc_exists=$(ssh "$host" "sudo test -f $KC_ADMIN_ENV && echo yes || echo no" 2>/dev/null)
  if [[ "$kc_exists" == "yes" ]]; then
    echo "  $KC_ADMIN_ENV: 既に存在 (スキップ)"
  else
    local kc_pass
    kc_pass=$(generate_secret)
    deploy_file "$host" "$KC_ADMIN_ENV" "$(printf 'KC_BOOTSTRAP_ADMIN_USERNAME=admin\nKC_BOOTSTRAP_ADMIN_PASSWORD=%s\n' "$kc_pass")"
    echo "  $KC_ADMIN_ENV: 生成完了"
    echo "  管理者パスワード: $kc_pass"
    echo "  (このパスワードは再表示されません。安全に保管してください)"
  fi

  echo ""

  # Keycloak DB
  echo "--- Keycloak DB パスワード ---"
  local db_exists
  db_exists=$(ssh "$host" "sudo test -f $KC_DB_PASS && echo yes || echo no" 2>/dev/null)
  if [[ "$db_exists" == "yes" ]]; then
    echo "  $KC_DB_PASS: 既に存在 (スキップ)"
  else
    local db_pass
    db_pass=$(generate_secret)
    deploy_file "$host" "$KC_DB_PASS" "$db_pass"
    echo "  $KC_DB_PASS: 生成完了"
  fi

  echo ""

  # TOMORU API session key
  echo "--- TOMORU API セッションキー ---"
  local api_exists
  api_exists=$(ssh "$host" "sudo test -f $API_ENV && echo yes || echo no" 2>/dev/null)
  if [[ "$api_exists" == "yes" ]]; then
    echo "  $API_ENV: 既に存在 (スキップ)"
  else
    local session_key
    session_key=$(generate_hex_key)
    deploy_file "$host" "$API_ENV" "$(printf 'SESSION_ENCRYPTION_KEY=%s\n' "$session_key")"
    echo "  $API_ENV: 生成完了"
  fi

  echo ""
  echo "シークレットの設置が完了しました。"
  echo ""
  echo "次のステップ:"
  echo "  1. OIDC_CLIENT_SECRET を tomoru-api.env に追加:"
  echo "     ./scripts/setup-tomoru.sh deploy-secret $host oidc-secret"
  echo "  2. NixOS をリビルド:"
  echo "     ssh $host sudo nixos-rebuild switch --flake /path/to/gity-local-servers#monooki"
  echo "  3. サービス状態を確認:"
  echo "     ./scripts/setup-tomoru.sh status $host"
}

cmd_deploy_secret() {
  local host="$1"
  local name="$2"

  case "$name" in
    keycloak-admin)
      echo ""
      echo "Keycloak 管理者パスワードを入力してください。"
      echo "  ユーザー名は 'admin' 固定です。"
      echo ""
      read -rsp "Password: " password
      echo ""

      if [[ -z "$password" ]]; then
        echo "Error: 入力が空です。" >&2
        exit 1
      fi

      deploy_file "$host" "$KC_ADMIN_ENV" "$(printf 'KC_BOOTSTRAP_ADMIN_USERNAME=admin\nKC_BOOTSTRAP_ADMIN_PASSWORD=%s\n' "$password")"
      echo "設置完了: $KC_ADMIN_ENV"
      echo ""
      echo "Keycloak を再起動するには:"
      echo "  ssh $host sudo systemctl restart keycloak"
      ;;

    keycloak-db)
      echo ""
      echo "Keycloak DB パスワードを入力してください。"
      echo ""
      read -rsp "Password: " password
      echo ""

      if [[ -z "$password" ]]; then
        echo "Error: 入力が空です。" >&2
        exit 1
      fi

      deploy_file "$host" "$KC_DB_PASS" "$password"
      echo "設置完了: $KC_DB_PASS"
      echo ""
      echo "Warning: DB パスワードの変更は PostgreSQL 側の変更も必要です。"
      echo "  初回デプロイ前に設定することを推奨します。"
      ;;

    session-key)
      echo ""
      echo "セッション暗号化キーを入力してください (64文字の hex 文字列)。"
      echo "  自動生成する場合は空のまま Enter を押してください。"
      echo ""
      read -rsp "Key (空で自動生成): " key
      echo ""

      if [[ -z "$key" ]]; then
        key=$(generate_hex_key)
        echo "キーを自動生成しました。"
      elif [[ ! "$key" =~ ^[0-9a-fA-F]{64}$ ]]; then
        echo "Warning: 入力が64文字の hex 文字列ではありません。"
        read -rp "続行しますか? [y/N]: " confirm
        [[ "$confirm" =~ ^[yY]$ ]] || exit 1
      fi

      # 既存の OIDC_CLIENT_SECRET を保持
      local existing_oidc=""
      existing_oidc=$(ssh "$host" "sudo grep '^OIDC_CLIENT_SECRET=' $API_ENV 2>/dev/null || true")

      local content
      content="$(printf 'SESSION_ENCRYPTION_KEY=%s\n' "$key")"
      if [[ -n "$existing_oidc" ]]; then
        content="$content"$'\n'"$existing_oidc"
      fi

      deploy_file "$host" "$API_ENV" "$content"
      echo "設置完了: $API_ENV"
      echo ""
      echo "TOMORU API を再起動するには:"
      echo "  ssh $host sudo systemctl restart tomoru-api"
      ;;

    oidc-secret)
      echo ""
      echo "OIDC client secret を入力してください。"
      echo "  Keycloak 管理コンソール > Clients > tomoru-admin > Credentials から取得してください。"
      echo ""
      read -rsp "Secret: " secret
      echo ""

      if [[ -z "$secret" ]]; then
        echo "Error: 入力が空です。" >&2
        exit 1
      fi

      # 既存の SESSION_ENCRYPTION_KEY を保持
      local existing_session=""
      existing_session=$(ssh "$host" "sudo grep '^SESSION_ENCRYPTION_KEY=' $API_ENV 2>/dev/null || true")

      if [[ -z "$existing_session" ]]; then
        echo "Warning: SESSION_ENCRYPTION_KEY が設定されていません。先に init を実行してください。" >&2
        exit 1
      fi

      local content
      content="${existing_session}"$'\n'"$(printf 'OIDC_CLIENT_SECRET=%s\n' "$secret")"

      deploy_file "$host" "$API_ENV" "$content"
      echo "設置完了: $API_ENV"
      echo ""
      echo "TOMORU API を再起動するには:"
      echo "  ssh $host sudo systemctl restart tomoru-api"
      ;;

    *)
      echo "Error: 不明なシークレット名 '$name'" >&2
      echo "有効な名前: keycloak-admin, keycloak-db, session-key, oidc-secret" >&2
      exit 1
      ;;
  esac
}

cmd_status() {
  local host="$1"

  echo ""
  echo "--- $host: TOMORU シークレット ---"
  ssh "$host" "sudo bash -s" <<'REMOTE'
for f in tomoru-keycloak-admin.env tomoru-keycloak-db-pass tomoru-api.env; do
  path="/var/lib/secrets/$f"
  if [ -f "$path" ]; then
    printf '  %-30s OK\n' "$f"
  else
    printf '  %-30s 未設置\n' "$f"
  fi
done

echo ""
echo "--- tomoru-api.env の内容 ---"
if [ -f /var/lib/secrets/tomoru-api.env ]; then
  # 値をマスクして表示
  while IFS='=' read -r key value; do
    if [ -n "$key" ] && [[ "$key" != \#* ]]; then
      printf '  %s=%s...%s\n' "$key" "${value:0:4}" "${value: -4}"
    fi
  done < /var/lib/secrets/tomoru-api.env
else
  echo "  (ファイル未設置)"
fi
REMOTE

  echo ""
  echo "--- $host: TOMORU サービス ---"
  ssh "$host" "
    printf '  %-35s %s\n' 'keycloak' \"\$(systemctl is-active keycloak.service 2>/dev/null || echo 'inactive')\"
    printf '  %-35s %s\n' 'tomoru-migrate' \"\$(systemctl is-active tomoru-migrate.service 2>/dev/null || echo 'inactive')\"
    printf '  %-35s %s\n' 'tomoru-api' \"\$(systemctl is-active tomoru-api.service 2>/dev/null || echo 'inactive')\"
    printf '  %-35s %s\n' 'tomoru-web' \"\$(systemctl is-active tomoru-web.service 2>/dev/null || echo 'inactive')\"
    printf '  %-35s %s\n' 'tomoru-admin' \"\$(systemctl is-active tomoru-admin.service 2>/dev/null || echo 'inactive')\"
    printf '  %-35s %s\n' 'tomoru-kiosk' \"\$(systemctl is-active tomoru-kiosk.service 2>/dev/null || echo 'inactive')\"
  " 2>/dev/null || echo "(SSH 接続失敗)"

  echo ""
  echo "--- $host: Keycloak ヘルスチェック ---"
  ssh "$host" "
    if curl -sf http://127.0.0.1:8180/health/ready >/dev/null 2>&1; then
      echo '  Keycloak: ready'
    else
      echo '  Keycloak: not ready'
    fi
  " 2>/dev/null || echo "(SSH 接続失敗)"
}

# --- Main ---
if [[ $# -lt 1 ]]; then
  usage
  exit 1
fi

CMD="${1:-}"
shift

case "$CMD" in
  init)
    [[ $# -ge 1 ]] || {
      echo "Error: SSH ホストを指定してください。" >&2
      exit 1
    }
    cmd_init "$1"
    ;;
  deploy-secret)
    [[ $# -ge 2 ]] || {
      echo "Error: SSH ホストとシークレット名を指定してください。" >&2
      echo "Usage: setup-tomoru.sh deploy-secret <ssh-host> <name>" >&2
      exit 1
    }
    cmd_deploy_secret "$1" "$2"
    ;;
  status)
    [[ $# -ge 1 ]] || {
      echo "Error: SSH ホストを指定してください。" >&2
      exit 1
    }
    cmd_status "$1"
    ;;
  -h | --help | help)
    usage
    ;;
  *)
    echo "Error: 不明なコマンド '$CMD'" >&2
    echo ""
    usage
    exit 1
    ;;
esac
