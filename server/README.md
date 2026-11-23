# Dedicated server

All multiplayer uses WebSockets (`WebSocketMultiplayerPeer`), so desktop and web builds can play together. The default cloud server is `wss://fallout.drew.place/` (`Net.CLOUD_URL`, joined with `Net.join_cloud()`).

## Run locally

```sh
godot --headless --path . --audio-driver Dummy -- --server [--port=7777] [--map pinecrest] [--heartbeat=/tmp/fallout-heartbeat]
```

The server is peer 1 but is not a player. It logs joins, leaves, and runs to stdout. A run starts once every connected player is READY in the lobby (or force-started). After the results screen, or when everyone leaves, it unloads the run and waits for the next one. Code: `game/dedicated_server.gd`.

Players vote for a map or RANDOM before starting. The server chooses the winner and breaks ties at random. With no votes, it uses `--map <id>`. The default is Pinecrest, including when the supplied map is unavailable.

Clients join from **CLOUD PLAY** on the title screen. **Settings > SERVER (WSS)** can point the client at any server, e.g. `ws://127.0.0.1:7777/` for a local instance.

## Docker

The build context is the repo root (BuildKit reads `server/Dockerfile.dockerignore`).

```sh
# ARM64 (default)
docker build -f server/Dockerfile -t fallout-server .

# AMD64 / x86_64
docker build -f server/Dockerfile --build-arg GODOT_ARCH=x86_64 -t fallout-server .

# Run locally on port 7777
docker run --rm -p 7777:7777 fallout-server
```

- The image downloads the official Godot 4.7.2 Linux binary (verifying the SHA512 checksum on `arm64`), builds the `.godot` import cache at build time, and runs as an unprivileged user under `tini`.
- **Liveness:** The server rewrites `/tmp/fallout-heartbeat` every 15 s, and the Docker `HEALTHCHECK` fails if the file is older than a minute.
- **Reverse proxy & TLS:** Browser builds served over HTTPS require `wss://`. In production, place a TLS-terminating reverse proxy in front of container port `7777` that forwards WebSocket upgrade requests (`Upgrade: websocket`).
- **CI:** The **Dedicated server build** GitHub Actions workflow (`server-build.yml`) builds the container image and verifies both the healthcheck and WebSocket upgrade handshake.
- **Protocol compatibility:** Clients must match the server's `Net.PROTOCOL` version. Bump `Net.PROTOCOL` whenever an RPC or networked scene path changes; mismatched clients are turned away with a message.
