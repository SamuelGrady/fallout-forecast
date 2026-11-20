extends Node
## Local one-shots and the synchronized storm score.

const MUSIC := [
	"res://assets/audio/music/music_piano.ogg",
	"res://assets/audio/music/music_bass.ogg",
	"res://assets/audio/music/music_drums.ogg",
	"res://assets/audio/music/music_lead.ogg",
	"res://assets/audio/music/music_boss.ogg",
]
const THRESHOLDS := [0.0, 0.12, 0.32, 0.58]
## Overall soundtrack level (linear). 2.0 is about +6 dB; playtests found the
## score too quiet. The Master limiter keeps peaks in check.
const MUSIC_GAIN := 2.0
## Rain bed level (linear). 0.55 is about -5 dB.
const RAIN_GAIN := 0.55
const RAIN_BUS := &"Rain"
## Mix buses. Rain sits under Ambience; Music ducks under Weapons fire.
const BUSES := [&"Music", &"Weapons", &"Threats", &"UI", &"Ambience"]
const WEAPON_CUES := ["reload", "jam", "reel_tick", "throw_bomb", "hit_enemy", "hit_flesh", "headshot", "shotgun_pump", "rifle_reload"]
const UI_CUES := ["ui_click", "pickup", "lever", "reel_land", "crate_open", "decon", "revive", "storm_countdown", "storm_arrival", "storm_clear"]
const AMBIENCE_CUES := ["downpour", "step_0", "step_1", "step_2", "step_3", "decon_spray", "dome_deploy", "dome_collapse"]
var _last_cue_ms := {}

var _layers: Array[AudioStreamPlayer] = []
var _rain: AudioStreamPlayer
var _wind: AudioStreamPlayer
var _rain_filter := AudioEffectLowPassFilter.new()
var _boss_active := false
var _rain_gain := 0.0
var _shelter_mix := 0.0
var _pressure := 0.0
var _last_phase := Vector2i(-1, -1)
var _web := OS.has_feature("web")
var _stream_cache := {}
var _active_sfx := 0
const WEB_MAX_SFX := 8


func _ready() -> void:
	for name in BUSES:
		_add_bus(name, &"Master")
	var bus := _add_bus(RAIN_BUS, &"Ambience")
	# On single-threaded Web, bus DSP effects burn main-thread audio budget and
	# cause buffer underrun crackles; keep desktop effects intact.
	if not _web:
		AudioServer.add_bus_effect(bus, _rain_filter)
		# Master limiter keeps shotgun + explosion stacks from clipping.
		AudioServer.add_bus_effect(0, AudioEffectHardLimiter.new())
		# Music ducks a few dB while guns are firing.
		var duck := AudioEffectCompressor.new()
		duck.sidechain = &"Weapons"
		duck.threshold = -26.0
		duck.ratio = 4.0
		duck.attack_us = 2000.0
		duck.release_ms = 350.0
		AudioServer.add_bus_effect(AudioServer.get_bus_index(&"Music"), duck)
	WeatherManager.phase_changed.connect(_phase_changed)


func _add_bus(bus_name: StringName, send: StringName) -> int:
	var index := AudioServer.get_bus_index(bus_name)
	if index == -1:
		index = AudioServer.bus_count
		AudioServer.add_bus()
		AudioServer.set_bus_name(index, bus_name)
	AudioServer.set_bus_send(index, send)
	return index


func bus_for(cue: String) -> StringName:
	if _web:
		return &"Master"
	if cue.begins_with("shot_") or cue.begins_with("gun_") or cue in WEAPON_CUES:
		return &"Weapons"
	if cue in UI_CUES or cue.begins_with("vcr_") or cue.begins_with("ping_"):
		return &"UI"
	if cue in AMBIENCE_CUES:
		return &"Ambience"
	return &"Threats"


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
	var wav := "res://assets/audio/sfx/%s.wav" % cue
	var path := wav if ResourceLoader.exists(wav) else "res://assets/audio/sfx/%s.ogg" % cue
	var stream := load(path) as AudioStream
	_stream_cache[cue] = stream
	return stream


func start_run() -> void:
	if Net.dedicated:
		return
	var music_bus := &"Master" if _web else &"Music"
	var rain_bus := &"Master" if _web else RAIN_BUS
	for i in MUSIC.size():
		var source: String = MUSIC[i]
		var stream := load(source).duplicate() as AudioStreamOggVorbis
		stream.loop = true
		var voice := _loop(stream, music_bus)
		# On Web, keep silent stems paused so we aren't decoding 5 OGGs at once.
		if _web and i > 0:
			voice.stream_paused = true
		_layers.append(voice)
	_rain = _loop_wav("res://assets/audio/sfx/rain.wav", rain_bus)
	if _web:
		_rain.stream_paused = true
		_wind = null
	else:
		_wind = _loop_wav("res://assets/audio/sfx/storm_wind.wav", rain_bus)


