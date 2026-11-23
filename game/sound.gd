extends Node
## Local one-shots and the synchronized storm score.

const SCORE := ["forecast_theme", "forecast_pulse", "forecast_storm", "forecast_boss"]
const RAIN_GAIN := 0.50
const RAIN_BUS := &"Rain"
## Mix buses. Rain sits under Ambience; Music ducks under Weapons fire.
const BUSES := [&"Music", &"Weapons", &"Threats", &"UI", &"Ambience"]
const UI_CUES := ["pickup", "lever", "reel_land", "crate_open", "decon", "revive", "storm_countdown",
	"storm_arrival", "storm_clear", "incoming_group", "suit_beep", "kill_confirm", "multikill", "vhs_glitch"]
const AMBIENCE_CUES := ["downpour", "decon_spray", "dome_deploy", "dome_collapse"]
const CUE_SOURCE := {"ui_focus": "reel_tick", "ui_tick": "reel_tick"}
## Source-level trims measured from the decoded files, before local/3D gains.
const CUE_TRIM_DB := {
	"ui_click": -4.0, "ui_focus": -2.0,
	"gun_shotgun": -4.0, "gun_revolver": -3.0, "gun_rifle": -1.0,
	"shot_shotgun": -7.0, "shot_nailgun": -7.0, "shot_rifle": 2.0,
	"explosion": -3.0, "explosion_big": -3.0, "hit_flesh": -4.0, "reload": -4.0,
	"turned": -4.0, "decon_spray": -3.0, "dome_deploy": -3.0, "dome_collapse": -3.0,
	"downpour": -3.0, "storm_clear": -4.0, "storm_arrival": -2.0, "storm_countdown": -2.0,
	"drip_windup": -2.0, "gutter_windup": -2.0, "gutter_skid": -2.0, "mister_windup": -2.0,
	"hailstone_crash": -3.0, "undertow_lurk": -2.0, "smog_spit": -2.0, "smog_splash": 2.0,
	"static_blink": 1.0, "thunderhead_fuse": -2.0, "thunder": 0.0,
	"vcr_insert": -5.0, "vcr_eject": -2.0, "vcr_whirr": 1.0,
}
## Per-cue ceiling overrides for cue_gain (default -10 dB). Thunder has to
## cut through rain, wind and the score, so it may play much hotter.
const CUE_CAP_DB := {"thunder": -1.0}
var _last_cue_ms := {}

var _layers: Array[AudioStreamPlayer] = []
var _rain: AudioStreamPlayer
var _wind: AudioStreamPlayer
var _rain_filter := AudioEffectLowPassFilter.new()
var _in_run := false
var _rain_gain := 0.0
var _shelter_mix := 0.0
var _pressure := 0.0
var _last_phase := Vector2i(-1, -1)
var _web := OS.has_feature("web")
var _headless := DisplayServer.get_name() == "headless"
var _stream_cache := {}
var _active_sfx := 0
const WEB_MAX_SFX := 8


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for name in BUSES:
		_add_bus(name, &"Master")
	var bus := _add_bus(RAIN_BUS, &"Ambience")
	# On single-threaded Web, bus DSP effects burn main-thread audio budget and
	# cause buffer underrun crackles; keep desktop effects intact.
	if not _web:
		AudioServer.add_bus_effect(bus, _rain_filter)
		# Master limiter keeps shotgun + explosion stacks from clipping.
		var limiter := AudioEffectHardLimiter.new()
		limiter.ceiling_db = -1.5
		AudioServer.add_bus_effect(0, limiter)
		# Music ducks a few dB while guns are firing.
		var duck := AudioEffectCompressor.new()
		duck.sidechain = &"Weapons"
		duck.threshold = -19.0
		duck.ratio = 2.5
		duck.mix = 0.45
		duck.attack_us = 5000.0
		duck.release_ms = 260.0
		AudioServer.add_bus_effect(AudioServer.get_bus_index(&"Music"), duck)
	WeatherManager.phase_changed.connect(_phase_changed)
	if not _headless and not Net.dedicated:
		_start_score.call_deferred()


func _add_bus(bus_name: StringName, send: StringName) -> int:
	var index := AudioServer.get_bus_index(bus_name)
	if index == -1:
		index = AudioServer.bus_count
		AudioServer.add_bus()
		AudioServer.set_bus_name(index, bus_name)
	AudioServer.set_bus_send(index, send)
	return index


func bus_for(cue: String) -> StringName:
	if _is_fire(cue):
		return &"Weapons"
	if cue in UI_CUES or cue.begins_with("ui_") or cue.begins_with("vcr_") or cue.begins_with("ping_"):
		return &"UI"
	if cue in AMBIENCE_CUES or cue.begins_with("step_") or cue.begins_with("splash_"):
		return &"Ambience"
	return &"Threats"


func _is_fire(cue: String) -> bool:
	return cue.begins_with("shot_") or cue.begins_with("gun_") or cue == "throw_bomb"


