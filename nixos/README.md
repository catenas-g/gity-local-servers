# NixOS ホスト構成

このディレクトリには各 NixOS マシンのホスト固有設定が含まれています。

## ホスト一覧

| ホスト名 | アーキテクチャ | IP | 用途 |
|----------|----------------|----|------|
| `more-jump-more` | aarch64-linux | 192.168.128.200 | Raspberry Pi 4 ジャンプサーバー |
| `monooki` | x86_64-linux | 192.168.128.199 | NextCloud + TOMORU + バイナリキャッシュ |
| `errand-ensemble-1` | aarch64-linux | 192.168.128.198 | CI ランナー |
| `errand-ensemble-2` | aarch64-linux | 192.168.128.197 | CI ランナー |

## デプロイ手順

### 1. ビルドと適用

対象マシン上で実行:

```bash
sudo nixos-rebuild switch --flake .#<ホスト名>
```

例:

```bash
# monooki にデプロイ
sudo nixos-rebuild switch --flake .#monooki

# more-jump-more にデプロイ
sudo nixos-rebuild switch --flake .#more-jump-more
```

### 2. SD カードイメージのビルド (Raspberry Pi)

Raspberry Pi の初回セットアップ用:

```bash
nix build .#more-jump-more-sdImage
nix build .#errand-ensemble-1-sdImage
nix build .#errand-ensemble-2-sdImage
```

生成されたイメージを SD カードに書き込んで起動します。

### 3. 変更後の検証

`.nix` ファイルを変更したら必ず以下を実行:

```bash
treefmt
nix flake check --extra-experimental-features 'nix-command flakes'
```

## シークレット管理

シークレットは **git で管理しません**。各マシンの `/var/lib/secrets/` に直接配置します。

設置方法は2つあります:

1. **スクリプトで設置** (推奨): `scripts/setup-tomoru.sh` で SSH 経由で配置
2. **自動生成**: 初回デプロイ時に activation script がランダム生成

### セットアップスクリプト

`scripts/setup-tomoru.sh` を使うと、シークレットの生成・設置・状態確認をリモートから行えます。

```bash
# 初回: 全シークレットを一括生成・設置
./scripts/setup-tomoru.sh init gity@192.168.128.199

# 個別シークレットの設置 (対話入力)
./scripts/setup-tomoru.sh deploy-secret gity@192.168.128.199 keycloak-admin
./scripts/setup-tomoru.sh deploy-secret gity@192.168.128.199 keycloak-db
./scripts/setup-tomoru.sh deploy-secret gity@192.168.128.199 session-key
./scripts/setup-tomoru.sh deploy-secret gity@192.168.128.199 oidc-secret

# シークレットとサービスの状態確認
./scripts/setup-tomoru.sh status gity@192.168.128.199
```

詳細は `./scripts/setup-tomoru.sh --help` を参照してください。

### monooki のシークレット

| ファイル | 形式 | 内容 |
|----------|------|------|
| `tomoru-keycloak-admin.env` | systemd EnvironmentFile | Keycloak 管理者認証情報 |
| `tomoru-keycloak-db-pass` | プレーンテキスト | Keycloak DB パスワード |
| `tomoru-api.env` | systemd EnvironmentFile | TOMORU API シークレット |
| `nextcloud-admin-pass` | プレーンテキスト | NextCloud 管理者パスワード |

#### tomoru-keycloak-admin.env

Keycloak 管理コンソールの認証情報。`keycloak.service` の `EnvironmentFile` として読み込まれます。

```env
KC_BOOTSTRAP_ADMIN_USERNAME=admin
KC_BOOTSTRAP_ADMIN_PASSWORD=<ランダム生成 or 任意のパスワード>
```

#### tomoru-keycloak-db-pass

Keycloak が使用する PostgreSQL データベースのパスワード。

```
<ランダム生成 or 任意のパスワード>
```

#### tomoru-api.env

TOMORU API サーバーのシークレット。`SESSION_ENCRYPTION_KEY` は activation script で自動生成されます。
`OIDC_CLIENT_SECRET` は手動で設定してください（Keycloak 管理コンソールまたは realm JSON から取得）。

```env
SESSION_ENCRYPTION_KEY=<64文字の hex 文字列>
OIDC_CLIENT_SECRET=<Keycloak admin console から取得>
```

#### nextcloud-admin-pass

NextCloud 管理者の初期パスワード。

```
<ランダム生成 or 任意のパスワード>
```

### シークレットの手動配置

自動生成に頼らず事前にシークレットを配置する場合:

