# NextCloud SAML SSO (Keycloak) 調査レポート

## 概要

- **日付**: 2026-02-23
- **対象サーバー**: monooki (192.168.128.199, NixOS x86_64)
- **NextCloud**: 31.0.14
- **IdP**: Keycloak (https://sso.gity.co.jp)
- **Keycloakレルム**: `gity`
- **SAMLクライアントID**: `monooki`
- **SAMLアプリ**: `user_saml` (NextCloud store-apps)

## 現在の状態

Keycloakでの認証は成功するが、NextCloudへのリダイレクト後にセッションが保持されず、ログイン画面に戻るループが発生する。

**根本原因**: ブラウザのSameSite Cookieポリシーにより、クロスサイトPOST (`https://sso.gity.co.jp` -> `http://192.168.128.199`) でCookieがブロックされている。

## 調査経緯

### 1. IdP証明書未設定

**エラー**: `idp_cert_or_fingerprint_not_found_and_required`

**原因**: `idp-x509cert` が設定されていなかった。

**対応**:

```bash
sudo nextcloud-occ saml:config:set 1 --idp-x509cert '<証明書>'
```

### 2. IdP URLの誤り

**エラー**: Keycloakで404

**原因**: 2つの問題があった。

- レルム名の誤り: `monooki` -> 正しくは `gity`
- URLパスの誤り: Keycloak 17+では `/auth/realms/` ではなく `/realms/`

**対応**:

```bash
sudo nextcloud-occ saml:config:set 1 \
  --idp-entityId 'https://sso.gity.co.jp/realms/gity' \
  --idp-singleSignOnService.url 'https://sso.gity.co.jp/realms/gity/protocol/saml'
```

### 3. SP Entity IDの不一致

**エラー**: Keycloakで「無効なリクエスト」

**原因**: NextCloudがデフォルトで `http://192.168.128.199/apps/user_saml/saml/metadata` をIssuerとして送信するが、KeycloakのClient IDは `monooki`。

**対応**:

```bash
sudo nextcloud-occ saml:config:set 1 --sp-entityId 'monooki'
```

### 4. クライアントプロトコルの誤り

**エラー**: Keycloakで「Wrong client protocol」

**原因**: Keycloakのクライアント `monooki` がOpenID Connectプロトコルで作成されていた。

**対応**: Keycloakでクライアントを削除し、SAMLプロトコルで再作成した。

### 5. 署名付きリクエストの要求

**エラー**: Keycloakで「無効な要求元」

**原因**: Keycloakの `WantAuthnRequestsSigned="true"` が有効で、NextCloudは署名なしのSAMLリクエストを送信していた。

**確認方法**:

```bash
curl -s "https://sso.gity.co.jp/realms/gity/protocol/saml/descriptor" \
  | grep WantAuthnRequestsSigned
```

**対応**: Keycloak管理画面 -> Clients -> `monooki` -> Keys -> 「Client Signature Required」をOFFに変更。

### 6. SameSite Cookieブロック (未解決)

**エラー**: NextCloudログに `"Cookie was not present"`

**原因**: Keycloak (HTTPS) からNextCloud (HTTP) へのクロスサイトPOSTで、ブラウザのSameSite Cookieポリシーにより `user_saml` のCookieがブロックされている。

**リクエストフロー** (nginxアクセスログより):

```
POST /apps/user_saml/saml/acs  -> 303  # ACS受信、Cookieなしでセッション作成失敗
GET  /                          -> 302  # 未認証のためリダイレクト
GET  /login                     -> 302  # SAMLログイン画面へ
GET  /selectUserBackEnd          -> 200  # SSO選択画面 (ループ)
```

## 現在のSAML設定

```bash
sudo nextcloud-occ saml:config:get
```

```
- 1:
    - general-uid_mapping: username
    - idp-entityId: https://sso.gity.co.jp/realms/gity
    - idp-singleSignOnService.url: https://sso.gity.co.jp/realms/gity/protocol/saml
    - saml-attribute-mapping-displayName_mapping: username
    - saml-attribute-mapping-email_mapping: email
    - sp-x509cert: <testrealm時代の証明書 - 要確認>
    - idp-x509cert: <monookiクライアントの証明書>
    - sp-entityId: monooki
```

## Keycloakクライアント設定 (monooki)

| 設定                           | 値                                                       |
| ------------------------------ | -------------------------------------------------------- |
| Client ID                      | monooki                                                  |
| Client Protocol                | SAML                                                     |
| Root URL                       | http://192.168.128.199                                   |
| Home URL                       | http://192.168.128.199                                   |
| Valid Redirect URIs             | http://192.168.128.199/\*                                |
| Master SAML Processing URL     | http://192.168.128.199/apps/user_saml/saml/acs           |
| Name ID Format                 | username                                                 |
| Force POST Binding             | ON (OFFにすべき - 後述)                                  |
| Client Signature Required      | OFF                                                      |
| Document Signing               | ON                                                       |
| Assertion Signing              | OFF                                                      |
| Signature Algorithm            | RSA_SHA256                                               |
| SAML Signature Key Name        | NONE                                                     |

## 解決策の選択肢

### 方法A: NextCloudをHTTPS化 (推奨)

自己署名証明書でnginxにTLSを追加する。

**メリット**:

- SameSite Cookie問題を根本解決
- セキュリティ向上

**デメリット**:

- ブラウザで自己署名証明書の警告を承認する必要がある
- Keycloak側のURL設定もhttps://に更新が必要

**Nix設定変更の要点**:

- `services.nextcloud.https = true`
- `services.nextcloud.hostName = "192.168.128.199"`
- `services.nextcloud.settings.overwriteprotocol = "https"`
- `services.nginx.virtualHosts."192.168.128.199".forceSSL = true` + 自己署名証明書
- ファイアウォールにポート443追加

**Keycloak側の更新**:

- Valid Redirect URIs: `https://192.168.128.199/*`
- Master SAML Processing URL: `https://192.168.128.199/apps/user_saml/saml/acs`

### 方法B: 正式なドメイン + Let's Encrypt

NextCloudに正式なドメイン名を割り当て、Let's Encryptで証明書を取得する。

**メリット**:

- ブラウザ警告なし
- 本番運用に適した構成

**デメリット**:

- DNS設定が必要
- ローカルネットワークからLet's Encryptの検証が必要 (DNS-01チャレンジ等)

### 方法C: Keycloak側でHTTP許可 (非推奨)

Keycloakのレスポンスをhttp://にリダイレクトするよう設定する。

**問題**: 現代のブラウザはSameSite=LaxがデフォルトでクロスサイトPOSTのCookieをブロックするため、HTTP同士でも異なるドメイン間では同じ問題が発生する可能性がある。

## 補足情報

### SAMLリクエストのデコード方法

```bash
python3 -c "
import base64, zlib, urllib.parse
saml_req = '<URL-encoded SAMLRequest>'
decoded = urllib.parse.unquote(saml_req)
raw = base64.b64decode(decoded)
xml = zlib.decompress(raw, -15)
print(xml.decode('utf-8'))
"
```

### SAMLディスクリプタの確認

```bash
curl -s "https://sso.gity.co.jp/realms/gity/protocol/saml/descriptor"
```

### NextCloudログの確認

NixOSではデフォルトで `log_type = syslog` だが、`config.php` は rebuild で上書きされるため、Nix設定で `loglevel` と `log_type` を指定する必要がある。

```nix
services.nextcloud.settings = {
  loglevel = 0; # DEBUG
  log_type = "file";
};
```

```bash
# ログ確認
sudo cat /var/lib/nextcloud/data/nextcloud.log

# syslog経由の場合
sudo journalctl --since '5 min ago' | grep Nextcloud
```

### occ コマンド

NixOSでは `nextcloud-occ` ラッパーを使用する。

```bash
sudo nextcloud-occ saml:config:get
sudo nextcloud-occ saml:config:set 1 --<key> '<value>'
```