func cue_gain(cue: String, volume_db: float) -> float:
	return minf(volume_db + float(CUE_TRIM_DB.get(cue, 0.0)), float(CUE_CAP_DB.get(cue, -10.0)))


func ui_focus() -> void:
	if not _recent("ui_focus", 0.08):
		play("ui_focus", -20.0, 1.35)


## True if this cue played within min_gap seconds (for spammy pickups).
func _recent(cue: String, min_gap: float) -> bool:
	var now := Time.get_ticks_msec()
	if now - int(_last_cue_ms.get(cue, -100000)) < int(min_gap * 1000.0):
		return true
	_last_cue_ms[cue] = now
	return false


func _get_sfx(cue: String) -> AudioStream:
	if _stream_cache.has(cue):
		return _stream_cache[cue]
	var file: String = CUE_SOURCE.get(cue, cue)
	var wav := "res://assets/audio/sfx/%s.wav" % file
	var path := wav if ResourceLoader.exists(wav) else "res://assets/audio/sfx/%s.ogg" % file
	var stream := load(path) as AudioStream if ResourceLoader.exists(path) else null
	if stream == null:
		push_warning("Sound: missing cue " + cue)
	_stream_cache[cue] = stream
	return stream


func _start_score() -> void:
	for name in SCORE:
		_layers.append(_loop_wav("res://assets/audio/music/%s.wav" % name, &"Music"))


func start_run() -> void:
	if Net.dedicated or _headless or _in_run:
		return
	_in_run = true
	var rain_bus := RAIN_BUS
	_rain = _loop_wav("res://assets/audio/sfx/rain.wav", rain_bus)
	if _web:
		_rain.stream_paused = true
		_wind = null
	else:
		_wind = _loop_wav("res://assets/audio/sfx/storm_wind.wav", rain_bus)


func stop_run() -> void:
	_in_run = false
	for voice in [_rain, _wind]:
		if is_instance_valid(voice):
			voice.stop()
			voice.queue_free()
	_rain = null
	_wind = null
	_rain_gain = 0.0
	_shelter_mix = 0.0
	_pressure = 0.0
	_last_phase = Vector2i(-1, -1)


func _loop_wav(path: String, bus: StringName) -> AudioStreamPlayer:
	var stream := load(path).duplicate() as AudioStreamWAV
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_end = roundi(stream.get_length() * stream.mix_rate)
	return _loop(stream, bus)


func _loop(stream: AudioStream, bus := &"Master") -> AudioStreamPlayer:
	var voice := AudioStreamPlayer.new()
	voice.stream = stream
	voice.bus = bus
	voice.process_mode = Node.PROCESS_MODE_ALWAYS if bus == &"Music" else Node.PROCESS_MODE_PAUSABLE
	if _web:
		voice.playback_type = AudioServer.PLAYBACK_TYPE_SAMPLE if bus == &"Music" else AudioServer.PLAYBACK_TYPE_STREAM
	voice.volume_linear = 0.0
	add_child(voice)
	voice.play()
	return voice


func _process(delta: float) -> void:
	if _layers.is_empty():
		return
	var blend := 1.0 - exp(-2.5 * delta / maxf(Engine.time_scale, 0.001))
	var intensity := WeatherManager.storm_intensity
	var player := get_tree().get_first_node_in_group("local_player")
	var danger := 0.0
	var boss := false
	if _in_run:
		boss = get_tree().get_first_node_in_group("boss") != null or get_tree().get_first_node_in_group("miniboss") != null
		danger = clampf(get_tree().get_node_count_in_group("enemies") / 13.0, 0.0, 1.0)
		if player and (player.state == "downed" or player.health <= 30.0):
			danger = maxf(danger, 0.72)
	_pressure = lerpf(_pressure, danger, blend * 0.52)
	var activity := maxf(intensity if _in_run else 0.0, _pressure)
	var gains := [
		0.68 if _in_run else 0.78,
		lerpf(0.30, 0.78, activity) if _in_run else 0.18,
		smoothstep(0.18, 0.86, activity) * (0.42 if boss else 0.80),
		0.82 if boss else 0.0,
	]
	var overlay_mix := 0.47 if get_tree().paused else 1.0
	for i in _layers.size():
		_layers[i].volume_linear = lerpf(_layers[i].volume_linear, gains[i] * overlay_mix, blend)
	if not _in_run or get_tree().paused:
		return

	_shelter_mix = lerpf(_shelter_mix, 1.0 if player and player.get("sheltered") else 0.0, blend)
	_rain_gain = lerpf(_rain_gain, intensity, blend)
	# Under a roof the rain should still be there, just dull and close.
	if not _web:
		_rain_filter.cutoff_hz = lerpf(16000.0, 1500.0, _shelter_mix)
	if _rain:
		var rvol := _rain_gain * lerpf(0.4, 0.22 if _web else 0.32, _shelter_mix) * RAIN_GAIN
		_rain.volume_linear = rvol
		if _web:
			var pause_rain := rvol < 0.005
			if _rain.stream_paused != pause_rain:
				_rain.stream_paused = pause_rain
	if _wind:
		_wind.volume_linear = smoothstep(0.23, 1.0, _rain_gain) * lerpf(0.27, 0.09, _shelter_mix)


