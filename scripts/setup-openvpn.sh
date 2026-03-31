#!/usr/bin/env bash
# OpenVPN PKI 初期化・クライアント証明書管理スクリプト
# 使い方: ./scripts/setup-openvpn.sh --help
set -euo pipefail

PKI_DIR="/etc/openvpn/pki"
CERT_DIR="/etc/openvpn"
CLIENTS_DIR="/etc/openvpn/clients"

usage() {
  cat <<'EOF'
Usage: setup-openvpn.sh <command> <ssh-host> [args...]

Commands:
  init <ssh-host>                 PKI 初期化 (CA + サーバー証明書 + DH パラメータ)
  add-client <ssh-host> <name>    クライアント証明書の生成
  get-ovpn <ssh-host> <name>      .ovpn ファイルをローカルにダウンロード
  list <ssh-host>                 発行済み証明書の一覧
  status <ssh-host>               PKI と OpenVPN サービスの状態確認

Examples:
  ./scripts/setup-openvpn.sh init gity@192.168.128.200
  ./scripts/setup-openvpn.sh add-client gity@192.168.128.200 phone
  ./scripts/setup-openvpn.sh get-ovpn gity@192.168.128.200 phone
  ./scripts/setup-openvpn.sh list gity@192.168.128.200
  ./scripts/setup-openvpn.sh status gity@192.168.128.200

Notes:
  - init は PKI 未作成時のみ実行可能（再初期化はできません）
  - get-ovpn 実行前に OPENVPN_SERVER_ADDR 環境変数でサーバーアドレスを指定してください
    例: OPENVPN_SERVER_ADDR=vpn.example.com ./scripts/setup-openvpn.sh get-ovpn ...
  - DH パラメータ生成には数分かかる場合があります
EOF
}

cmd_init() {
  local host="$1"

  echo "PKI を $host 上で初期化します..."

  # 既存の PKI チェック
  if ssh "$host" "sudo test -d $PKI_DIR" 2>/dev/null; then
    echo "Error: PKI は既に初期化されています ($PKI_DIR)" >&2
    echo "再初期化する場合は先に $PKI_DIR を削除してください。" >&2
    exit 1
  fi

  ssh "$host" "sudo bash -s" <<REMOTE
set -euo pipefail
export EASYRSA_PKI="$PKI_DIR"
export EASYRSA_BATCH=1
export EASYRSA_REQ_CN="OpenVPN-CA"

echo "==> PKI 初期化..."
easyrsa init-pki

echo "==> CA 構築..."
easyrsa build-ca nopass

echo "==> サーバー証明書生成..."
easyrsa gen-req server nopass
easyrsa sign-req server server

echo "==> DH パラメータ生成 (時間がかかります)..."
easyrsa gen-dh

echo "==> 証明書を $CERT_DIR に配置..."
cp "$PKI_DIR/ca.crt"             "$CERT_DIR/ca.pem"
cp "$PKI_DIR/issued/server.crt"  "$CERT_DIR/server.pem"
cp "$PKI_DIR/private/server.key" "$CERT_DIR/server-key.pem"
cp "$PKI_DIR/dh.pem"             "$CERT_DIR/dh2048.pem"

chmod 600 "$CERT_DIR/server-key.pem"

echo ""
echo "PKI 初期化完了!"
REMOTE

  echo ""
  echo "OpenVPN を再起動するには:"
  echo "  ssh $host sudo systemctl restart openvpn-server.service"
}

cmd_add_client() {
  local host="$1"
  local name="$2"

  echo "クライアント証明書 '$name' を $host 上で生成します..."

  ssh "$host" "sudo bash -s" <<REMOTE
set -euo pipefail
export EASYRSA_PKI="$PKI_DIR"
export EASYRSA_BATCH=1

if [ ! -d "$PKI_DIR" ]; then
  echo "Error: PKI が未初期化です。先に init を実行してください。" >&2
  exit 1
fi

if [ -f "$PKI_DIR/issued/${name}.crt" ]; then
  echo "Error: '$name' の証明書は既に存在します。" >&2
  exit 1
fi

echo "==> クライアント証明書生成..."
easyrsa gen-req "$name" nopass
easyrsa sign-req client "$name"

mkdir -p "$CLIENTS_DIR"

# .ovpn ファイル生成
cat > "$CLIENTS_DIR/${name}.ovpn" <<OVPN
client
dev tun
proto udp
remote YOUR_SERVER_IP 1194
resolv-retry infinite
nobind
persist-key
persist-tun
cipher AES-256-GCM
verb 3

<ca>
\$(cat "$PKI_DIR/ca.crt")
</ca>

<cert>
\$(cat "$PKI_DIR/issued/${name}.crt")
</cert>

<key>
\$(cat "$PKI_DIR/private/${name}.key")
</key>
OVPN

chmod 600 "$CLIENTS_DIR/${name}.ovpn"

echo ""
echo "クライアント証明書の生成完了!"
echo "  証明書: $PKI_DIR/issued/${name}.crt"
echo "  秘密鍵: $PKI_DIR/private/${name}.key"
echo "  .ovpn:  $CLIENTS_DIR/${name}.ovpn"
REMOTE
}

