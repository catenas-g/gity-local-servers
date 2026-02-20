# Headscale + Caddy (L4) on Raspberry Pi: 任意プロトコルの安全な外部公開

## 概要

ローカルネットワーク (LAN) 内の Raspberry Pi に Headscale（Tailscale互換の自前コーディネーションサーバー）と Caddy（L4プラグイン付き）を配置し、同一LAN上の他マシンで動作するサービスを、プロトコルを問わずインターネットに安全に公開する構成である。

Caddy の L4 (Layer 4) プラグインにより、HTTP/HTTPS だけでなく SSH, データベース, ゲームサーバー等の任意の TCP/UDP トラフィックを tailnet 経由でバックエンドに転送できる。

## アーキテクチャ図

```
                         インターネット
                              │
                              ▼
              ┌───────────────────────────────┐
              │  ルーター                      │
              │  ポートフォワード:             │
              │    80   → Pi:80   (HTTP)      │
              │    443  → Pi:443  (HTTPS)     │
              │    2222 → Pi:2222 (SSH)       │
              │    5432 → Pi:5432 (PostgreSQL)│
              │    8080 → Pi:8080 (Headscale) │
              └───────────┬───────────────────┘
                          │
  ┌───────────────────────▼─────────────────────── LAN (192.168.x.0/24) ──┐
  │                                                                        │
  │  ┌─ Raspberry Pi (192.168.x.10) ────────────────────────────────┐     │
  │  │                                                               │     │
  │  │  [Headscale] :8080                                           │     │
  │  │    コーディネーションサーバー                                  │     │
  │  │    ノード登録 / 認証 / WireGuard鍵交換 / ACLポリシー適用      │     │
  │  │                                                               │     │
  │  │  [Caddy + L4 プラグイン]                                     │     │
  │  │  ┌─────────────────────────────────────────────────────┐     │     │
  │  │  │                                                     │     │     │
  │  │  │  Layer 7 (HTTP/HTTPS)                               │     │     │
  │  │  │  ├─ :80/:443  app.example.com → 100.64.0.2:8080    │     │     │
  │  │  │  └─ :80/:443  api.example.com → 100.64.0.3:3000    │     │     │
  │  │  │       TLS自動取得 (Let's Encrypt)                   │     │     │
  │  │  │                                                     │     │     │
  │  │  │  Layer 4 (TCP/UDP)                                  │     │     │
  │  │  │  ├─ :2222  TCP → 100.64.0.2:22    (SSH)            │     │     │
  │  │  │  ├─ :5432  TCP → 100.64.0.3:5432  (PostgreSQL)     │     │     │
  │  │  │  └─ :27015 UDP → 100.64.0.4:27015 (ゲームサーバー) │     │     │
  │  │  │                                                     │     │     │
  │  │  └─────────────────────────────────────────────────────┘     │     │
  │  │                                                               │     │
  │  │  [Tailscaleクライアント] tailnet: 100.64.0.1                 │     │
  │  │    Pi自身をtailnetに参加させ、WireGuardトンネルを確立         │     │
  │  └───────────────────┬───────────────────────────────────────────┘     │
  │                      │                                                 │
  │                      │ WireGuard 暗号化トンネル (100.64.0.x)          │
  │          ┌───────────┼──────────────┐                                  │
  │          ▼           ▼              ▼                                   │
  │  ┌──────────────┐ ┌──────────────┐ ┌──────────────┐                   │
  │  │ マシンA       │ │ マシンB       │ │ マシンC       │                   │
  │  │ 192.168.x.20 │ │ 192.168.x.30 │ │ 192.168.x.40 │                   │
  │  │ 100.64.0.2   │ │ 100.64.0.3   │ │ 100.64.0.4   │                   │
  │  │              │ │              │ │              │                   │
  │  │ :8080 Web    │ │ :3000 API    │ │ :27015 Game  │                   │
  │  │ :22   SSH    │ │ :5432 PgSQL  │ │  (UDP)       │                   │
  │  │              │ │              │ │              │                   │
  │  │ [TS Client]  │ │ [TS Client]  │ │ [TS Client]  │                   │
  │  └──────────────┘ └──────────────┘ └──────────────┘                   │
  └────────────────────────────────────────────────────────────────────────┘
```

## 通信経路

```
外部ユーザー
  │
  ├─ HTTPS (app.example.com:443)
  │    → Caddy L7 → TLS終端 → WireGuard → 100.64.0.2:8080
  │
  ├─ SSH (example.com:2222)
  │    → Caddy L4 → TCPそのまま → WireGuard → 100.64.0.2:22
  │
  ├─ PostgreSQL (example.com:5432)
  │    → Caddy L4 → TCPそのまま → WireGuard → 100.64.0.3:5432
  │
  └─ ゲーム (example.com:27015)
       → Caddy L4 → UDPそのまま → WireGuard → 100.64.0.4:27015
```

