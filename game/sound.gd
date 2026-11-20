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
const RAIN_BUS := &"Rain"
## Mix buses. Rain sits under Ambience; Music ducks under Weapons fire.
const BUSES := [&"Music", &"Weapons", &"Threats", &"UI", &"Ambience"]
const WEAPON_CUES := ["reload", "jam", "reel_tick", "throw_bomb", "hit_enemy", "headshot"]
const UI_CUES := ["ui_click", "pickup", "lever", "reel_land", "crate_open", "decon", "revive"]
const AMBIENCE_CUES := ["downpour", "step_0", "step_1", "step_2", "step_3"]
var _last_cue_ms := {}

var _layers: Array[AudioStreamPlayer] = []
var _rain: AudioStreamPlayer
var _rain_filter := AudioEffectLowPassFilter.new()
var _boss_active := false
var _rain_gain := 0.0
var _shelter_mix := 0.0


func _ready() -> void:
	for name in BUSES:
		_add_bus(name, &"Master")
	var bus := _add_bus(RAIN_BUS, &"Ambience")
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
	if cue.begins_with("shot_") or cue in WEAPON_CUES:
		return &"Weapons"
	if cue in UI_CUES:
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


func start_run() -> void:
	for source in MUSIC:
		var stream := load(source).duplicate() as AudioStreamOggVorbis
		stream.loop = true
		_layers.append(_loop(stream, &"Music"))
	var rain_stream := load("res://assets/audio/sfx/rain.wav").duplicate() as AudioStreamWAV
	rain_stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	rain_stream.loop_end = roundi(rain_stream.get_length() * rain_stream.mix_rate)
	_rain = _loop(rain_stream, RAIN_BUS)


func stop_run() -> void:
	for layer in _layers:
		layer.stop()
		layer.queue_free()
	_layers.clear()
	_boss_active = false
	_rain.stop()
	_rain.queue_free()
	_rain = null
	_rain_gain = 0.0
	_shelter_mix = 0.0


func _loop(stream: AudioStream, bus := &"Master") -> AudioStreamPlayer:
	var voice := AudioStreamPlayer.new()
	voice.stream = stream
	voice.bus = bus
	voice.volume_linear = 0.0
	add_child(voice)
	voice.play()
	return voice


func _process(delta: float) -> void:
	if _layers.is_empty():
		return
	var intensity := WeatherManager.storm_intensity
	var blend := 1.0 - exp(-3.0 * delta)
	var boss := get_tree().get_first_node_in_group("boss") != null
	for i in THRESHOLDS.size():
		var gain := 0.0 if boss else 0.24 * smoothstep(THRESHOLDS[i], THRESHOLDS[i] + 0.2, intensity)
		if i == 0 and not boss:
			gain = 0.20
		_layers[i].volume_linear = lerpf(_layers[i].volume_linear, gain, blend)
	var boss_track := _layers.back() as AudioStreamPlayer
	if boss and not _boss_active:
		boss_track.seek(0.0)
	_boss_active = boss
	boss_track.volume_linear = lerpf(boss_track.volume_linear, 0.32 if boss else 0.0, blend)

	var player := get_tree().get_first_node_in_group("local_player")
	_shelter_mix = lerpf(_shelter_mix, 1.0 if player and player.get("sheltered") else 0.0, blend)
	_rain_gain = lerpf(_rain_gain, intensity, blend)
	# Under a roof the rain should still be there, just dull and close.
	_rain_filter.cutoff_hz = lerpf(16000.0, 1500.0, _shelter_mix)
	_rain.volume_linear = _rain_gain * lerpf(0.4, 0.32, _shelter_mix)


func _phase_changed(phase: int, _wave: int) -> void:
	if phase == WeatherManager.Phase.DOWNPOUR and _rain:
		_play_stream(load("res://assets/audio/sfx/downpour.wav") as AudioStream, -8.0, 1.0, &"Ambience")


func play(cue: String, volume_db := -10.0, pitch := 1.0) -> void:
	if cue == "pickup":
		# Pickups come in bursts after a fight: one soft, varied cue at a time.
		if _recent(cue, 0.3):
			return
		volume_db -= 6.0
		pitch *= randf_range(0.92, 1.12)
	var extension := "wav" if cue in ["player_hurt", "headshot"] else "ogg"
	_play_stream(load("res://assets/audio/sfx/%s.%s" % [cue, extension]) as AudioStream, volume_db, pitch, bus_for(cue))


func _play_stream(stream: AudioStream, volume_db: float, pitch := 1.0, bus := &"Master") -> void:
	var voice := AudioStreamPlayer.new()
	voice.stream = stream
	voice.volume_db = volume_db
	voice.pitch_scale = pitch
	voice.bus = bus
	add_child(voice)
	voice.finished.connect(voice.queue_free)
	voice.play()


func play_at(cue: String, position: Vector3, volume_db := -6.0, pitch := 1.0) -> void:
	var world := get_tree().current_scene
	if not world:
		return
	var voice := AudioStreamPlayer3D.new()
	voice.stream = load("res://assets/audio/sfx/%s.ogg" % cue) as AudioStream
	if cue == "pickup" and _recent(cue, 0.3):
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
