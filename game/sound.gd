extends Node
## Local one-shots and the synchronized storm score.

const SCORE := ["forecast_theme", "forecast_pulse", "forecast_storm", "forecast_boss"]
const RAIN_GAIN := 0.50
const RAIN_BUS := &"Rain"
## Rain sits under Ambience; Weapons feeds the desktop Music sidechain.
const BUSES := [&"Music", &"Weapons", &"Threats", &"UI", &"Ambience", &"Foley"]
const UI_CUES := ["pickup", "lever", "reel_land", "crate_open", "decon", "revive", "storm_countdown",
	"storm_arrival", "storm_clear", "incoming_group", "suit_beep", "kill_confirm", "multikill",
	"vhs_glitch", "gun_supply_drop"]
const AMBIENCE_CUES := ["downpour", "decon_spray", "dome_deploy", "dome_collapse",
	"gun_dome_expand", "gun_bleach_burst", "gun_field_deploy", "gun_flare"]
const FOLEY_CUES := ["reload", "rifle_reload", "shotgun_pump", "jam",
	"gun_frag_throw", "gun_dome_throw", "gun_umbrella", "gun_umbrella_open",
	"gun_bleach_bomb", "gun_bait_radio", "gun_bait_activate", "gun_sandbag",
	"gun_lightning_rod", "gun_med_tin", "gun_suit_patch"]
const NON_FIRE_GUN_CUES := [
	"gun_frag_throw", "gun_frag_blast", "gun_dome_throw", "gun_dome_expand",
	"gun_umbrella", "gun_umbrella_open", "gun_bleach_bomb", "gun_bleach_burst",
	"gun_bait_radio", "gun_bait_activate", "gun_sandbag", "gun_lightning_rod",
	"gun_med_tin", "gun_suit_patch", "gun_flare", "gun_field_deploy",
	"gun_supply_drop", "gun_bait_loop", "gun_disruptor_charge",
]
const ATTACK_TELLS := ["drip_windup", "gutter_windup", "mister_windup", "sleet_leap",
	"hailstone_charge", "smog_spit", "static_shock", "undertow_emerge", "thunderhead_fuse"]
const PLAYER_ALERTS := ["player_hurt", "downed", "turned", "revive", "suit_beep", "ping_revive", "ping_danger"]
const CUE_SOURCE := {"ui_focus": "reel_tick", "ui_tick": "reel_tick"}
## Source-level trims measured from the decoded files, before local/3D gains.
const CUE_TRIM_DB := {
	"ui_click": -4.0, "ui_focus": -2.0,
	"gun_shotgun": -2.0, "gun_revolver": 1.0, "gun_rifle": -2.0,
	"gun_boombox_launcher": -1.5, "gun_leaky_nailgun": -0.5, "gun_lucky_penny_revolver": 0.5,
	"gun_nail_driver": 4.0, "gun_hunting_rifle": 3.5, "gun_harpoon": 4.5,
	"gun_battery_zapper": 4.5, "gun_flare_launcher": 3.5, "gun_rock_salt": 3.0,
	"gun_leaf_blower": 2.5, "gun_pressure_washer": 2.0, "gun_disruptor": 2.5,
	"gun_frag_throw": 0.0, "gun_frag_blast": -3.0, "gun_dome_throw": 0.0,
	"gun_dome_expand": -3.0, "gun_umbrella_open": -2.5, "gun_bleach_burst": -2.5,
	"gun_bait_activate": -1.0,
	"shot_shotgun": -1.5, "shot_nailgun": 1.5, "shot_rifle": 2.5, "shot_boombox": 0.0,
	"explosion": -3.0, "explosion_big": -3.0, "hit_flesh": -4.0, "reload": -4.0,
	"turned": -4.0, "decon_spray": -3.0, "dome_deploy": -3.0, "dome_collapse": -3.0,
	"downpour": -3.0, "storm_clear": -4.0, "storm_arrival": -2.0, "storm_countdown": -2.0,
	"drip_windup": 3.0, "gutter_windup": 5.0, "gutter_skid": -2.0, "mister_windup": 5.0,
	"sleet_leap": 2.0, "hailstone_crash": -3.0, "undertow_lurk": -2.0, "smog_spit": 2.0,
	"smog_splash": 2.0, "static_blink": 1.0, "thunderhead_fuse": -2.0, "thunder": 0.0,
	"player_hurt": 1.0,
	"vcr_insert": -5.0, "vcr_eject": -2.0, "vcr_whirr": 1.0,
}
## Per-cue ceiling overrides for cue_gain (default -10 dB; weapon fire and
## thunder must cut cleanly through rain, wind and the darksynth score).
const CUE_CAP_DB := {"thunder": -1.0, "player_hurt": -7.0}
const WEAPON_CAP_DB := -1.0
const CLOSE_TELL_M := 12.0
const TELL_HOLD := 0.32
var _last_cue_ms := {}

