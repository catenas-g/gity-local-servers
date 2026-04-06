# Gity Local Servers

Nix Flakes による NixOS / Home Manager 構成リポジトリ。
ローカルネットワーク上の複数マシンを宣言的に管理します。

クラウドインフラについては [catenas-public-service-terraform](https://github.com/catenas-g/catenas-public-service-terraform) を参照してください。

## アーキテクチャ

```
Internet
    │
    ▼
Router (ポートフォワーディング)
    │
    ▼
more-jump-more (Raspberry Pi 4 / 192.168.128.200)
  ├─ Headscale :8080  … VPN コーディネーションサーバー
  ├─ Caddy L7          … HTTPS リバースプロキシ (自動 TLS)
  ├─ Caddy L4          … TCP/UDP プロキシ (SSH, PostgreSQL 等)
  ├─ Cloudflare DDNS   … 動的 DNS 更新
  ├─ OpenVPN           … VPN サーバー
  └─ GitHub Runner     … CI/CD

monooki (x86_64 / 192.168.128.199)
  ├─ NextCloud 31      … ファイルサーバー
  ├─ TOMORU            … 店舗管理アプリ (API + Web + Admin + Kiosk + Keycloak)
  ├─ Attic             … Nix バイナリキャッシュ
  └─ GitHub Runner ×4  … CI/CD (並列実行)

errand-ensemble-1 (Raspberry Pi 4 / 192.168.128.198)
  └─ GitHub Runner     … CI/CD

errand-ensemble-2 (Raspberry Pi 4 / 192.168.128.197)
  └─ GitHub Runner     … CI/CD
```

## リポジトリ構成

```
.
├── flake.nix                     # エントリポイント
├── flake.lock
├── shell.nix                     # 開発シェル (nil, git, qemu-user)
├── treefmt.nix                   # フォーマッタ設定 (nixfmt)
├── overlays/                     # nixpkgs-unstable オーバーレイ
├── modules/
│   ├── common/
│   │   ├── base.nix              # 共通 NixOS 設定 (ユーザー, TZ, Nix 設定)
│   │   └── nixpkgs.nix           # 共通 nixpkgs 設定
│   ├── nixos/
│   │   ├── headscale/            # Headscale VPN コーディネーター
│   │   ├── caddy-l4/             # Caddy + L4 プラグイン
│   │   ├── tailscale/            # Tailscale クライアント
│   │   ├── cloudflare-ddns/      # Cloudflare DDNS 更新
│   │   ├── ssh-server/           # 強化済み OpenSSH
│   │   ├── github-runner/        # GitHub Actions ランナー (並列対応)
│   │   ├── attic/                # Nix バイナリキャッシュサーバー
│   │   ├── attic-watch/          # ストア自動プッシュ
│   │   └── openvpn/              # OpenVPN サーバー
│   └── home-manager/
│       └── pkgs/                 # ユーザーパッケージ
├── nixos/
│   ├── more-jump-more/           # Raspberry Pi 4 ジャンプサーバー (aarch64)
│   ├── monooki/                  # NextCloud + キャッシュサーバー (x86_64)
│   ├── errand-ensemble-1/        # CI ランナー (aarch64)
│   └── errand-ensemble-2/        # CI ランナー (aarch64)
├── home-manager/
│   └── gity/                     # Home Manager ユーザー構成
├── docker/
│   └── github-runner/            # Docker Compose ランナー (非 NixOS 向け)
├── scripts/
│   ├── setup-github-runner.sh    # ランナートークンデプロイ
│   ├── setup-attic-watch.sh      # Attic トークンデプロイ
│   ├── setup-openvpn.sh          # OpenVPN PKI・クライアント管理
│   └── setup-tomoru.sh           # TOMORU シークレット設置・管理
└── docs/                         # ガイド・トラブルシューティング
```

## 構成一覧

| 名前 | 種別 | アーキテクチャ | 用途 |
|------|------|----------------|------|
| `more-jump-more` | NixOS | aarch64-linux | Raspberry Pi 4 ジャンプサーバー |
| `monooki` | NixOS | x86_64-linux | NextCloud + バイナリキャッシュ |
| `errand-ensemble-1` | NixOS | aarch64-linux | CI ランナーノード |
| `errand-ensemble-2` | NixOS | aarch64-linux | CI ランナーノード |
| `gity` | Home Manager | x86_64-linux | ユーザー環境管理 |

## モジュール

| モジュール | 説明 |
|------------|------|
| **headscale** | Tailscale 互換 VPN コーディネーションサーバー。ACL でアクセス制御 |
| **caddy-l4** | L4 (TCP/UDP) + L7 (HTTP/HTTPS) リバースプロキシ。自動 TLS 対応 |
| **tailscale** | Headscale メッシュに接続する VPN クライアント。カーネルモード有効 |
| **cloudflare-ddns** | 5 分間隔で Cloudflare DNS レコードを自動更新 |
| **ssh-server** | パスワード認証無効・root ログイン禁止の強化済み OpenSSH |
| **github-runner** | GitHub Actions セルフホストランナー。`count` オプションで並列数を設定可能 |
| **attic** | Nix バイナリキャッシュサーバー (JWT RS256 認証、Zstd 圧縮) |
| **attic-watch** | Nix ストア監視 + Attic への自動プッシュ |
| **openvpn** | OpenVPN サーバー (UDP 1194、10.8.0.0/24) |

## Docker 構成 (非 NixOS マシン向け)

Nix が導入されていないマシンで GitHub Actions ランナーを動かす場合:

```bash
cd docker/github-runner
cp .env.example .env
# .env に ACCESS_TOKEN (GitHub PAT) を設定
docker compose up -d
```

`myoung34/github-runner` イメージを使用し、4 レプリカ × Ephemeral モードで動作します。

## セットアップ

### 前提条件

- [Nix](https://nixos.org/) (flakes 有効)
- Raspberry Pi 4 (aarch64-linux) — ジャンプサーバー・CI ノード用
- x86_64 マシン — NextCloud・キャッシュサーバー用

### SD カードイメージのビルド

```bash
nix build .#more-jump-more-sdImage
nix build .#errand-ensemble-1-sdImage
nix build .#errand-ensemble-2-sdImage
```

### Home Manager の適用

```bash
home-manager switch --flake .#gity
```

### 開発シェル

```bash
nix-shell  # nil (Nix LSP) + git + qemu-user が利用可能
```

## 検証

`.nix` ファイルを変更したら必ず以下を実行してください:

```bash
# フォーマット
treefmt

# 検証
nix flake check --extra-experimental-features 'nix-command flakes'
```

## ライセンス

Private
