#!/usr/bin/env bash
set -e

# コンテナ内でも「ホストと同じ絶対パス」で見えている前提
# (compose.ymlで ${PWD}:${PWD} をマウントしているため)
cd "${HOST_PROJECT_DIR}"

REPO_PATH="${HOST_PROJECT_DIR}/${REPO_DIR}"

if [ ! -d "${REPO_PATH}" ]; then
    echo "[bootstrap] cloning ${REPO_URL} ..."
    git clone "${REPO_URL}" "${REPO_PATH}"
else
    echo "[bootstrap] ${REPO_DIR} already exists. pulling latest..."
    git -C "${REPO_PATH}" pull || echo "[bootstrap] pull failed (offline?) - continuing with existing checkout"
fi

cd "${REPO_PATH}"
chmod +x ./generate_config.sh

if [ -f "Revolt.toml" ]; then
    echo "[bootstrap] Revolt.toml already exists -> generate_config.sh をスキップします(既存シークレットを保持)"
else
    echo "[bootstrap] generating config for domain: ${DOMAIN}"
    # generate_config.sh の対話プロンプトに自動回答する
    # 1問目: reverse proxyを使うか [y/N]
    # 2問目: video(カメラ/画面共有)を有効にするか [Y/n]
    printf "%s\n%s\n" "${ENABLE_REVERSE_PROXY}" "${ENABLE_VIDEO}" | ./generate_config.sh "${DOMAIN}"
fi

# ## MongoDB tcmalloc/39bit VA 問題への対策
#
# Raspberry Pi標準カーネル(39bit VA)では、MongoDB 8.x系が内蔵する
# tcmalloc(48bit VA前提でmmapヒントアドレスを生成する)が
# `arena.cc: CHECK in Alloc: FATAL ERROR` でクラッシュすることがある。
# 実メモリ不足でもDockerのメモリ制限でもなく、カーネルのVA幅と
# tcmallocの前提のミスマッチが原因のため、compose.override.ymlで
# MongoDBのイメージタグを固定して回避する。
#
# | 判定 | 動作 |
# | --- | --- |
# | compose.override.yml が存在しない | 新規作成してdatabaseサービスを書き込む |
# | 存在するが database: 定義が無い | 末尾にdatabaseサービスを追記する |
# | 存在して database: 定義が既にある | ユーザー設定を尊重し何もしない |
COMPOSE_OVERRIDE="${REPO_PATH}/compose.override.yml"
MONGO_IMAGE_TAG="${MONGO_IMAGE_TAG:-7.0}"

# database: というYAMLキー(2スペースインデント)が既にあるかどうかで判定する
if [ -f "${COMPOSE_OVERRIDE}" ] && grep -qE "^[[:space:]]{2}database:[[:space:]]*$" "${COMPOSE_OVERRIDE}"; then
    echo "[bootstrap] compose.override.yml に database サービスの定義が既にあるためスキップします"
else
    echo "[bootstrap] compose.override.yml に MongoDB(${MONGO_IMAGE_TAG}) 固定設定を書き込みます"

    if [ ! -f "${COMPOSE_OVERRIDE}" ]; then
        echo "services:" > "${COMPOSE_OVERRIDE}"
    elif ! grep -qE "^services:[[:space:]]*$" "${COMPOSE_OVERRIDE}"; then
        # 既存ファイルはあるが services: トップレベルキーが無い異常系。
        # 壊さないよう自動追記は諦め、手動対応を促して終了する。
        echo "[bootstrap][warn] ${COMPOSE_OVERRIDE} に 'services:' が見つかりません。" >&2
        echo "[bootstrap][warn] 自動追記をスキップします。手動で database サービスを追加してください。" >&2
        COMPOSE_OVERRIDE=""
    fi

    if [ -n "${COMPOSE_OVERRIDE}" ]; then
        cat >> "${COMPOSE_OVERRIDE}" <<EOF
  # Raspberry Pi(39bit VA)で MongoDB 8.x の tcmalloc が
  # mmapに失敗してクラッシュする問題を避けるためのバージョン固定
  # (start.sh が自動生成 / MONGO_IMAGE_TAG は .env で変更可能)
  database:
    image: mongo:${MONGO_IMAGE_TAG}
    healthcheck:
      test: echo 'db.runCommand("ping").ok' | mongosh localhost:27017/test --quiet
      interval: 10s
      timeout: 10s
      retries: 5
      start_period: 10s
EOF
    fi
fi

echo "[bootstrap] starting Stoat stack (docker compose -p stoat up -d) ..."
docker compose -p stoat up -d --remove-orphans

echo "[bootstrap] done. 'docker ps' でstoat-*コンテナが起動しているか確認してください。"
