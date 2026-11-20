extends CanvasLayer
## Autoload "Perf": frame-time telemetry you can run on web.
##
## Always on, very cheap: every frame's time goes into a histogram, and any
## frame over SPIKE_MS is recorded with what happened just before it
## (Perf.mark() calls: phase changes, spawns, first plays of a sound, scene
## loads, warm-up). Settings > PERFORMANCE OVERLAY shows live numbers; EXPORT
## PERF REPORT (settings or pause menu) downloads a text report on web (and
## copies it to the clipboard), or saves it to user:// on desktop.

const SPIKE_MS := 100.0
const MAX_SPIKES := 200
const MAX_EVENTS := 80
## Histogram buckets (upper bounds, ms) for frame-time percentiles.
const BUCKETS := [8, 12, 17, 25, 33, 50, 75, 100, 150, 250, 500, 1000, 2500, 5000, 1000000]

var _hist: Array[int] = []
var _frames := 0
var _total_ms := 0.0
var _worst_ms := 0.0
var _spikes: Array = []
var _events: Array = []  # [seconds, text]
var _last_us := 0
var _start_us := 0
var _overlay := Label.new()
var _recent_worst := 0.0
var _recent_clock := 0.0
var _scene := ""
## Monotonic spike counter, so Telemetry can send only new spikes.
var spike_seq := 0


func _ready() -> void:
	layer = 125
	process_mode = Node.PROCESS_MODE_ALWAYS
	_hist.resize(BUCKETS.size())
	_hist.fill(0)
	_start_us = Time.get_ticks_usec()
	_last_us = _start_us
	_overlay.position = Vector2(8, 120)
	_overlay.add_theme_font_size_override("font_size", 16)
	_overlay.add_theme_color_override("font_color", Color(0.6, 1.0, 0.7))
	_overlay.add_theme_color_override("font_outline_color", Color.BLACK)
	_overlay.add_theme_constant_override("outline_size", 4)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_overlay)
	get_tree().tree_changed.connect(_on_tree_changed)


## Note something that just happened, so a following spike can be explained.
func mark(text: String) -> void:
	_events.append([_seconds(), text])
	if _events.size() > MAX_EVENTS:
		_events.pop_front()


func _seconds() -> float:
	return (Time.get_ticks_usec() - _start_us) / 1000000.0


func _on_tree_changed() -> void:
	if not is_inside_tree():
		return
	var current := get_tree().current_scene
	var path := current.scene_file_path if current else ""
	if path != _scene:
		_scene = path
		mark("scene " + path.get_file())


func _process(delta: float) -> void:
	var now := Time.get_ticks_usec()
	var ms := (now - _last_us) / 1000.0
	_last_us = now
	_frames += 1
	_total_ms += ms
	_worst_ms = maxf(_worst_ms, ms)
	for i in BUCKETS.size():
		if ms <= BUCKETS[i]:
			_hist[i] += 1
			break
	if ms >= SPIKE_MS:
		var t := _seconds()
		var before: Array = []
		for e in _events:
			if t - float(e[0]) <= 2.0 + ms / 1000.0:
				before.append(e[1])
		spike_seq += 1
		_spikes.append({"id": spike_seq, "t": t, "ms": ms, "scene": _scene.get_file(), "before": before,
			"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
			"draws": int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))})
		if _spikes.size() > MAX_SPIKES:
			_spikes.pop_front()
	_recent_clock += delta
	_recent_worst = maxf(_recent_worst, ms)
	_overlay.visible = Settings.perf_overlay
	if _overlay.visible and _recent_clock >= 0.5:
		_overlay.text = "FPS %d  frame %.1f ms\nworst(0.5s) %.0f ms  spikes %d\ndraws %d  nodes %d  mem %.0f MB" % [
			Engine.get_frames_per_second(), ms, _recent_worst, _spikes.size(),
			int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
			int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
			Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0]
	if _recent_clock >= 0.5:
		_recent_clock = 0.0
		_recent_worst = 0.0


func _percentile(p: float) -> String:
	var target := int(_frames * p)
	var seen := 0
	for i in BUCKETS.size():
		seen += _hist[i]
		if seen >= target:
			return "<=%d ms" % BUCKETS[i] if BUCKETS[i] < 1000000 else ">5000 ms"
	return "?"


func report() -> String:
	var lines := PackedStringArray()
	lines.append("FALLOUT FORECAST PERF REPORT")
	lines.append("time %s  session %.0f s  protocol v%d" % [Time.get_datetime_string_from_system(), _seconds(), Net.PROTOCOL])
	lines.append("platform %s  web %s  renderer %s  adapter %s %s" % [OS.get_name(), OS.has_feature("web"),
		RenderingServer.get_current_rendering_method(), RenderingServer.get_video_adapter_vendor(), RenderingServer.get_video_adapter_name()])
	lines.append("window %s  scene %s" % [str(get_viewport().get_visible_rect().size), _scene.get_file()])
	lines.append("frames %d  avg %.1f ms  worst %.0f ms  p50 %s  p95 %s  p99 %s" % [_frames,
		_total_ms / maxf(_frames, 1), _worst_ms, _percentile(0.5), _percentile(0.95), _percentile(0.99)])
	lines.append("")
	lines.append("FRAME HISTOGRAM (ms bucket: frames)")
	for i in BUCKETS.size():
		if _hist[i] > 0:
			lines.append("  <=%s: %d" % [str(BUCKETS[i]) if BUCKETS[i] < 1000000 else "inf", _hist[i]])
	lines.append("")
	lines.append("SPIKES >= %d ms (newest last)" % int(SPIKE_MS))
	for s in _spikes:
		lines.append("  %7.1fs  %6.0f ms  %s  nodes %d draws %d  after: %s" % [s.t, s.ms, s.scene, s.nodes, s.draws, ", ".join(PackedStringArray(s.before.map(func(x): return str(x))))])
	lines.append("")
	lines.append("RECENT EVENTS")
	for e in _events:
		lines.append("  %7.1fs  %s" % [e[0], e[1]])
	return "\n".join(lines)


## Cumulative counters for Telemetry (it sends deltas).
func snapshot() -> Dictionary:
	return {"frames": _frames, "total_ms": _total_ms, "worst_ms": _worst_ms, "hist": _hist.duplicate(), "seconds": _seconds(),
		"scene": _scene.get_file(), "nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"draws": int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		"mem_mb": snappedf(Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0, 0.1)}


func spikes_since(id: int) -> Array:
	return _spikes.filter(func(s: Dictionary) -> bool: return int(s.id) > id)


## Download (web) or save (desktop) the report, and copy it to the clipboard.
## Returns where it went, for a status line.
func export_report() -> String:
	var text := report()
	DisplayServer.clipboard_set(text)
	var name := "fallout-perf-%s.txt" % Time.get_datetime_string_from_system().replace(":", "-")
	if OS.has_feature("web"):
		JavaScriptBridge.download_buffer(text.to_utf8_buffer(), name, "text/plain")
		return "Downloaded %s (also copied)" % name
	var path := "user://" + name
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(text)
		f.close()
	return "Saved %s (also copied)" % ProjectSettings.globalize_path(path)
