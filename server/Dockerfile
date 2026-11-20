# Fallout Forecast dedicated server (headless Godot, WebSocket on TCP 7777).
# Build from the repo root:  docker build -f server/Dockerfile -t fallout-server .
# Targets linux/arm64 (ballista); set GODOT_ARCH=x86_64 for an amd64 host.

FROM debian:bookworm-slim AS godot
ARG GODOT_VERSION=4.7.2
ARG GODOT_ARCH=arm64
# SHA512 of Godot_v4.7.2-stable_linux.arm64.zip from the release's SHA512-SUMS.txt.
ARG GODOT_SHA512=dd59918da086bd49bde2f5450b5e567ff8650cbde9abbd7b8f4ca1197ff8c609baa38834666d032deafb47099078d7822279e2a0e06e5665745468f26533e7e2
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl unzip \
 && rm -rf /var/lib/apt/lists/*
RUN curl -fsSL -o /tmp/godot.zip \
      "https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable/Godot_v${GODOT_VERSION}-stable_linux.${GODOT_ARCH}.zip" \
 && if [ "$GODOT_ARCH" = "arm64" ]; then echo "${GODOT_SHA512}  /tmp/godot.zip" | sha512sum -c -; fi \
 && unzip -q /tmp/godot.zip -d /tmp/godot \
 && mv /tmp/godot/Godot_v${GODOT_VERSION}-stable_linux.${GODOT_ARCH} /usr/local/bin/godot \
 && chmod +x /usr/local/bin/godot


FROM debian:bookworm-slim
RUN apt-get update \
 && apt-get install -y --no-install-recommends libfontconfig1 tini \
 && rm -rf /var/lib/apt/lists/* \
 && useradd --create-home --uid 10001 fallout
COPY --from=godot /usr/local/bin/godot /usr/local/bin/godot
COPY --chown=fallout:fallout . /game
USER fallout
ENV HOME=/home/fallout
WORKDIR /game
# Build the .godot import cache now so the server starts in seconds.
RUN godot --headless --path /game --import >/tmp/import.log 2>&1 || true; \
    test -f /game/.godot/global_script_class_cache.cfg \
 || (tail -40 /tmp/import.log; exit 1)

EXPOSE 7777/tcp
# The server rewrites this file every 15 s; a stale file means the main loop hung.
HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 \
  CMD find /tmp/fallout-heartbeat -mmin -1 | grep -q . || exit 1
ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["godot", "--headless", "--path", "/game", "--audio-driver", "Dummy", \
     "--", "--server", "--port=7777", "--heartbeat=/tmp/fallout-heartbeat"]
