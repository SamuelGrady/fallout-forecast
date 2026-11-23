# Fallout Forecast on the web

Install the official Godot 4.7.2 export templates, then run these commands from the repo root.

```sh
mkdir -p build/web
godot --headless --import
godot --headless --export-release Web build/web/index.html
python -m http.server 8000 --bind 127.0.0.1 --directory build/web
```

Open `http://127.0.0.1:8000/` in a desktop browser with WebGL 2. Click **PLAY** to enable audio. Click the canvas during a run to capture the mouse. The fullscreen button is available while the mouse is free. `Esc` releases capture or fullscreen.

Web uses the single-threaded Compatibility renderer export and retains Jolt. It uses CPU rain without roof-heightfield collision, fades nearby drops under shelter, and keeps exponential fog. Glow, the VHS screen shader passes, and the PS1 material swap are disabled on web, while the `REC` and timestamp overlay remains. To play online, select **CLOUD PLAY** to join the default cloud server (`wss://fallout.drew.place/`), or point **Settings > SERVER (WSS)** at another server.

## Docker & CI

Build the static container image from the repo root (ARM64 or AMD64):

```sh
docker build -f web/Dockerfile -t fallout-web .
docker run --rm -p 8080:8080 fallout-web
```

Nginx listens on port `8080` with a `/healthz` probe. It serves the HTML with `no-store` and compressed WASM, PCK, and JS from a content-hashed directory. When hosted behind a reverse proxy at a subpath, strip the `/fallout/` prefix before forwarding to port `8080` (the launcher resolves assets relative to `/fallout/`).

The **Web export** GitHub Actions workflow (`web-export.yml`) builds the container image, checks Nginx responses, and uploads the web export as a workflow artifact on pushes to `web-build` and `master`.
