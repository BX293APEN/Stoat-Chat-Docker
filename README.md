# Stoat

`docker compose up --build -d` だけで、Stoat(旧Revolt)本体 + 前段nginxまで
まとめて立ち上げるための構成です。

```
Stoat/
├── .env
├── compose.yml
├── Dockerfile          # bootstrapコンテナ用
├── start.sh            # bootstrapコンテナのエントリポイント
└── linux_data/
    └── nginx/
        └── config/
            └── stoat.conf   # nginxのserver{}ブロック(conf.d配下にマウント)
```

## サービス構成

- **bootstrap**: `stoatchat/self-hosted` を clone → `generate_config.sh` を自動実行 →
  ホストのDockerに対して `docker compose -p stoat up -d` を発行し、Stoat本体を起動する使い捨てコンテナ
- **nginx**: 将来の公開を見据えた経路管理・証明書管理の窓口。
  Stoat本体側のCaddy(ホストの`127.0.0.1:8880`)へリバースプロキシする

```
[インターネット] → nginx(80/443, 証明書管理) → Caddy(:8880, docker-outside-of-dockerで起動)
                                                    → api / events / autumn / january / web / ...
```

## 使い方

```bash
cd Stoat
$EDITOR .env   # DOMAIN と linux_data/nginx/config/stoat.conf の server_name を実際の値に変更
docker compose up --build -d
```

`nginx`サービスは`bootstrap`が正常終了する(=Stoat本体の起動を発行し終わる)まで起動を待ちます
(`depends_on: condition: service_completed_successfully`)。

## 動作確認

```bash
docker compose logs -f bootstrap   # clone・config生成・起動の様子
docker ps --filter "name=stoat-"   # Stoat本体のコンテナ一覧(別プロジェクト "stoat")
docker compose logs -f nginx       # nginxのアクセス/エラーログ
```

## 証明書を使う場合

`stoat.conf`の`ssl_certificate`関連行のコメントを外し、証明書ファイルを
`linux_data/nginx/certs/`などに置いた上で、`compose.yml`のnginxサービスに
以下のようなマウントを追加してください。

```yaml
    volumes:
      - ${VOLUME}/nginx/config/stoat.conf:/etc/nginx/conf.d/stoat.conf:ro
      - ${VOLUME}/nginx/certs:/etc/letsencrypt:ro
```

certbotでの取得自体はこのnginxコンテナの外(ホスト側のcertbot、または別途webrootモード用の
サービスを追加するなど)で行う想定です。

## なぜ `host.docker.internal` を使っているか

`nginx`はDockerコンテナとして動いているため、`stoat.conf`内で単純に`127.0.0.1:8880`と
書いてもそれは**nginxコンテナ自身**を指してしまい、ホスト上で待ち受けているCaddyには届きません。
そのため`compose.yml`側で

```yaml
extra_hosts:
  - "host.docker.internal:host-gateway"
```

を設定し、`stoat.conf`側は`http://host.docker.internal:8880`宛にproxy_passしています。

## なぜbootstrapコンテナ内で絶対パスが必要か(docker-outside-of-docker の罠)

bootstrapコンテナは `/var/run/docker.sock` 経由で**ホストのDocker**に対して
`docker compose -p stoat up -d` を発行しています。この時、Stoat側`compose.yml`内の
相対パス(`./Revolt.toml` など)は「コマンドを打ったプロセスのカレントディレクトリ」を基準に
文字列として解決され、その結果がそのままホストのDockerデーモンに渡ります。

コンテナ内のカレントディレクトリとホスト上の実パスが一致していないと、
生成された絶対パス文字列がホスト上に存在せず、bind mountが壊れます。
そのため `${PWD}:${PWD}` で「コンテナ内でも全く同じ絶対パスに見える」状態を作り、
この問題を回避しています。`${PWD}`はシェルが自動でexportする環境変数なので、
利用者側で絶対パスを手打ちする必要はありません(必ずこの`Stoat`フォルダの中で
`docker compose up`を実行してください)。

## 設定をやり直したい場合

`stoat/Revolt.toml` が存在する限り自動生成はスキップされます。設定をやり直したい場合は、
`secrets.env`を必ず保持した上で`--overwrite`フラグ付きで手動実行してください
(失うとアップロード済みファイルに一切アクセスできなくなります)。

```bash
cd Stoat/stoat
./generate_config.sh --overwrite <新しいDOMAIN>
docker compose up -d
```

## セキュリティ上の注意

bootstrapコンテナは `/var/run/docker.sock` をマウントしているため、
**ホストのDockerに対してroot相当の権限**を持ちます。個人宅サーバーでの運用を想定していますが、
取り扱いには注意してください。
