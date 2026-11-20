# Telemetry collector

Every client (desktop and web, not the dedicated server or headless runs) sends anonymous events to `https://fallout-telemetry.drew.place/v1/events` from `game/telemetry.gd`. Players can turn it off in Settings > SEND TELEMETRY.

Events, one JSON object per POST:
- `session`: OS, web, renderer, GPU adapter, window/screen size, cores, locale, engine version.
- `perf`, every 60 s while the game is open: the frame-time histogram since the last send, average/worst frame, new spikes of 100 ms or more with the Perf marks before them, scene, nodes, draws, memory, and the map/wave/players when in a run.
- `run_start` / `run_end`: map, online or solo, player count, waves, result, endless score, time.

Every event carries a random install id (`Settings.install_id`), a session id, a sequence number and `Net.PROTOCOL`. No names, chat or input. The collector does not log IPs; it keeps them only in memory for rate limiting (120 events per IP per 10 minutes, 64 KB per event).

## Deploy (ballista, plain compose like the original fallout-server)

```
ssh root@ballista
cd /opt/fallout-telemetry/src && git pull   # or copy server/telemetry/ here
docker compose -p fallout-telemetry -f server/telemetry/docker-compose.yml up -d --build
```

The container joins the `coolify` network; its `caddy` labels make coolify-proxy issue the certificate for `fallout-telemetry.drew.place` (covered by the `*.drew.place` DNS wildcard) and proxy to port 8080.

## Read the data

Files are `/data/events-YYYY-MM-DD.jsonl` in the `fallout-telemetry_fallout-telemetry-data` volume. The oldest days are deleted past 2 GB.

```
ssh root@ballista docker exec fallout-telemetry sh -c 'cat /data/events-*.jsonl' > telemetry.jsonl
python tools/telemetry/summary.py telemetry.jsonl
```
