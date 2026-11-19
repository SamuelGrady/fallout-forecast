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

var _layers: Array[AudioStreamPlayer] = []
var _rain: AudioStreamPlayer
var _rain_filter := AudioEffectLowPassFilter.new()
var _boss_active := false
var _rain_gain := 0.0
var _shelter_mix := 0.0


func _ready() -> void:
	var bus := AudioServer.bus_count
	AudioServer.add_bus()
	AudioServer.set_bus_name(bus, RAIN_BUS)
	AudioServer.add_bus_effect(bus, _rain_filter)
	WeatherManager.phase_changed.connect(_phase_changed)


func start_run() -> void:
	for source in MUSIC:
		var stream := load(source).duplicate() as AudioStreamOggVorbis
		stream.loop = true
		_layers.append(_loop(stream))
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
	_rain_filter.cutoff_hz = lerpf(16000.0, 650.0, _shelter_mix)
	_rain.volume_linear = _rain_gain * lerpf(0.4, 0.23, _shelter_mix)


func _phase_changed(phase: int, _wave: int) -> void:
	if phase == WeatherManager.Phase.DOWNPOUR and _rain:
		_play_stream(load("res://assets/audio/sfx/downpour.wav") as AudioStream, -8.0)


func play(cue: String, volume_db := -10.0) -> void:
	_play_stream(load("res://assets/audio/sfx/%s.ogg" % cue) as AudioStream, volume_db)


func _play_stream(stream: AudioStream, volume_db: float) -> void:
	var voice := AudioStreamPlayer.new()
	voice.stream = stream
	voice.volume_db = volume_db
	add_child(voice)
	voice.finished.connect(voice.queue_free)
	voice.play()


func play_at(cue: String, position: Vector3, volume_db := -6.0) -> void:
	var world := get_tree().current_scene
	if not world:
		return
	var voice := AudioStreamPlayer3D.new()
	voice.stream = load("res://assets/audio/sfx/%s.ogg" % cue) as AudioStream
	voice.volume_db = volume_db
	voice.max_distance = 45.0
	world.add_child(voice)
	voice.global_position = position
	voice.finished.connect(voice.queue_free)
	voice.play()