## Combat heat (0-1): spikes fast on hits, kills, gunfire, explosions and
## player damage, holds briefly, then decays over ~5 s once the fight quiets.
## Nearby/total enemies, low health and the storm hold a floor under it.
const HEAT_HIT := 0.28
const HEAT_KILL := 0.45
const HEAT_FIRE := 0.18
const HEAT_CUES := {"explosion": 0.35, "explosion_big": 0.35, "gun_frag_blast": 0.35, "hit_flesh": 0.30, "suit_beep": 0.20}
const HEAT_HOLD := 1.0
const HEAT_DECAY := 0.22
const NEAR_ENEMY_M := 22.0
## Music energy attack/release rates (1/s): ~0.5 s up, ~3.5 s down, fast calm-down after wave clear.
const ATTACK_RATE := 6.0
const RELEASE_RATE := 0.85
const CALM_RELEASE_RATE := 2.6
var _combat_heat := 0.0
var _heat_hold := 0.0
var _heat := 0.0
var _storm := 0.0
var _boss_mix := 0.0
var _swarm_floor := 0.0
var _scan_left := 0.0

var _layers: Array[AudioStreamPlayer] = []
var _rain: AudioStreamPlayer
var _wind: AudioStreamPlayer
var _rain_filter := AudioEffectLowPassFilter.new()
var _in_run := false
var _rain_gain := 0.0
var _shelter_mix := 0.0
var _tell_left := 0.0
var _tell_mix := 0.0
var _last_phase := Vector2i(-1, -1)
var _web := OS.has_feature("web")
var _headless := DisplayServer.get_name() == "headless"
var _stream_cache := {}

enum WebPriority { BACKGROUND, STANDARD, ACTION, FOREGROUND }
const WEB_MAX_SFX := 8
const WEB_BACKGROUND_LIMIT := 5
var _web_voices: Dictionary[AudioStreamPlayer, int] = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for name in BUSES:
		_add_bus(name, &"Master")
	var bus := _add_bus(RAIN_BUS, &"Ambience")
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index(&"Foley"), -2.0)
	# On single-threaded Web, bus DSP effects burn main-thread audio budget and
	# cause buffer underrun crackles; keep desktop effects intact.
	if not _web:
		AudioServer.add_bus_effect(bus, _rain_filter)
		# Master limiter keeps shotgun + explosion stacks from clipping.
		var limiter := AudioEffectHardLimiter.new()
		limiter.ceiling_db = -1.5
		AudioServer.add_bus_effect(0, limiter)
		# Music ducks while guns are firing so shots always read clearly.
		var duck := AudioEffectCompressor.new()
		duck.sidechain = &"Weapons"
		duck.threshold = -22.0
		duck.ratio = 3.0
		duck.mix = 0.42
		duck.attack_us = 3000.0
		duck.release_ms = 220.0
		AudioServer.add_bus_effect(AudioServer.get_bus_index(&"Music"), duck)
	else:
		# Leave room for stacked attacks on the Web mixer without desktop DSP.
		AudioServer.set_bus_volume_db(AudioServer.get_bus_index(&"Weapons"), -3.0)
	WeatherManager.phase_changed.connect(_phase_changed)
	# GameManager is a later autoload: connect once the whole tree is up.
	(func(): GameManager.combat_hit.connect(_on_combat_hit)).call_deferred()
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
	if cue in FOLEY_CUES or cue.begins_with("step_") or cue.begins_with("splash_") \
			or cue.begins_with("casing_") or cue.begins_with("impact_"):
		return &"Foley"
	if cue in AMBIENCE_CUES:
		return &"Ambience"
	return &"Threats"


func _is_fire(cue: String) -> bool:
	if cue in NON_FIRE_GUN_CUES:
		return false
	return cue.begins_with("shot_") or cue.begins_with("gun_") or cue == "throw_bomb"