- Layer 7 (HTTP/HTTPS): Caddy がTLS終端し、平文HTTPをtailnet経由で転送
- Layer 4 (TCP/UDP): Caddy がプロトコルに関与せずバイトストリームをそのまま転送。暗号化はWireGuardが担当

## Caddy L4 ビルド手順

標準の Caddy には L4 モジュールが含まれないため、xcaddy でカスタムビルドする:

```bash
go install github.com/caddyserver/xcaddy/cmd/xcaddy@latest
xcaddy build --with github.com/mholt/caddy-l4
sudo mv caddy /usr/bin/caddy
```

## Caddy 設定 (JSON)

L4 ルーティングは Caddyfile 非対応のため、JSON設定を使用する:

```json
{
  "apps": {
    "http": {
      "servers": {
        "web": {
          "listen": [":443"],
          "routes": [
            {
              "match": [{"host": ["app.example.com"]}],
              "handle": [{
                "handler": "reverse_proxy",
                "upstreams": [{"dial": "100.64.0.2:8080"}]
              }]
            },
            {
              "match": [{"host": ["api.example.com"]}],
              "handle": [{
                "handler": "reverse_proxy",
                "upstreams": [{"dial": "100.64.0.3:3000"}]
              }]
            }
          ]
        }
      }
    },
    "layer4": {
      "servers": {
        "ssh": {
          "listen": ["0.0.0.0:2222"],
          "routes": [{
            "handle": [{
              "handler": "proxy",
              "upstreams": [{"dial": ["100.64.0.2:22"]}]
            }]
          }]
        },
        "postgres": {
          "listen": ["0.0.0.0:5432"],
          "routes": [{
            "handle": [{
              "handler": "proxy",
              "upstreams": [{"dial": ["100.64.0.3:5432"]}]
            }]
          }]
        },
        "game_udp": {
          "listen": ["udp/0.0.0.0:27015"],
          "routes": [{
            "handle": [{
              "handler": "proxy",
              "upstreams": [{"dial": ["udp/100.64.0.4:27015"]}]
            }]
          }]
        }
      }
    }
  }
}
```

## ACL ポリシー

`/etc/headscale/acl.json`:

```json
{
  "hosts": {
    "raspberry-pi": "100.64.0.1",
    "machine-a": "100.64.0.2",
    "machine-b": "100.64.0.3",
    "machine-c": "100.64.0.4"
  },
  "acls": [
    {
      "action": "accept",
      "src": ["raspberry-pi"],
      "dst": [
        "machine-a:22",
        "machine-a:8080",
        "machine-b:3000",
        "machine-b:5432",
        "machine-c:27015"
      ]
    }
  ]
}
```

Raspberry Pi (Caddy) からのみ、各マシンの必要なポートへのアクセスが許可される。

## ルーター ポートフォワード一覧

| 外部ポート | 転送先 (Pi) | プロトコル | 用途 |
|---|---|---|---|
| 80 | :80 | TCP | Caddy HTTP / ACME チャレンジ |
| 443 | :443 | TCP | Caddy HTTPS (L7) |
| 2222 | :2222 | TCP | SSH 中継 (L4) |
| 5432 | :5432 | TCP | PostgreSQL 中継 (L4) |
| 27015 | :27015 | UDP | ゲームサーバー 中継 (L4) |
| 8080 | :8080 | TCP | Headscale ノード登録 |

## DNS レコード

```
hs.example.com     A    <グローバルIP or DDNS>
app.example.com    A    <グローバルIP or DDNS>
api.example.com    A    <グローバルIP or DDNS>
```

TCP/UDP の L4 プロキシはホスト名による振り分けができないため、ポート番号で区別する。同一ドメインまたはIPに対してポートを指定して接続する:

```bash
ssh -p 2222 user@example.com
psql -h example.com -p 5432 -U dbuser mydb
```

## セキュリティ特性

1. **多層暗号化**: HTTP/HTTPS は Caddy が TLS 終端、全プロトコル共通で tailnet の WireGuard が暗号化
2. **最小権限 ACL**: Pi からのみ、必要なマシン:ポートの組み合わせだけ許可
3. **ゼロ露出**: バックエンドマシンはインターネットに直接接続しない
4. **統一管理**: Caddy 1プロセスで L4/L7 両方を処理。設定・監視が一元化
5. **プロトコル非依存**: TCP/UDP いずれも tailnet 経由で安全に転送可能

## 注意事項

- Caddy L4 はカスタムビルドが必要。Raspberry Pi 上で Go のビルド環境を整えるか、クロスコンパイルする
- L4 プロキシはプロトコルの中身を解釈しないため、アプリケーション層の認証はバックエンド側で実装する必要がある
- UDP の WireGuard 転送はオーバーヘッドが大きく、リアルタイム性の要求が厳しい用途（FPSゲーム等）では遅延に注意
- Raspberry Pi の処理能力がボトルネックになり得る。高スループットが必要な場合はより高性能なマシンの利用を検討
- Headscale のバージョンによりコマンド体系が異なる場合がある
