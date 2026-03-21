#!/usr/bin/env bash
# GitHub Actions セルフホストランナーのトークン設置スクリプト
# 使い方: ./scripts/setup-github-runner.sh --help
set -euo pipefail

ORG="catenas-g"
TOKEN_PATH="/var/lib/secrets/github-runner-token"

usage() {
  cat <<'EOF'
Usage: setup-github-runner.sh <command> <ssh-host>

Commands:
  deploy-pat      PAT を対話入力して設置（推奨・長期運用向け）
  deploy-token    gh API で registration token を生成して設置（テスト向け・1時間有効）
  status          ランナーの登録状態を確認
  list-runners    Organization のランナー一覧を表示

Examples:
  ./scripts/setup-github-runner.sh deploy-pat gity@192.168.128.200
  ./scripts/setup-github-runner.sh deploy-token gity@more-jump-more
  ./scripts/setup-github-runner.sh status gity@192.168.128.200
  ./scripts/setup-github-runner.sh list-runners

Notes:
  - deploy-pat: Fine-grained PAT 推奨。必要な権限: "Self-hosted runners" Read & Write
    Classic PAT の場合は admin:org スコープが必要
  - deploy-token: Registration token は1時間で期限切れ。テストや初回確認用
  - PAT はランナー再起動時に自動で registration token に交換されるため長期運用に適する
EOF
}

check_gh() {
  if ! command -v gh &>/dev/null; then
    echo "Error: gh コマンドが見つかりません。GitHub CLI をインストールしてください。" >&2
    exit 1
  fi
  if ! gh auth status &>/dev/null 2>&1; then
    echo "Error: gh が未認証です。'gh auth login' を実行してください。" >&2
    exit 1
  fi
}

check_org() {
  local org_name
  org_name=$(gh api "orgs/$ORG" --jq '.login' 2>/dev/null) || {
    echo "Error: Organization '$ORG' にアクセスできません。" >&2
    exit 1
  }
  echo "Organization: $org_name"
}

deploy_token_to_host() {
  local host="$1"
  local token="$2"

  echo "トークンを $host:$TOKEN_PATH に設置中..."
  printf '%s' "$token" |
    ssh "$host" 'sudo mkdir -p /var/lib/secrets && sudo tee '"$TOKEN_PATH"' >/dev/null && sudo chmod 600 '"$TOKEN_PATH"
  echo "設置完了!"
}

cmd_deploy_pat() {
  local host="$1"
  check_gh
  check_org

  echo ""
  echo "GitHub PAT を入力してください。"
  echo "  Fine-grained PAT 作成: https://github.com/settings/personal-access-tokens/new"
  echo "    → Resource owner: $ORG"
  echo "    → Organization permissions: Self-hosted runners (Read and Write)"
  echo ""
  echo "  Classic PAT 作成: https://github.com/settings/tokens/new?scopes=admin:org"
  echo ""
  read -rsp "PAT: " token
  echo ""

  if [[ -z "$token" ]]; then
    echo "Error: 入力が空です。" >&2
    exit 1
  fi

  # PAT の形式チェック
  if [[ "$token" =~ ^ghp_ ]] || [[ "$token" =~ ^github_pat_ ]]; then
    echo "PAT の形式を確認: OK"
  else
    echo "Warning: PAT の標準的なプレフィックス (ghp_, github_pat_) が検出されませんでした。"
    read -rp "続行しますか? [y/N]: " confirm
    [[ "$confirm" =~ ^[yY]$ ]] || exit 1
  fi

  # PAT で Organization へアクセス可能か検証
  echo "PAT の権限を検証中..."
  if gh api -H "Authorization: token $token" "orgs/$ORG" --jq '.login' &>/dev/null 2>&1; then
    echo "Organization アクセス: OK"
  else
    echo "Warning: この PAT で Organization '$ORG' にアクセスできない可能性があります。"
    echo "         スコープが不足しているか、Organization の SSO 認証が必要かもしれません。"
    read -rp "続行しますか? [y/N]: " confirm
    [[ "$confirm" =~ ^[yY]$ ]] || exit 1
  fi

  deploy_token_to_host "$host" "$token"
  echo ""
  echo "次のステップ: NixOS をリビルドしてランナーサービスを起動してください。"
  echo "  sudo nixos-rebuild switch --flake github:your-org/your-repo"
}

cmd_deploy_token() {
  local host="$1"
  check_gh
  check_org

  echo ""
  echo "Registration token を生成中..."
  local response
  response=$(gh api -X POST "orgs/$ORG/actions/runners/registration-token")
  local token expires_at
  token=$(echo "$response" | jq -r '.token')
  expires_at=$(echo "$response" | jq -r '.expires_at')

  echo "生成完了 (期限: $expires_at)"
  echo ""
  echo "⚠ Registration token は1時間で期限切れになります。"
  echo "  ランナーサービスの初回起動はこの期限内に行ってください。"
  echo "  長期運用には 'deploy-pat' を使用してください。"
  echo ""

  deploy_token_to_host "$host" "$token"
}

cmd_status() {
  local host="$1"
  check_gh
  check_org

  echo ""
  echo "--- リモートのトークンファイル ---"
  ssh "$host" "
    if [ -f $TOKEN_PATH ]; then
      echo 'ファイル: 存在'
      ls -la $TOKEN_PATH
      echo \"形式: \$(head -c 10 $TOKEN_PATH 2>/dev/null | sudo cat)...\"
    else
      echo 'ファイル: 未設置'
    fi
  " 2>/dev/null || echo "(SSH 接続失敗)"

  echo ""
  echo "--- ランナーサービス状態 ---"
  ssh "$host" "
    systemctl is-active github-runner-default.service 2>/dev/null || echo '(サービス未起動)'
    systemctl status github-runner-default.service 2>/dev/null | head -15 || true
  " 2>/dev/null || echo "(SSH 接続失敗)"

  echo ""
  echo "--- GitHub 上のランナー登録状況 ---"
  gh api "orgs/$ORG/actions/runners" --jq '
    if (.total_count // 0) == 0 then
      "(ランナー未登録)"
    else
      .runners[] | [.name, .status, (.labels | map(.name) | join(", "))] | @tsv
    end
  ' 2>/dev/null || echo "(API アクセス失敗)"
}

cmd_list_runners() {
  check_gh
  check_org

  echo ""
  echo "--- $ORG のセルフホストランナー一覧 ---"
  gh api "orgs/$ORG/actions/runners" --jq '
    if (.total_count // 0) == 0 then
      "(ランナー未登録)"
    else
      .runners[] | "\(.name)\t\(.status)\t\(.os)/\(.labels | map(select(.type == "custom")) | map(.name) | join(", "))"
    end
  ' 2>/dev/null || echo "(API アクセス失敗)"
}

# --- Main ---
if [[ $# -lt 1 ]]; then
  usage
  exit 1
fi

CMD="${1:-}"
shift

case "$CMD" in
  deploy-pat)
    [[ $# -ge 1 ]] || { echo "Error: SSH ホストを指定してください。" >&2; exit 1; }
    cmd_deploy_pat "$1"
    ;;
  deploy-token)
    [[ $# -ge 1 ]] || { echo "Error: SSH ホストを指定してください。" >&2; exit 1; }
    cmd_deploy_token "$1"
    ;;
  status)
    [[ $# -ge 1 ]] || { echo "Error: SSH ホストを指定してください。" >&2; exit 1; }
    cmd_status "$1"
    ;;
  list-runners)
    cmd_list_runners
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
