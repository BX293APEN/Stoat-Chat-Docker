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

echo "[bootstrap] starting Stoat stack (docker compose -p stoat up -d) ..."
docker compose -p stoat up -d --remove-orphans

echo "[bootstrap] done. 'docker ps' でstoat-*コンテナが起動しているか確認してください。"
