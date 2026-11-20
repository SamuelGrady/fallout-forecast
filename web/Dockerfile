FROM debian:bookworm-slim AS export

ARG TARGETARCH
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl libfontconfig1 libgl1 libasound2 unzip \
    && rm -rf /var/lib/apt/lists/*

RUN set -eu; \
    case "${TARGETARCH:-$(uname -m)}" in \
        amd64|x86_64) arch=x86_64; digest=cadd3204e728a35d3f13adb7fd0d7902636b79f6b95c40c265eb73b6c35329e4 ;; \
        arm64|aarch64) arch=arm64; digest=5dd0d86405cf7e8adf79fb6377b38ba682a2846cb378ffe5364f38c01ad29b9d ;; \
        *) echo "Unsupported build architecture: $TARGETARCH" >&2; exit 1 ;; \
    esac; \
    release=https://github.com/godotengine/godot-builds/releases/download/4.7.2-stable; \
    curl --fail --silent --show-error --location --retry 3 \
        "$release/Godot_v4.7.2-stable_linux.$arch.zip" -o /tmp/godot.zip; \
    echo "$digest  /tmp/godot.zip" | sha256sum --check; \
    unzip -j /tmp/godot.zip "Godot_v4.7.2-stable_linux.$arch" -d /tmp; \
    install "/tmp/Godot_v4.7.2-stable_linux.$arch" /usr/local/bin/godot; \
    curl --fail --silent --show-error --location --retry 3 \
        "$release/Godot_v4.7.2-stable_export_templates.tpz" -o /tmp/templates.tpz; \
    echo "f298490b8d44d934be425a5a65a51bf15f422428b229a06a6e11d9ffea248011  /tmp/templates.tpz" | sha256sum --check; \
    mkdir -p /root/.local/share/godot/export_templates/4.7.2.stable; \
    unzip -j /tmp/templates.tpz templates/web_nothreads_release.zip templates/version.txt \
        -d /root/.local/share/godot/export_templates/4.7.2.stable; \
    rm /tmp/godot.zip /tmp/templates.tpz "/tmp/Godot_v4.7.2-stable_linux.$arch"

WORKDIR /project
COPY . .
RUN godot --headless --import \
    && mkdir -p /export \
    && godot --headless --export-release Web /export/game.html

RUN set -eu; \
    cd /export; \
    version=$(sha256sum ./* | sha256sum | cut -c1-32); \
    mkdir -p "/site/$version"; \
    sed "/<head>/a\  <base href=\"./$version/\">" game.html > /site/index.html; \
    rm game.html; \
    mv ./* "/site/$version/"; \
    gzip -k -9 "/site/$version/game.wasm" "/site/$version/game.pck" "/site/$version/game.js"

FROM nginx:stable-alpine
RUN apk add --no-cache curl
COPY web/nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=export /site/ /usr/share/nginx/html/
EXPOSE 8080
