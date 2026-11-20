# Fallout Forecast on the web

Install the official Godot 4.7.2 export templates, then run these commands from the repo root.

```sh
mkdir -p build/web
godot --headless --import
godot --headless --export-release Web build/web/index.html
python -m http.server 8000 --bind 127.0.0.1 --directory build/web
```

Open `http://127.0.0.1:8000/` in a desktop browser with WebGL 2. Click **Start game** to enable audio. Click the canvas during a run to capture the mouse. The fullscreen button is available while the mouse is free. Esc releases capture or fullscreen.

Web uses the single-threaded Compatibility renderer export and retains Jolt. It uses CPU rain without roof-heightfield collision, fades nearby drops under shelter, and keeps exponential fog. Glow, the VHS screen shader passes, and the PS1 material swap are disabled on web. The REC and timestamp overlay remains. To play online, select **Join Game** and choose the cloud server at `wss://fallout.drew.place/`.

The production image builds with `docker build -f web/Dockerfile .` on ARM64 or AMD64. Nginx serves port 8080 with a `/healthz` probe. It serves the HTML with `no-store` and compressed WASM, PCK, and JS from a content-hashed directory. The launcher resolves assets relative to `/fallout/`.

The **Web export** GitHub Actions workflow builds the ARM64 image, checks nginx responses, and uploads the web files as a workflow artifact on pushes to `web-build` and `master`. Production builds run in a separate Coolify app through the existing GitHub App push webhook. See [the rollout steps](deploy.md).
