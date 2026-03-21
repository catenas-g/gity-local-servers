#!/usr/bin/env bash
# Attic watch-store のトークン設置スクリプト
# 使い方: ./scripts/setup-attic-watch.sh --help
set -euo pipefail

TOKEN_PATH="/var/lib/secrets/attic-watch-store.env"

usage() {
  cat <<'EOF'
Usage: setup-attic-watch.sh <command> <ssh-host>

Commands:
  deploy <ssh-host>   トークンを対話入力して設置
  status <ssh-host>   サービスの状態を確認

Examples:
  ./scripts/setup-attic-watch.sh deploy gity@192.168.128.200
  ./scripts/setup-attic-watch.sh deploy gity@monooki
  ./scripts/setup-attic-watch.sh status gity@192.168.128.200

Notes:
  - トークンは monooki 上で生成:
      sudo atticd-atticadm make-token --sub "gity" --validity "10y" \
        --pull gity --push gity --create-cache gity
EOF
}

deploy_to_host() {
  local host="$1"
  local token="$2"

  echo "トークンを $host:$TOKEN_PATH に設置中..."
  printf 'ATTIC_TOKEN=%s\n' "$token" |
    ssh "$host" 'sudo mkdir -p /var/lib/secrets && sudo tee '"$TOKEN_PATH"' >/dev/null && sudo chmod 600 '"$TOKEN_PATH"
  echo "設置完了!"
}

cmd_deploy() {
  local host="$1"

  echo ""
  echo "Attic トークンを入力してください。"
  echo "  monooki で以下を実行して生成:"
  echo "    sudo atticd-atticadm make-token --sub \"gity\" --validity \"10y\" \\"
  echo "      --pull gity --push gity --create-cache gity"
  echo ""
  read -rsp "Token: " token
  echo ""

  if [[ -z "$token" ]]; then
    echo "Error: 入力が空です。" >&2
    exit 1
  fi

  deploy_to_host "$host" "$token"
  echo ""
  echo "サービスを再起動するには:"
  echo "  ssh $host sudo systemctl restart attic-watch-store"
}

cmd_status() {
  local host="$1"

  echo ""
  echo "--- $host ---"
  ssh "$host" "
    if [ -f $TOKEN_PATH ]; then
      echo 'トークンファイル: 存在'
    else
      echo 'トークンファイル: 未設置'
    fi
    echo ''
    systemctl is-active attic-watch-store.service 2>/dev/null || echo 'サービス状態: 未起動'
    systemctl status attic-watch-store.service 2>/dev/null | head -10 || true
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
  deploy)
    [[ $# -ge 1 ]] || {
      echo "Error: SSH ホストを指定してください。" >&2
      exit 1
    }
    cmd_deploy "$1"
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