func _phase_changed(phase: int, wave: int) -> void:
	var transition := Vector2i(phase, wave)
	if _rain == null or transition == _last_phase:
		return
	_last_phase = transition
	match phase:
		WeatherManager.Phase.DRIZZLE:
			play("storm_arrival", -13.0)
		WeatherManager.Phase.DOWNPOUR:
			play("downpour", -7.0)
		WeatherManager.Phase.CLEARING:
			play("storm_clear", -12.0)


## Cues played at least once (first plays load the file: worth a Perf mark).
var _played := {}


func _first_play(cue: String) -> void:
	if not _played.has(cue):
		_played[cue] = true
		Perf.mark("first sound " + cue)


func play(cue: String, volume_db := -10.0, pitch := 1.0) -> void:
	if Net.dedicated or _headless:
		return
	_first_play(cue)
	if cue == "pickup":
		# Pickups come in bursts after a fight: one soft, varied cue at a time.
		if _recent(cue, 0.3):
			return
		volume_db -= 6.0
		pitch *= randf_range(0.92, 1.12)
	elif _web and cue != "ui_focus" and _recent(cue, 0.045):
		return
	if _web and _is_fire(cue):
		Juice.duck_music(-3.0, 0.13)
	_play_stream(_get_sfx(cue), cue_gain(cue, volume_db), pitch, bus_for(cue))


## Thunder for a lightning strike. Its own player per strike (overlaps are
## fine), always STREAM playback on Web (the QOA-compressed WAV must not use
## sample playback), and never dropped by the Web voice cap or cue dedupe.
func play_thunder(volume_db := -1.0, pitch := 1.0) -> void:
	if Net.dedicated or _headless:
		return
	_first_play("thunder")
	var cue := "thunder_web" if _web else "thunder"
	var stream := _get_sfx(cue)
	if stream == null:
		stream = _get_sfx("thunder")
	Juice.duck_music(-7.0, 1.4)
	_play_stream(stream, cue_gain("thunder", volume_db), pitch, &"Ambience", true)
	Perf.mark("thunder playback")


func _play_stream(stream: AudioStream, volume_db: float, pitch := 1.0, bus := &"Master", priority := false) -> void:
	if stream == null:
		return
	if _web and _active_sfx >= WEB_MAX_SFX and not priority:
		return
	var voice := AudioStreamPlayer.new()
	voice.stream = stream
	voice.volume_db = volume_db
	voice.pitch_scale = pitch
	voice.bus = bus
	voice.process_mode = Node.PROCESS_MODE_ALWAYS if bus == &"UI" else Node.PROCESS_MODE_PAUSABLE
	if _web:
		voice.playback_type = AudioServer.PLAYBACK_TYPE_STREAM
		_active_sfx += 1
		voice.tree_exited.connect(func(): _active_sfx = maxi(0, _active_sfx - 1))
	add_child(voice)
	voice.finished.connect(voice.queue_free)
	voice.play()


func play_at(cue: String, position: Vector3, volume_db := -6.0, pitch := 1.0) -> void:
	if Net.dedicated or _headless:
		return
	_first_play(cue)
	if cue == "pickup" and _recent(cue, 0.3):
		return
	volume_db = cue_gain(cue, volume_db)
	if _web:
		if _active_sfx >= WEB_MAX_SFX or _recent(cue, 0.06):
			return
		# On Web, approximate 3D distance attenuation in a lightweight 2D stream
		# to avoid expensive WebGL/WASM HRTF/spatial mixing overhead.
		var cam := get_viewport().get_camera_3d()
		var atten := 0.0
		if cam:
			var d := cam.global_position.distance_to(position)
			if d > 42.0:
				return
			atten = -clampf(d * 0.45, 0.0, 22.0)
		_play_stream(_get_sfx(cue), volume_db + atten, pitch, bus_for(cue))
		return
	var world := get_tree().current_scene
	if not world:
		return
	var voice := AudioStreamPlayer3D.new()
	voice.stream = _get_sfx(cue)
	if voice.stream == null:
		voice.free()
		return
	voice.volume_db = volume_db
	voice.pitch_scale = pitch
	voice.bus = bus_for(cue)
	voice.max_distance = 45.0
	# Distant sounds lose their highs (built-in air absorption), so a
	# teammate's gunfire down the street sounds far away.
	voice.attenuation_filter_cutoff_hz = 2800.0
	voice.attenuation_filter_db = -14.0
	world.add_child(voice)
	voice.global_position = position
	voice.finished.connect(voice.queue_free)
	voice.play()
