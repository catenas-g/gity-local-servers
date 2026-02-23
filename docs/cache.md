# Nix リモートバイナリキャッシュ

OSS プロジェクト向けのリモートキャッシュ方法まとめ。

## 選択肢一覧

| 方式 | コスト (OSS) | インフラ | 開発者間共有 | ストレージ |
| --- | --- | --- | --- | --- |
| Cachix | 無料 5 GiB | 不要 (SaaS) | 可 | マネージド |
| cache-nix-action | 無料 | 不要 | 不可 (CI のみ) | 10 GiB (GitHub 制限) |
| Magic Nix Cache | 無料 | 不要 | 不可 (CI のみ) | 10 GiB (GitHub 制限) |
| FlakeHub Cache | 有料のみ | 不要 (SaaS) | 可 | マネージド |
| Attic | 無料 (セルフホスト) | サーバー + S3 | 可 | 無制限 |
| Harmonia | 無料 (セルフホスト) | サーバー | 可 | ローカルディスク |
| S3 バケット直接 | ~$0.02/GB/月 | S3 のみ | 可 | 無制限 |

## 1. Cachix (SaaS) — 推奨

最も広く使われている Nix バイナリキャッシュサービス。Cloudflare CDN 付き。

- **無料枠**: 5 GiB (公開キャッシュ、帯域無制限)
- **圧縮**: 最大 90% 削減されるため実質的な容量は大きい
- **公式サイト**: <https://www.cachix.org>

### セットアップ

```bash
# インストール
nix profile install nixpkgs#cachix

# アカウント作成後
cachix authtoken <your-token>
cachix create <your-cache-name>
cachix use <your-cache-name>

# ビルド結果をプッシュ
nix build .#nixosConfigurations.more-jump-more.config.system.build.toplevel
cachix push <your-cache-name> ./result

# または watch-exec で自動プッシュ
cachix watch-exec <your-cache-name> -- nix build ...
```

### GitHub Actions 連携

```yaml
- uses: cachix/install-nix-action@v30
- uses: cachix/cachix-action@v15
  with:
    name: your-cache-name
    authToken: "${{ secrets.CACHIX_AUTH_TOKEN }}"
- run: nix build ...
```

## 2. GitHub Actions キャッシュ

### cache-nix-action (推奨)

GitHub Actions の組み込みキャッシュを利用。最大 55% のビルド時間短縮。

- **リポジトリ**: <https://github.com/nix-community/cache-nix-action>

```yaml
- uses: nixbuild/nix-quick-install-action@v30
- uses: nix-community/cache-nix-action@v6
  with:
    primary-key: nix-${{ runner.os }}-${{ hashFiles('flake.lock') }}
    restore-prefixes-first-match: nix-${{ runner.os }}-
- run: nix build ...
```

### Magic Nix Cache Action

Determinate Systems 製。ゼロ設定だが、GitHub API 変更で壊れた前例があり安定性に懸念。

```yaml
- uses: DeterminateSystems/nix-installer-action@main
- uses: DeterminateSystems/magic-nix-cache-action@main
- run: nix build ...
```

## 3. セルフホスト

### Attic — S3 バックエンド対応の多機能キャッシュ

重複排除・GC・マルチテナント対応。Apache 2.0 ライセンス。

- **リポジトリ**: <https://github.com/zhaofengli/attic>

```bash
nix profile install github:zhaofengli/attic
attic login myserver https://your-attic-instance your-token
attic cache create mycache
attic push mycache ./result
```

NixOS モジュール:

```nix
{
  services.atticd = {
    enable = true;
    settings = {
      listen = "[::]:8080";
      storage = {
        type = "s3";
        region = "us-east-1";
        bucket = "your-nix-cache";
        endpoint = "https://s3.amazonaws.com";
      };
    };
  };
}
```

### Harmonia — 軽量 Rust 製キャッシュサーバー

ローカル Nix store をそのまま HTTP で配信。最もシンプルなセルフホスト選択肢。

- **リポジトリ**: <https://github.com/nix-community/harmonia>

```nix
{
  services.harmonia = {
    enable = true;
    signKeyPath = "/var/lib/harmonia/cache-priv-key.pem";
    settings.bind = "[::]:5000";
  };
}
```

署名鍵の生成:

```bash
nix-store --generate-binary-cache-key cache.example.com cache-priv-key.pem cache-pub-key.pem
```

### S3 バケット直接 (サーバー不要)

Nix は S3 をネイティブサポートしている。サーバー管理不要。

```bash
# 署名鍵の生成
nix-store --generate-binary-cache-key cache.example.com priv-key.pem pub-key.pem

# S3 にプッシュ
nix copy --to "s3://your-bucket?region=us-east-1" ./result
```

利用側の設定:

```nix
{
  nix.settings = {
    substituters = [ "s3://your-bucket?region=us-east-1" ];
    trusted-public-keys = [ "cache.example.com:PUBKEY..." ];
  };
}
```

## このプロジェクトでの推奨構成

**Cachix (無料枠) + cache-nix-action** の組み合わせが OSS の定番。

- **Cachix**: ユーザーが `cachix use` でビルド済みバイナリを取得 (特に aarch64-linux ビルドの高速化に有効)
- **cache-nix-action**: CI の繰り返しビルドを無料で高速化

ビルドサーバー (Raspberry Pi 等) が既にあるなら **Harmonia** を NixOS モジュールで有効にするだけで即座にバイナリキャッシュサーバーになる。

## 参考リンク

- [Cachix ドキュメント](https://docs.cachix.org/getting-started)
- [NixOS Wiki - Binary Cache](https://nixos.wiki/wiki/Binary_Cache)
- [NixOS & Flakes Book - キャッシュホスティング](https://nixos-and-flakes.thiscute.world/nix-store/host-your-own-binary-cache-server)
- [Nix マニュアル - S3 Binary Cache Store](https://nix.dev/manual/nix/2.24/store/types/s3-binary-cache-store)
