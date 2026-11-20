extends Node
## Autoload "WeatherManager". Owns the storm cycle and storm_intensity (0-1).
##
## The host (multiplayer server, or offline) runs the phase timers and sends
## every phase change to clients by RPC. Each client counts the phase timer
## down and eases storm_intensity toward the phase's target on its own, so only
## phase changes cross the network.
##
## Until GameManager exists, auto_cycle runs the phases on its own timers.
## GameManager can set auto_cycle = false and drive it with set_phase().
##
## Lightning: during Downpour (and the Acid Storm) the host strikes every
## 8-15 s at a random spot on the map and sends one RPC with the position and
## a seed, so every client's flash, bolt, outlines and thunder line up.
##
## Debug (debug builds, host only): F1 skips to the next phase, F2 jumps to
## wave 5, F6 strikes lightning now.

signal phase_changed(phase: Phase, wave: int)
signal storm_changed(state: StormState, intensity: float)
signal lightning_struck(position: Vector3, strike_seed: int)

enum Phase { CALM, MUTATION_ROLL, DRIZZLE, DOWNPOUR, CLEARING }
enum StormState { CLEAR, DRIZZLE, DOWNPOUR, ACID_STORM }

const PHASE_NAMES := ["Calm", "Mutation Roll", "Drizzle", "Downpour", "Clearing"]
const STORM_NAMES := ["Clear", "Drizzle", "Downpour", "Acid Storm"]
const FINAL_WAVE := 5
const WavePlan := preload("res://enemies/wave_plan.gd")

## Starting values from the design doc's weather table. Index by StormState.
const STORM_INTENSITY := [0.0, 0.3, 0.7, 1.0]
const ENEMY_BUFF := [1.0, 1.0, 1.3, 1.5]
const SUIT_LOSS_PER_SECOND := [0.0, 1.0, 4.0, 6.0]

@export var auto_cycle := true
@export var calm_duration := 30.0
## Wave 1 starts faster: the playtest sat through 30 s of nothing.
@export var first_calm_duration := 12.0
## Placeholder until the slot reel exists; the roll itself is Sam's.
@export var mutation_roll_duration := 5.0
@export var drizzle_duration := 30.0
@export var downpour_min_duration := 40.0
@export var downpour_max_duration := 50.0
@export var clearing_duration := 15.0
## How fast storm_intensity eases toward its target, in intensity per second.
@export var intensity_ramp := 0.1
@export var lightning_min_interval := 8.0
@export var lightning_max_interval := 15.0
## Strikes land at a random spot inside this half-size around the map center.
@export var lightning_area := 60.0

var phase: Phase = Phase.CALM
var wave := 1
var phase_time_left := 0.0
var running := false
## Smoothed value every system reads.
var storm_intensity := 0.0
var target_intensity := 0.0
var storm_state: StormState = StormState.CLEAR

var _lightning_timer := 0.0


## While true the current phase doesn't time out (mutation roll vote, boss alive).
var hold := false
## When >= 0, storm_intensity eases to this instead of the phase target (boss sacs).
var intensity_override := -1.0


func _process(delta: float) -> void:
	if running:
		phase_time_left = maxf(phase_time_left - delta, 0.0)
		if auto_cycle and Net.is_host() and phase_time_left <= 0.0 and not hold and _combat_complete():
			next_phase()
		if Net.is_host() and phase == Phase.DOWNPOUR:
			_lightning_timer -= delta
			if _lightning_timer <= 0.0:
				var interval_scale := .62 if wave_modifier() == WavePlan.HEAVY_WEATHER else 1.0
				_lightning_timer = randf_range(lightning_min_interval, lightning_max_interval) * interval_scale
				strike_lightning()

	var before := storm_intensity
	var goal := intensity_override if intensity_override >= 0.0 else target_intensity
	storm_intensity = move_toward(storm_intensity, goal, intensity_ramp * delta)
	var before_state := storm_state
	storm_state = _state_for(storm_intensity)
	if storm_intensity != before or storm_state != before_state:
		storm_changed.emit(storm_state, storm_intensity)


func _unhandled_input(event: InputEvent) -> void:
	if not OS.is_debug_build() or not Net.is_host():
		return
	if event is InputEventKey and event.pressed and not event.echo and not event.shift_pressed:
		match event.keycode:
			KEY_F1:
				next_phase()
			KEY_F2:
				set_phase(Phase.CALM, FINAL_WAVE)
			KEY_F6:
				strike_lightning()


