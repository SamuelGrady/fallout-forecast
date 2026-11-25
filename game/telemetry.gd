extends Node
## Autoload "Telemetry": sends anonymous performance and run data from every
## client to the Fallout Forecast telemetry server, so real web/desktop hitches
## show up without anyone exporting a report. Settings > SEND TELEMETRY turns
## it off (Settings.telemetry_enabled); the dedicated server never sends.
##
## What is sent (JSON, one event per POST):
## - session: platform, web or not, renderer, GPU adapter, window size,
##   protocol, a random install id (Settings.install_id) and session id.
## - perf (every INTERVAL s while playing): frame-time histogram delta, average
##   and worst frame, and the new >= 100 ms spikes with the events before them
##   (Perf marks: scene, phase, first sound, spawn...).
## - run_start / run_end: map, players, online or solo, waves, result, time.
## No names, chat, IPs in the payload or input data. The server sees the IP
## as any web server does and does not store it.

const URL := "https://fallout-telemetry.drew.place/v1/events"
const INTERVAL := 60.0
## For local testing: FALLOUT_TELEMETRY_URL overrides URL and
## FALLOUT_TELEMETRY_FORCE=1 sends from headless runs too.
const MAX_QUEUE := 24
const MAX_SPIKES_PER_SEND := 40

var _session := ""
var _http: HTTPRequest
var _queue: Array[String] = []
var _busy := false
var _clock := 0.0
var _last_snap := {}
var _last_spike := 0
var _seq := 0


func _ready() -> void:
	if Net.car_bridge:
		set_process(false)
		return
	process_mode = Node.PROCESS_MODE_ALWAYS
	_session = Crypto.new().generate_random_bytes(8).hex_encode()
	_http = HTTPRequest.new()
	_http.timeout = 45.0
	_http.request_completed.connect(_on_done)
	add_child(_http)
	GameManager.run_finished.connect(_on_run_finished)
	_send_session.call_deferred()


func _active() -> bool:
	if Net.car_bridge:
		return false
	if OS.get_environment("FALLOUT_TELEMETRY_FORCE") == "1":
		return Settings.telemetry_enabled
	return Settings.telemetry_enabled and not Net.dedicated and DisplayServer.get_name() != "headless"


func _send_session() -> void:
	if not _active():
		return
	_last_snap = Perf.snapshot()
	_last_spike = Perf.spike_seq
	_enqueue("session", {
		"os": OS.get_name(),
		"web": OS.has_feature("web"),
		"renderer": RenderingServer.get_current_rendering_method(),
		"adapter": "%s %s" % [RenderingServer.get_video_adapter_vendor(), RenderingServer.get_video_adapter_name()],
		"window": [int(get_viewport().get_visible_rect().size.x), int(get_viewport().get_visible_rect().size.y)],
		"screen": [DisplayServer.screen_get_size().x, DisplayServer.screen_get_size().y],
		"cores": OS.get_processor_count(),
		"locale": OS.get_locale_language(),
		"engine": Engine.get_version_info().string,
	})


func _process(delta: float) -> void:
	_clock += delta / maxf(Engine.time_scale, 0.0001)
	if _clock < INTERVAL:
		return
	_clock = 0.0
	if _active():
		_send_perf()


## Frame data since the last send. Skipped when nothing new happened.
func _send_perf() -> void:
	var now: Dictionary = Perf.snapshot()
	var frames := int(now.frames) - int(_last_snap.get("frames", 0))
	if frames <= 0:
		return
	var hist: Array = []
	var old_hist: Array = _last_snap.get("hist", [])
	for i in (now.hist as Array).size():
		hist.append(int(now.hist[i]) - (int(old_hist[i]) if i < old_hist.size() else 0))
	var spikes: Array = []
	for s in Perf.spikes_since(_last_spike):
		spikes.append({"t": snappedf(float(s.t), 0.1), "ms": roundi(float(s.ms)), "scene": s.scene,
			"nodes": s.nodes, "draws": s.draws, "before": s.before})
	if spikes.size() > MAX_SPIKES_PER_SEND:
		spikes = spikes.slice(spikes.size() - MAX_SPIKES_PER_SEND)
	_last_spike = Perf.spike_seq
	var total := float(now.total_ms) - float(_last_snap.get("total_ms", 0.0))
	_enqueue("perf", {
		"frames": frames,
		"avg_ms": snappedf(total / frames, 0.1),
		"worst_ms": roundi(float(now.worst_ms)),
		"hist": hist,
		"spikes": spikes,
		"scene": now.scene,
		"nodes": now.nodes,
		"draws": now.draws,
		"mem_mb": now.mem_mb,
		"map": GameManager.map_id if GameManager.run_active else "",
		"wave": WeatherManager.wave if GameManager.run_active else 0,
		"players": GameManager.player_count() if GameManager.run_active else 0,
		"online": Net.is_online(),
	})
	_last_snap = now


## Main calls this when a run begins on this peer.
func run_started(map_id: String) -> void:
	if _active():
		_enqueue("run_start", {"map": map_id, "online": Net.is_online(), "players": GameManager.player_count()})


func _on_run_finished(won: bool, results: Dictionary) -> void:
	if not _active():
		return
	_send_perf()
	_enqueue("run_end", {
		"won": won,
		"map": str(results.get("map_id", "")),
		"waves": int(results.get("waves", 0)),
		"wave_reached": int(results.get("wave_reached", 0)),
		"endless": bool(results.get("endless", false)),
		"endless_score": int(results.get("endless_score", 0)),
		"seconds": int(results.get("seconds", 0)),
		"players": (results.get("players", {}) as Dictionary).size() if results.get("players") is Dictionary else 1,
		"online": Net.is_online(),
	})


func _notification(what: int) -> void:
	# Best effort on desktop quit; browsers just close.
	if what == NOTIFICATION_WM_CLOSE_REQUEST and _active():
		_send_perf()


func _enqueue(kind: String, data: Dictionary) -> void:
	_seq += 1
	var event := {
		"v": 1,
		"kind": kind,
		"install": Settings.install_id,
		"session": _session,
		"seq": _seq,
		"t": snappedf(Time.get_ticks_msec() / 1000.0, 0.1),
		"protocol": Net.PROTOCOL,
		"web": OS.has_feature("web"),
		"data": data,
	}
	_queue.append(JSON.stringify(event))
	while _queue.size() > MAX_QUEUE:
		_queue.pop_front()
	_pump()


func _pump() -> void:
	if _busy or _queue.is_empty() or not _active():
		return
	_busy = true
	# text/plain keeps the browser's fetch a "simple" CORS request (no preflight).
	var url := OS.get_environment("FALLOUT_TELEMETRY_URL") if OS.has_environment("FALLOUT_TELEMETRY_URL") else URL
	var err := _http.request(url, ["Content-Type: text/plain"], HTTPClient.METHOD_POST, _queue[0])
	if err != OK:
		_busy = false
		_queue.pop_front()


func _on_done(result: int, code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	_busy = false
	# Drop the event whether or not it landed: telemetry must never pile up or retry-storm.
	if not _queue.is_empty():
		_queue.pop_front()
	if result != HTTPRequest.RESULT_SUCCESS or code >= 400:
		Perf.mark("telemetry failed %d/%d" % [result, code])
	_pump()