```bash
sudo mkdir -p /var/lib/secrets

# Keycloak 管理者
printf 'KC_BOOTSTRAP_ADMIN_USERNAME=admin\nKC_BOOTSTRAP_ADMIN_PASSWORD=自分のパスワード\n' \
  | sudo tee /var/lib/secrets/tomoru-keycloak-admin.env > /dev/null

# Keycloak DB
echo '自分のパスワード' | sudo tee /var/lib/secrets/tomoru-keycloak-db-pass > /dev/null

# TOMORU API (SESSION_ENCRYPTION_KEY + OIDC_CLIENT_SECRET)
printf 'SESSION_ENCRYPTION_KEY=%s\nOIDC_CLIENT_SECRET=your-secret-here\n' "$(openssl rand -hex 32)" \
  | sudo tee /var/lib/secrets/tomoru-api.env > /dev/null

# NextCloud
echo '自分のパスワード' | sudo tee /var/lib/secrets/nextcloud-admin-pass > /dev/null

# パーミッション設定
sudo chmod 600 /var/lib/secrets/*
```

### シークレットの共有

チームメンバー間でシークレットを共有する場合は、以下の方法を推奨します:

- **直接転送**: `scp` や `rsync` でターゲットマシンにコピー
- **パスワードマネージャー**: 1Password / Bitwarden 等の共有ボールトに保管
- **暗号化**: `age` や `gpg` で暗号化してから安全なチャンネルで送付

```bash
# 例: scp でリモートマシンに配置
scp secrets/tomoru-keycloak-admin.env gity@192.168.128.199:/tmp/
ssh gity@192.168.128.199 'sudo mv /tmp/tomoru-keycloak-admin.env /var/lib/secrets/ && sudo chmod 600 /var/lib/secrets/tomoru-keycloak-admin.env'
```

### パスワードの変更

#### Keycloak 管理者パスワード

```bash
# 1. ファイルを編集
sudo vi /var/lib/secrets/tomoru-keycloak-admin.env

# 2. Keycloak を再起動
sudo systemctl restart keycloak
```

> **注意**: `KC_BOOTSTRAP_ADMIN_PASSWORD` は Keycloak の初回起動時に管理者アカウントを作成するためのものです。
> 一度作成された後は Keycloak 管理コンソール (`http://192.168.128.199:8180/admin/`) からパスワードを変更してください。

#### OIDC Client Secret の更新

```bash
# 1. Keycloak 管理コンソールから新しい secret を取得
# 2. tomoru-api.env を更新
./scripts/setup-tomoru.sh deploy-secret gity@192.168.128.199 oidc-secret

# 3. API を再起動
ssh gity@192.168.128.199 sudo systemctl restart tomoru-api
```

## TOMORU サービス起動順序

```
activation script (シークレット自動生成)
    │
    ▼
postgresql.service
    │
    ├──────────────────────────────┐
    ▼                              ▼
tomoru-migrate.service        keycloak.service
    │                              │
    ▼                              │
tomoru-api.service                 │
    │                              │
    ├──────────┬──────────┐        │
    ▼          ▼          ▼        ▼
tomoru-web  tomoru-admin  tomoru-kiosk
(:3000)     (:3001)       (:3002)
```

> **注意**: Keycloak は TOMORU モジュールとは独立して管理されています。
> OIDC client secret は手動で tomoru-api.env に設定してください。

## トラブルシューティング

### サービスの状態確認

```bash
# 全 TOMORU サービスの状態
systemctl status tomoru-{api,web,admin,kiosk,migrate} keycloak

# 特定サービスのログ
journalctl -u tomoru-api -n 50 --no-pager
journalctl -u keycloak -n 50 --no-pager
```

### よくある問題

#### tomoru-api が起動しない

1. **シークレットファイルの確認**:
   ```bash
   ls -la /var/lib/secrets/tomoru-*
   cat /var/lib/secrets/tomoru-api.env
   ```

2. **OIDC_CLIENT_SECRET が設定されているか**:
   ```bash
   grep OIDC_CLIENT_SECRET /var/lib/secrets/tomoru-api.env
   ```
   設定されていなければ Keycloak 管理コンソールから取得して設定。

3. **Keycloak が起動しているか**:
   ```bash
   curl -sf http://192.168.128.199:8180/health/ready
   ```

#### Keycloak にログインできない

- 初回デプロイ: `/var/lib/secrets/tomoru-keycloak-admin.env` の `KC_BOOTSTRAP_ADMIN_PASSWORD` を確認
- パスワード変更済み: Keycloak 管理コンソールで設定したパスワードを使用