## Host: everyone is ready, so cut a waiting phase (Calm or Clearing) short.
func skip_wait() -> void:
	if not Net.is_host() or hold or not (phase == Phase.CALM or phase == Phase.CLEARING):
		return
	if phase_time_left > 3.0:
		_apply_phase(phase, wave, 3.0)
		if Net.is_online():
			Net.rpc_to_all(_receive_phase, [phase, wave, 3.0])


## Host: force storm_intensity toward `value` (-1 to go back to the phase's
## target). Every client eases toward the same number, so the boss's sacs step
## the storm down on every screen at once.
func set_intensity_override(value: float) -> void:
	if not Net.is_host():
		return
	intensity_override = value
	if Net.is_online():
		Net.rpc_to_all(_override, [value])


@rpc("authority", "call_remote", "reliable")
func _override(value: float) -> void:
	intensity_override = value


## Host: start wave 1 at Calm.
func start_run() -> void:
	hold = false
	# Through the setter so clients drop any override left by the last boss.
	set_intensity_override(-1.0)
	set_phase(Phase.CALM, 1)


## Leave the run (title, results): stop the cycle and clear the sky.
func stop() -> void:
	running = false
	hold = false
	intensity_override = -1.0
	target_intensity = 0.0
	storm_intensity = 0.0
	phase = Phase.CALM
	wave = 1


## Host: advance one phase. After Clearing the next wave starts at Calm.
## After the final wave's Clearing the cycle stops.
func next_phase() -> void:
	if phase == Phase.CLEARING:
		if wave >= FINAL_WAVE and not GameManager.endless:
			running = false
			return
		set_phase(Phase.CALM, wave + 1)
	elif phase == Phase.CALM and wave == 1:
		set_phase(Phase.DRIZZLE, wave)
	else:
		set_phase((phase + 1) as Phase, wave)


## Host: jump to a phase. Sends it to every client.
func set_phase(new_phase: Phase, new_wave: int) -> void:
	if not Net.is_host():
		push_warning("WeatherManager.set_phase called on a client")
		return
	var duration := _duration_for(new_phase)
	if new_phase == Phase.CALM and new_wave == 1:
		duration = first_calm_duration
	_apply_phase(new_phase, new_wave, duration)
	if Net.is_online():
		Net.rpc_to_all(_receive_phase, [new_phase, new_wave, duration])


## Host: strike lightning at a random spot (or at `at`) on every client.
func strike_lightning(at: Variant = null) -> void:
	if not Net.is_host():
		return
	var position: Vector3
	var rods := get_tree().get_nodes_in_group("lightning_rods")
	if not rods.is_empty():
		position = rods[0].global_position
	elif at is Vector3:
		position = at
	else:
		var sites := get_tree().get_nodes_in_group("enemy_spawn")
		if sites.is_empty():
			sites = get_tree().get_nodes_in_group("player_spawn")
		var site := sites.pick_random() as Node3D if not sites.is_empty() else null
		var center := site.global_position if site else Vector3.ZERO
		var spread := lightning_area * (.11 if wave_modifier() == WavePlan.HEAVY_WEATHER else .32)
		position = center + Vector3(randf_range(-spread, spread), 0.0, randf_range(-spread, spread))
		# Conductors mutation: pull most strikes near an infected so the chain jump matters.
		if GameManager.has_mutation("conductors") and randf() < 0.65:
			var enemies := get_tree().get_nodes_in_group("enemies")
			if not enemies.is_empty():
				var chosen: Node3D = enemies.pick_random()
				position = chosen.global_position + Vector3(randf_range(-3.5, 3.5), 0.0, randf_range(-3.5, 3.5))
	var strike_seed := randi()
	# rpc() needs a live peer, so solo strikes come straight off the signal.
	if Net.is_online():
		Net.rpc_to_all(_strike, [position, strike_seed])
	lightning_struck.emit(position, strike_seed)


@rpc("authority", "call_remote", "reliable")
func _strike(position: Vector3, strike_seed: int) -> void:
	lightning_struck.emit(position, strike_seed)


