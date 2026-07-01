# FROM [イメージ] [タグ]
# ホストのDockerを操作する(docker-outside-of-docker)ため、
# docker CLI 同梱イメージをベースにする
FROM docker:27-cli

# 環境変数を docker-compose.yml から受け取る
ARG LANG

ENV LANG=${LANG}

# RUN 命令はなるべく1つにまとめる
RUN apk add --no-cache bash git openssl curl

COPY start.sh /start.sh
RUN chmod +x /start.sh

ENTRYPOINT ["/start.sh"]
