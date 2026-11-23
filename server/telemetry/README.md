# Telemetry collector

Every client (desktop and web, not the dedicated server or headless runs) sends anonymous events to `https://fallout-telemetry.drew.place/v1/events` from `game/telemetry.gd`. Players can turn it off in **Settings > SEND TELEMETRY**.

Events, one JSON object per POST:
- `session`: OS, web, renderer, GPU adapter, window/screen size, cores, locale, engine version.
- `perf`, every 60 s while the game is open: the frame-time histogram since the last send, average/worst frame, new spikes of 100 ms or more with the `Perf` marks before them, scene, nodes, draws, memory, and the map/wave/players when in a run.
- `run_start` / `run_end`: map, online or solo, player count, waves, result, endless score, time.

Every event carries a random install id (`Settings.install_id`), a session id, a sequence number, and `Net.PROTOCOL`. No names, chat, or input are collected. The collector does not log IPs; it keeps them only in memory for rate limiting (120 events per IP per 10 minutes, 64 KB per event).

## Running with Docker

Build and run the collector from `server/telemetry/`:

```sh
docker build -t fallout-telemetry server/telemetry
docker run -d --name fallout-telemetry \
  --read-only \
  -p 8080:8080 \
  -v fallout-telemetry-data:/data \
  fallout-telemetry
```

Place a TLS-terminating reverse proxy in front of port `8080` with a 64 KB request body limit.

## Reading the data

Events are written to `/data/events-YYYY-MM-DD.jsonl` inside the container volume, and the oldest days are deleted once storage exceeds 2 GB. Export the JSONL files from the volume and summarize them with:

```sh
docker exec fallout-telemetry sh -c 'cat /data/events-*.jsonl' > telemetry.jsonl
python tools/telemetry/summary.py telemetry.jsonl
```