## Host: send the current phase to one peer (call when a player joins mid-run).
func sync_to_peer(peer_id: int) -> void:
	if Net.is_host():
		_receive_phase.rpc_id(peer_id, phase, wave, phase_time_left)
		_receive_intensity.rpc_id(peer_id, storm_intensity)
		_override.rpc_id(peer_id, intensity_override)


func replicate_puddle_growth(values: Dictionary) -> void:
	if Net.is_host() and not values.is_empty():
		Net.rpc_to_run(_sync_puddles, [values])


## The run scene is loaded on this peer, so existing water and lurking
## Undertows agree on what the new player sees.
func sync_puddles_to_peer(peer_id: int) -> void:
	if not Net.is_host():
		return
	var wet := {}
	for node in get_tree().get_nodes_in_group("puddles"):
		if node.has_method("set_growth"):
			wet[node.get_path()] = node.growth
	_sync_puddles.rpc_id(peer_id, wet)


@rpc("authority", "call_remote", "reliable")
func _sync_puddles(wet: Dictionary) -> void:
	for path in wet:
		var puddle := get_node_or_null(path)
		if puddle and puddle.has_method("set_growth"):
			puddle.set_growth(float(wet[path]))


func phase_name() -> String:
	return PHASE_NAMES[phase]


func wave_modifier() -> String:
	return WavePlan.modifier(wave)


func storm_name() -> String:
	return STORM_NAMES[storm_state]


## True only while an active rain/storm phase (or boss storm override) is driving hazard rain.
## Clearing, Calm, and Mutation Roll immediately end hazardous rain even while visuals ease out.
func is_storm_active() -> bool:
	if intensity_override >= 0.0:
		return intensity_override > 0.001
	return phase == Phase.DRIZZLE or phase == Phase.DOWNPOUR


func is_raining() -> bool:
	return storm_state != StormState.CLEAR and is_storm_active()


## Multiplier for enemy speed and damage at the current storm state.
func enemy_buff() -> float:
	return ENEMY_BUFF[storm_state]


## Suit integrity an exposed player loses per second right now.
func suit_loss_per_second() -> float:
	if not is_storm_active():
		return 0.0
	return SUIT_LOSS_PER_SECOND[storm_state]


@rpc("authority", "call_remote", "reliable")
func _receive_phase(new_phase: Phase, new_wave: int, time_left: float) -> void:
	_apply_phase(new_phase, new_wave, time_left)


@rpc("authority", "call_remote", "reliable")
func _receive_intensity(value: float) -> void:
	storm_intensity = value


func _apply_phase(new_phase: Phase, new_wave: int, time_left: float) -> void:
	Perf.mark("phase %s wave %d" % [PHASE_NAMES[new_phase], new_wave])
	phase = new_phase
	wave = new_wave
	phase_time_left = time_left
	running = true
	target_intensity = _target_for(new_phase, new_wave)
	_lightning_timer = randf_range(2.0, lightning_min_interval)
	phase_changed.emit(phase, wave)


func _target_for(p: Phase, w: int) -> float:
	match p:
		Phase.DRIZZLE:
			return STORM_INTENSITY[StormState.DRIZZLE]
		Phase.DOWNPOUR:
			return STORM_INTENSITY[StormState.ACID_STORM if w >= FINAL_WAVE else StormState.DOWNPOUR]
	return STORM_INTENSITY[StormState.CLEAR]


func _duration_for(p: Phase) -> float:
	match p:
		Phase.CALM:
			return calm_duration
		Phase.MUTATION_ROLL:
			return mutation_roll_duration
		Phase.DRIZZLE:
			return drizzle_duration
		Phase.DOWNPOUR:
			return randf_range(downpour_min_duration, downpour_max_duration)
	return clearing_duration


## Storm state = the highest table row the eased intensity has reached.
func _state_for(value: float) -> StormState:
	for s in [StormState.ACID_STORM, StormState.DOWNPOUR, StormState.DRIZZLE]:
		if value >= STORM_INTENSITY[s] - 0.001:
			return s
	return StormState.CLEAR


## A Downpour doesn't end while the horde is still alive. Host only, since it
## is only used to decide whether the phase timer may advance.
func _combat_complete() -> bool:
	if phase != Phase.DOWNPOUR or not GameManager.run_active:
		return true
	var scene := get_tree().current_scene
	var spawner := scene.get_node_or_null("Enemies") if scene else null
	return spawner == null or spawner.can_finish_wave()