func cue_gain(cue: String, volume_db: float) -> float:
	var default_cap := WEAPON_CAP_DB if _is_fire(cue) else -10.0
	if cue in ATTACK_TELLS:
		default_cap = -6.0
	return minf(volume_db + float(CUE_TRIM_DB.get(cue, 0.0)), float(CUE_CAP_DB.get(cue, default_cap)))


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
	_tell_left = 0.0
	_tell_mix = 0.0
	_combat_heat = 0.0
	_heat_hold = 0.0
	_swarm_floor = 0.0
	_heat = 0.0
	_storm = 0.0
	_boss_mix = 0.0
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
	var real := delta / maxf(Engine.time_scale, 0.001)
	var blend := 1.0 - exp(-2.5 * real)
	var intensity := WeatherManager.storm_intensity
	var player := get_tree().get_first_node_in_group("local_player")
	var paused := get_tree().paused
	_tell_left = maxf(0.0, _tell_left - real)
	var tell_active := _tell_left > 0.0 and not paused
	_tell_mix = lerpf(_tell_mix, 1.0 if tell_active else 0.0, 1.0 - exp(-(24.0 if tell_active else 7.0) * real))
	var gains := [0.72, 0.18, 0.0, 0.0]
	if _in_run:
		var boss := get_tree().get_first_node_in_group("boss") != null or get_tree().get_first_node_in_group("miniboss") != null
		if not paused:
			_update_heat(real, player, boss)
		var e := maxf(_heat, _storm)
		var storm_layer := maxf(clampf((_heat - 0.08) / 0.35, 0.0, 1.0), clampf((_storm - 0.05) / 0.45, 0.0, 1.0))
		var overdrive := 0.55 * smoothstep(0.72, 0.95, _heat) * smoothstep(0.55, 0.7, _storm)
		var boss_rate := 4.0 if boss else (3.0 if _is_calm_phase() else 1.5)
		_boss_mix = lerpf(_boss_mix, 0.95 if boss else overdrive, 1.0 - exp(-boss_rate * real))
		gains = [
			lerpf(0.58, 0.34, e),
			lerpf(0.06, 0.95, smoothstep(0.03, 0.3, e)),
			storm_layer,
			_boss_mix,
		]
	var overlay_mix := 0.47 if paused else lerpf(1.0, 0.66, _tell_mix)
	for i in _layers.size():
		var goal: float = gains[i] * overlay_mix
		var rate := 8.0 if goal > _layers[i].volume_linear else 3.0
		_layers[i].volume_linear = lerpf(_layers[i].volume_linear, goal, 1.0 - exp(-rate * real))
	if not _in_run or paused:
		return

	_shelter_mix = lerpf(_shelter_mix, 1.0 if player and player.get("sheltered") else 0.0, blend)
	_rain_gain = lerpf(_rain_gain, intensity, blend)
	# Under a roof the rain should still be there, just dull and close.
	if not _web:
		_rain_filter.cutoff_hz = lerpf(16000.0, 1500.0, _shelter_mix)
	if _rain:
		var rvol := _rain_gain * lerpf(0.4, 0.22 if _web else 0.32, _shelter_mix) * RAIN_GAIN * lerpf(1.0, 0.68, _tell_mix)
		_rain.volume_linear = rvol
		if _web:
			var pause_rain := rvol < 0.005
			if _rain.stream_paused != pause_rain:
				_rain.stream_paused = pause_rain
	if _wind:
		_wind.volume_linear = smoothstep(0.23, 1.0, _rain_gain) * lerpf(0.27, 0.09, _shelter_mix) * lerpf(1.0, 0.68, _tell_mix)


func _is_calm_phase() -> bool:
	return WeatherManager.phase in [WeatherManager.Phase.CALM, WeatherManager.Phase.CLEARING, WeatherManager.Phase.MUTATION_ROLL]


