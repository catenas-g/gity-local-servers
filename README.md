# Gity Local Servers

Nix Flakes による NixOS / Home Manager 構成リポジトリ。
Raspberry Pi 4 をジャンプサーバーとして、Tailscale VPN + Caddy L4/L7 リバースプロキシで内部サービスを安全に公開します。

## アーキテクチャ

```
Internet
    │
    ▼
Router (ポートフォワーディング)
    │
    ▼
Raspberry Pi 4 (192.168.1.10 / 100.64.0.1)
  ├─ Headscale :8080  … VPN コーディネーションサーバー
  ├─ Caddy L7          … HTTPS リバースプロキシ (自動 TLS)
  └─ Caddy L4          … TCP/UDP プロキシ (SSH, PostgreSQL, ゲームサーバー等)
       │ WireGuard トンネル
       ▼
  Tailnet (100.64.0.0/10)
    ├─ Machine A (100.64.0.2) — Web + SSH
    ├─ Machine B (100.64.0.3) — API + PostgreSQL
    └─ Machine C (100.64.0.4) — Game Server (UDP)
```

## リポジトリ構成

```
.
├── flake.nix                     # エントリポイント
├── flake.lock
├── shell.nix                     # 開発シェル (nil, git)
├── overlays/                     # nixpkgs-unstable オーバーレイ
├── modules/
│   ├── common/nixpkgs.nix        # 共通 nixpkgs 設定
│   ├── nixos/
│   │   ├── headscale/            # Headscale VPN コーディネーター
│   │   ├── caddy-l4/             # Caddy + L4 プラグイン
│   │   ├── tailscale/            # Tailscale クライアント
│   │   ├── cloudflare-ddns/      # Cloudflare DDNS 更新
│   │   └── ssh-server/           # 強化済み OpenSSH
│   └── home-manager/
├── nixos/
│   └── more-jump-more/           # NixOS 構成 (Raspberry Pi 4 / aarch64)
└── home-manager/
    └── panoption-chan/            # Home Manager 構成 (x86_64)
```

## 構成一覧

| 名前 | 種別 | アーキテクチャ | 用途 |
|------|------|----------------|------|
| `more-jump-more` | NixOS | aarch64-linux | Raspberry Pi 4 ジャンプサーバー |
| `panoption-chan` | Home Manager | x86_64-linux | ユーザー環境管理 |

## モジュール

| モジュール | 説明 |
|------------|------|
| **headscale** | Tailscale 互換 VPN コーディネーションサーバー。ACL でバックエンドへのアクセスを Pi のみに制限 |
| **caddy-l4** | L4 (TCP/UDP) + L7 (HTTP/HTTPS) リバースプロキシ。自動 TLS 対応 |
| **tailscale** | Headscale メッシュに接続する VPN クライアント。カーネルモード有効 |
| **cloudflare-ddns** | 5 分間隔で Cloudflare DNS レコードを自動更新。`proxied = false` で L4 サービスに対応 |
| **ssh-server** | パスワード認証無効・root ログイン禁止の強化済み OpenSSH |

## セットアップ

### 前提条件

- [Nix](https://nixos.org/) (flakes 有効)
- Raspberry Pi 4 (aarch64-linux) — NixOS 構成用
- Cloudflare API トークン — DDNS 用

### SD カードイメージのビルド

```bash
nix build .#nixosConfigurations.more-jump-more.config.system.build.sdImage
```

### Home Manager の適用

```bash
home-manager switch --flake .#panoption-chan
```

### 開発シェル

```bash
nix-shell  # nil (Nix LSP) + git が利用可能
```

## 検証

`.nix` ファイルを変更したら必ず以下を実行してください:

```bash
# フォーマット
nix fmt

# 検証
nix flake check --extra-experimental-features 'nix-command flakes'
```

## TODO

デプロイ前に以下のプレースホルダーを実際の値に置き換えてください:

- [ ] ドメイン名 (`hs.example.com`, `app.example.com`, `api.example.com`)
- [ ] バックエンド Tailnet IP (`100.64.0.2`, `100.64.0.3`, `100.64.0.4`)
- [ ] LAN 設定 (IP アドレス、ゲートウェイ)
- [ ] SSH 公開鍵 (`users.users.gity.openssh.authorizedKeys.keys`)
- [ ] Cloudflare API トークン (`/var/lib/secrets/cloudflare-api-token`)
- [ ] Caddy L4 プラグインのハッシュ値 (初回ビルドで Nix が正しい値を報告)

## ライセンス

Private
