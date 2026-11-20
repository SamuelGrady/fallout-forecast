# Fallout Forecast on the web

Install the official Godot 4.7.2 export templates, then run these commands from the repo root.

```sh
mkdir -p build/web
godot --headless --import
godot --headless --export-release Web build/web/index.html
python -m http.server 8000 --bind 127.0.0.1 --directory build/web
```

Open `http://127.0.0.1:8000/` in a desktop browser with WebGL 2. Click **Start game** to enable audio. Click the canvas during a run to capture the mouse. The fullscreen button is available while the mouse is free. Esc releases capture or fullscreen.

Web uses the single-threaded Compatibility renderer export and retains Jolt. It uses CPU rain without roof-heightfield collision, fades nearby drops under shelter, and keeps exponential fog. Glow, the VHS screen shader passes, and the PS1 material swap are disabled on web. The REC and timestamp overlay remains. Once the WebSocket client ships, web players can join the cloud server at `wss://fallout.drew.place/` through **Join Game**.

The production image builds with `docker build -f web/Dockerfile .` on ARM64 or AMD64. Nginx serves port 8080 with a `/healthz` probe. It serves the HTML with `no-store` and compressed WASM, PCK, and JS from a content-hashed directory. The launcher resolves assets relative to `/fallout/`.

Coolify should deploy this image from the GitHub App source on `master`, with its native push webhook enabled. For the first deployment, select `web-build`, deploy it, then set the monitored branch to `master` without redeploying until the branch is merged. Use the Dockerfile build pack, base directory `/`, Dockerfile `/web/Dockerfile`, and no generated domain. Add these Caddy labels to the game app. They extend the existing `https://drewdettmer.com` site block with a more specific route, stripping the prefix before proxying to nginx.

```ini
caddy_ingress_network=coolify
caddy_0=https://drewdettmer.com
caddy_0.redir=/fallout /fallout/ 308
caddy_0.handle_path=/fallout/*
caddy_0.handle_path.0_reverse_proxy={{upstreams 8080}}
```