## Raw combat heat plus its floors (swarm, low health, boss), then the
## smoothed heat/storm drives with a fast attack and a slow release.
func _update_heat(real: float, player: Node, boss: bool) -> void:
	_heat_hold -= real
	if _heat_hold <= 0.0:
		_combat_heat = maxf(0.0, _combat_heat - HEAT_DECAY * real)
	_scan_left -= real
	if _scan_left <= 0.0:
		_scan_left = 0.15
		var enemies := get_tree().get_nodes_in_group("enemies")
		var near := 0
		if player is Node3D:
			var origin: Vector3 = player.global_position
			for enemy in enemies:
				if enemy is Node3D and origin.distance_squared_to(enemy.global_position) < NEAR_ENEMY_M * NEAR_ENEMY_M:
					near += 1
		_swarm_floor = maxf(clampf(enemies.size() / 7.0, 0.0, 1.0) * 0.8, clampf(near / 3.0, 0.0, 1.0))
	var wave_clear := _is_calm_phase() and _swarm_floor <= 0.0 and not boss
	if wave_clear:
		_combat_heat = 0.0
		_heat_hold = 0.0
	var target := maxf(_combat_heat, _swarm_floor)
	if not wave_clear and player and (player.state == "downed" or player.health <= 30.0):
		target = maxf(target, 0.85)
	if boss:
		target = maxf(target, 0.7)
	var release := CALM_RELEASE_RATE if wave_clear else RELEASE_RATE
	_heat = _ramp(_heat, target, real, release)
	_storm = _ramp(_storm, _storm_drive(), real, release)


func _ramp(current: float, target: float, real: float, release := RELEASE_RATE) -> float:
	var rate := ATTACK_RATE if target > current else release
	return lerpf(current, target, 1.0 - exp(-rate * real))


## Storm energy: the phase's target as soon as it starts (storm_intensity
## eases in slowly), Acid Storm on the final wave and beyond; 0 once it ends.
func _storm_drive() -> float:
	if not WeatherManager.is_storm_active():
		return 0.0
	var target := 0.0
	match WeatherManager.phase:
		WeatherManager.Phase.DRIZZLE:
			target = 0.3
		WeatherManager.Phase.DOWNPOUR:
			target = 1.0 if WeatherManager.wave >= WeatherManager.FINAL_WAVE else 0.7
	return maxf(target, WeatherManager.storm_intensity)


func add_combat_heat(amount: float) -> void:
	if not _in_run:
		return
	if _is_calm_phase() and get_tree().get_node_count_in_group("enemies") == 0 \
			and get_tree().get_first_node_in_group("boss") == null:
		return
	_combat_heat = minf(1.0, _combat_heat + amount)
	_heat_hold = HEAT_HOLD


func _on_combat_hit(killed: bool, _critical: bool) -> void:
	add_combat_heat(HEAT_KILL if killed else HEAT_HIT)


func _heat_for_cue(cue: String) -> void:
	if _is_fire(cue):
		add_combat_heat(HEAT_FIRE)
	elif HEAT_CUES.has(cue):
		add_combat_heat(float(HEAT_CUES[cue]))


func _phase_changed(phase: int, wave: int) -> void:
	var transition := Vector2i(phase, wave)
	if _rain == null or transition == _last_phase:
		return
	_last_phase = transition
	match phase:
		WeatherManager.Phase.CALM:
			_combat_heat = 0.0
			_heat_hold = 0.0
			_swarm_floor = 0.0
		WeatherManager.Phase.DRIZZLE:
			play("storm_arrival", -13.0)
		WeatherManager.Phase.DOWNPOUR:
			play("downpour", -7.0)
		WeatherManager.Phase.CLEARING:
			_combat_heat = 0.0
			_heat_hold = 0.0
			_swarm_floor = 0.0
			play("storm_clear", -12.0)


## Cues played at least once (first plays load the file: worth a Perf mark).
var _played := {}


func _first_play(cue: String) -> void:
	if not _played.has(cue):
		_played[cue] = true
		Perf.mark("first sound " + cue)


func play(cue: String, volume_db := -10.0, pitch := 1.0) -> void:
	if Net.thin_server:
		Net.thin_server.record_sound(cue, null)
	if Net.dedicated or _headless:
		return
	_first_play(cue)
	_heat_for_cue(cue)
	var is_fire := _is_fire(cue)
	if cue == "pickup":
		# Pickups come in bursts after a fight: one soft, varied cue at a time.
		if _recent(cue, 0.3):
			return
		volume_db -= 6.0
		pitch *= randf_range(0.92, 1.12)
	elif _web and cue != "ui_focus" and not is_fire and _recent(cue, 0.045):
		return
	var bus := bus_for(cue)
	var priority := _web_priority(cue, bus, 0.0, true)
	if _play_stream(_get_sfx(cue), cue_gain(cue, volume_db), pitch, bus, priority) and _web and is_fire:
		Juice.duck_music(-2.5, 0.11)