cmd_get_ovpn() {
  local host="$1"
  local name="$2"
  local server_addr="${OPENVPN_SERVER_ADDR:-}"
  local local_out="./${name}.ovpn"

  # リモートに .ovpn が存在するか確認
  if ! ssh "$host" "sudo test -f $CLIENTS_DIR/${name}.ovpn" 2>/dev/null; then
    echo "Error: '$name' の .ovpn ファイルが見つかりません。" >&2
    echo "先に add-client を実行してください。" >&2
    exit 1
  fi

  echo ".ovpn ファイルをダウンロード中..."
  ssh "$host" "sudo cat $CLIENTS_DIR/${name}.ovpn" >"$local_out"

  # サーバーアドレスの置換
  if [[ -n "$server_addr" ]]; then
    sed -i "s/YOUR_SERVER_IP/$server_addr/g" "$local_out"
    echo "サーバーアドレスを $server_addr に設定しました。"
  else
    echo "Warning: OPENVPN_SERVER_ADDR が未設定です。"
    echo "  .ovpn ファイル内の 'remote YOUR_SERVER_IP 1194' を手動で編集してください。"
    echo "  または: OPENVPN_SERVER_ADDR=vpn.example.com ./scripts/setup-openvpn.sh get-ovpn ..."
  fi

  chmod 600 "$local_out"
  echo ""
  echo "ダウンロード完了: $local_out"
}

cmd_list() {
  local host="$1"

  ssh "$host" "sudo bash -s" <<REMOTE
if [ ! -d "$PKI_DIR/issued" ]; then
  echo "PKI が未初期化です。"
  exit 0
fi

echo "発行済み証明書:"
ls -1 "$PKI_DIR/issued/" | sed 's/\.crt$//'
REMOTE
}

cmd_status() {
  local host="$1"

  echo ""
  echo "--- $host ---"
  ssh "$host" "
    echo '--- PKI 状態 ---'
    if sudo test -d $PKI_DIR; then
      echo 'PKI ディレクトリ: 存在'
      echo '発行済み証明書:'
      sudo ls -1 $PKI_DIR/issued/ 2>/dev/null | sed 's/\.crt$/  /' || echo '  (なし)'
    else
      echo 'PKI ディレクトリ: 未作成'
    fi

    echo ''
    echo '--- 証明書ファイル ---'
    for f in ca.pem server.pem server-key.pem dh2048.pem; do
      if sudo test -f $CERT_DIR/\$f; then
        echo \"  \$f: OK\"
      else
        echo \"  \$f: 未配置\"
      fi
    done

    echo ''
    echo '--- OpenVPN サービス ---'
    systemctl is-active openvpn-server.service 2>/dev/null || echo '(サービス未起動)'
    systemctl status openvpn-server.service 2>/dev/null | head -10 || true
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
  add-client)
    [[ $# -ge 2 ]] || {
      echo "Error: SSH ホストとクライアント名を指定してください。" >&2
      echo "Usage: setup-openvpn.sh add-client <ssh-host> <name>" >&2
      exit 1
    }
    cmd_add_client "$1" "$2"
    ;;
  get-ovpn)
    [[ $# -ge 2 ]] || {
      echo "Error: SSH ホストとクライアント名を指定してください。" >&2
      echo "Usage: setup-openvpn.sh get-ovpn <ssh-host> <name>" >&2
      exit 1
    }
    cmd_get_ovpn "$1" "$2"
    ;;
  list)
    [[ $# -ge 1 ]] || {
      echo "Error: SSH ホストを指定してください。" >&2
      exit 1
    }
    cmd_list "$1"
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
