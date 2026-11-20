# Dedicated server

All multiplayer uses WebSockets (`WebSocketMultiplayerPeer`), so desktop and web builds can play together. The cloud server is `wss://fallout.drew.place/` (`Net.CLOUD_URL`, joined with `Net.join_cloud()`).

## Run locally

```
godot --headless --path . --audio-driver Dummy -- --server [--port=7777] [--heartbeat=/tmp/fallout-heartbeat]
```

The server is peer 1 but is not a player. It logs joins, leaves and runs to stdout. A run starts once every connected player is READY in the lobby. After the results screen, or when everyone leaves, it unloads the run and waits for the next one. Code: `game/dedicated_server.gd`.

Clients join from JOIN GAME. Use CLOUD SERVER, or type `127.0.0.1:7777`, `ws://host:port/` or `wss://host/`.

## Docker (ballista, arm64)

The build context is the repo root. BuildKit reads `server/Dockerfile.dockerignore`.

```
docker build -f server/Dockerfile -t fallout-server:<git sha> .
FALLOUT_TAG=<git sha> docker compose -f server/docker-compose.yml up -d
```

- The image downloads the official Godot 4.7.2 `linux.arm64` binary and checks its SHA512. It builds the `.godot` import cache at build time and runs as an unprivileged user under tini.
- Liveness: the server rewrites `/tmp/fallout-heartbeat` every 15 s, and the Docker `HEALTHCHECK` fails if the file is older than a minute.
- Networking: no host port is published. The container is on the `coolify` network, and its `caddy` labels make coolify-proxy serve `fallout.drew.place` with TLS and reverse-proxy the WebSocket to port 7777. `*.drew.place` is a DNS-only wildcard to ballista, so Caddy gets the certificate itself.

### Redeploy on ballista

From the repo, on Drew's PC:

```
git archive fallout-server | ssh root@ballista "rm -rf /opt/fallout-server/src && mkdir -p /opt/fallout-server/src && tar -x -C /opt/fallout-server/src"
ssh root@ballista "cd /opt/fallout-server/src && docker build -f server/Dockerfile -t fallout-server:<sha> -t fallout-server:latest . && FALLOUT_TAG=<sha> docker compose -p fallout -f server/docker-compose.yml up -d"
```

Clients must run the same build as the server. Bump `Net.PROTOCOL` whenever an RPC or a networked scene path changes; mismatched clients are turned away with a message.