## Thunder uses a fresh stream per strike, including its brighter Web render.
func play_thunder(volume_db := -1.0, pitch := 1.0) -> void:
	if Net.dedicated or _headless:
		return
	_first_play("thunder")
	var cue := "thunder_web" if _web else "thunder"
	var stream := _get_sfx(cue)
	if stream == null:
		stream = _get_sfx("thunder")
	if _play_stream(stream, cue_gain("thunder", volume_db), pitch, &"Ambience", WebPriority.FOREGROUND):
		Juice.duck_music(-7.0, 1.4)
		Perf.mark("thunder playback")


func _web_priority(cue: String, bus: StringName, distance: float, local: bool) -> int:
	if distance <= CLOSE_TELL_M and (cue in ATTACK_TELLS or cue in PLAYER_ALERTS):
		return WebPriority.FOREGROUND
	if cue == "ui_click" or (_is_fire(cue) and (local or distance <= 20.0)):
		return WebPriority.ACTION
	if bus == &"Foley" or cue in ["ui_focus", "ui_tick", "vhs_glitch", "enemy_death"]:
		return WebPriority.BACKGROUND
	return WebPriority.STANDARD


func _admit_web_voice(priority: int) -> bool:
	if priority == WebPriority.BACKGROUND and _web_voices.size() >= WEB_BACKGROUND_LIMIT:
		return false
	if _web_voices.size() < WEB_MAX_SFX:
		return true
	# Keep the oldest voice in each tier first in line for replacement.
	var victim: AudioStreamPlayer
	var lowest := priority + 1 if priority == WebPriority.FOREGROUND else priority
	for voice in _web_voices:
		if _web_voices[voice] < lowest:
			victim = voice
			lowest = _web_voices[voice]
	if victim == null:
		return false
	_web_voices.erase(victim)
	victim.stop()
	victim.queue_free()
	return true


func _play_stream(stream: AudioStream, volume_db: float, pitch: float, bus: StringName, priority: int) -> bool:
	if stream == null or (_web and not _admit_web_voice(priority)):
		return false
	var voice := AudioStreamPlayer.new()
	voice.stream = stream
	voice.volume_db = volume_db
	voice.pitch_scale = pitch
	voice.bus = bus
	voice.process_mode = Node.PROCESS_MODE_ALWAYS if bus == &"UI" else Node.PROCESS_MODE_PAUSABLE
	if _web:
		voice.playback_type = AudioServer.PLAYBACK_TYPE_STREAM
		_web_voices[voice] = priority
		voice.tree_exited.connect(func(): _web_voices.erase(voice))
	add_child(voice)
	voice.finished.connect(voice.queue_free)
	voice.play()
	return true


func play_at(cue: String, position: Vector3, volume_db := -6.0, pitch := 1.0) -> void:
	if Net.thin_server and volume_db > -65.0:
		Net.thin_server.record_sound(cue, position)
	if Net.dedicated or _headless or volume_db <= -65.0:
		return
	_first_play(cue)
	_heat_for_cue(cue)
	if cue == "pickup" and _recent(cue, 0.3):
		return
	volume_db = cue_gain(cue, volume_db)
	var bus := bus_for(cue)
	var camera := get_viewport().get_camera_3d()
	var distance := camera.global_position.distance_to(position) if camera else 0.0
	var close_tell := camera != null and distance <= CLOSE_TELL_M and cue in ATTACK_TELLS
	if _web:
		if distance > 42.0:
			return
		var priority := _web_priority(cue, bus, distance, false)
		var spatial_key := "near:" + cue if priority >= WebPriority.ACTION else "far:" + cue
		if cue != "pickup" and _recent(spatial_key, 0.06):
			return
		# On Web, approximate 3D distance attenuation in a lightweight 2D stream
		# to avoid expensive WebGL/WASM HRTF/spatial mixing overhead.
		var atten := -clampf(distance * 0.45, 0.0, 22.0)
		if _play_stream(_get_sfx(cue), volume_db + atten, pitch, bus, priority) and close_tell:
			_tell_left = TELL_HOLD
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
	voice.bus = bus
	voice.max_distance = 45.0
	# Distant sounds lose their highs (built-in air absorption), so a
	# teammate's gunfire down the street sounds far away.
	voice.attenuation_filter_cutoff_hz = 2800.0
	voice.attenuation_filter_db = -14.0
	world.add_child(voice)
	voice.global_position = position
	voice.finished.connect(voice.queue_free)
	voice.play()
	if close_tell:
		_tell_left = TELL_HOLD
