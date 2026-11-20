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

### Production deployment on ballista (Coolify)

The live server runs in Coolify on `ballista` as **Fallout Forecast Server** (`ghydxqhpmoruqs6yf4wayosl`), built from `kickofline/fallout-forecast` on `master` using Dockerfile build pack, repository root as the context, `/server/Dockerfile`, and port `7777`.

- **Auto-deploy:** Enabled via the Coolify GitHub App push webhook on `master`. Every push to `master` rebuilds the ARM64 container on `ballista` and also runs the **Dedicated server build** GitHub Actions workflow (`server-build.yml`) to verify Docker health and WebSocket upgrade.
- **Routing:** `coolify-proxy` terminates TLS for `https://fallout.drew.place` / `wss://fallout.drew.place/` and proxies WebSocket upgrades to port `7777` (while answering plain HTTP probes directly).
- **Protocol compatibility:** Clients must run the same build as the server. Bump `Net.PROTOCOL` whenever an RPC or a networked scene path changes; mismatched clients are turned away with a message.
- **Manual/local Docker check:** `server/docker-compose.yml` remains available if you want to build and run the image locally (`docker build -f server/Dockerfile -t fallout-server:<git sha> .`).