func stop_run() -> void:
	if _layers.is_empty():
		return
	for layer in _layers:
		if is_instance_valid(layer):
			layer.stop()
			layer.queue_free()
	_layers.clear()
	_boss_active = false
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
	if _web:
		voice.playback_type = AudioServer.PLAYBACK_TYPE_STREAM
	voice.volume_linear = 0.0
	add_child(voice)
	voice.play()
	return voice


func _process(delta: float) -> void:
	if _layers.is_empty():
		return
	var intensity := WeatherManager.storm_intensity
	var blend := 1.0 - exp(-3.0 * delta)
	var boss := get_tree().get_first_node_in_group("boss") != null or get_tree().get_first_node_in_group("miniboss") != null
	# Combat pressure (enemies alive) pushes the drums and lead up on top of
	# the storm layers, so a quiet Downpour and a packed one sound different.
	_pressure = lerpf(_pressure, clampf(get_tree().get_nodes_in_group("enemies").size() / 14.0, 0.0, 1.0), blend * 0.5)
	for i in THRESHOLDS.size():
		var gain := 0.0 if boss else 0.24 * smoothstep(THRESHOLDS[i], THRESHOLDS[i] + 0.2, intensity)
		if i == 0 and not boss:
			gain = 0.20
		elif i >= 2 and not boss:
			gain = maxf(gain, 0.24 * _pressure * (1.0 if i == 2 else 0.7))
		# On Web, decode at most piano + drums (skip bass & lead stems) to keep
		# single-threaded Vorbis decoding smooth without crackles.
		if _web and (i == 1 or i == 3):
			gain = 0.0
		var v := lerpf(_layers[i].volume_linear, gain * MUSIC_GAIN, blend)
		_layers[i].volume_linear = v
		if _web:
			var want_paused := v < 0.005
			if _layers[i].stream_paused != want_paused:
				_layers[i].stream_paused = want_paused
	var boss_track := _layers.back() as AudioStreamPlayer
	if boss and not _boss_active:
		if _web:
			boss_track.stream_paused = false
		boss_track.seek(0.0)
	_boss_active = boss
	var boss_vol := lerpf(boss_track.volume_linear, (0.32 * MUSIC_GAIN) if boss else 0.0, blend)
	boss_track.volume_linear = boss_vol
	if _web:
		var pause_boss := boss_vol < 0.005
		if boss_track.stream_paused != pause_boss:
			boss_track.stream_paused = pause_boss

	var player := get_tree().get_first_node_in_group("local_player")
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
		_wind.volume_linear = smoothstep(0.23, 1.0, _rain_gain) * lerpf(0.38, 0.09, _shelter_mix)


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


func play(cue: String, volume_db := -10.0, pitch := 1.0) -> void:
	if Net.dedicated:
		return
	if cue == "pickup":
		# Pickups come in bursts after a fight: one soft, varied cue at a time.
		if _recent(cue, 0.3):
			return
		volume_db -= 6.0
		pitch *= randf_range(0.92, 1.12)
	elif _web and _recent(cue, 0.045):
		return
	_play_stream(_get_sfx(cue), volume_db, pitch, bus_for(cue))


func _play_stream(stream: AudioStream, volume_db: float, pitch := 1.0, bus := &"Master") -> void:
	if stream == null:
		return
	if _web and _active_sfx >= WEB_MAX_SFX:
		return
	var voice := AudioStreamPlayer.new()
	voice.stream = stream
	voice.volume_db = volume_db
	voice.pitch_scale = pitch
	voice.bus = bus
	if _web:
		voice.playback_type = AudioServer.PLAYBACK_TYPE_STREAM
		_active_sfx += 1
		voice.tree_exited.connect(func(): _active_sfx = maxi(0, _active_sfx - 1))
	add_child(voice)
	voice.finished.connect(voice.queue_free)
	voice.play()


func play_at(cue: String, position: Vector3, volume_db := -6.0, pitch := 1.0) -> void:
	if Net.dedicated:
		return
	if cue == "pickup" and _recent(cue, 0.3):
		return
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
		_play_stream(_get_sfx(cue), volume_db + atten, pitch, &"Master")
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
	world.add_child(voice)
	voice.global_position = position
	voice.finished.connect(voice.queue_free)
	voice.play()
