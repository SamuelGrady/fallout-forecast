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
## Debug (debug builds, host only): F1 skips to the next phase, F2 jumps to wave 5.

signal phase_changed(phase: Phase, wave: int)
signal storm_changed(state: StormState, intensity: float)

enum Phase { CALM, MUTATION_ROLL, DRIZZLE, DOWNPOUR, CLEARING }
enum StormState { CLEAR, DRIZZLE, DOWNPOUR, ACID_STORM }

const PHASE_NAMES := ["Calm", "Mutation Roll", "Drizzle", "Downpour", "Clearing"]
const STORM_NAMES := ["Clear", "Drizzle", "Downpour", "Acid Storm"]
const FINAL_WAVE := 5

## Starting values from the design doc's weather table. Index by StormState.
const STORM_INTENSITY := [0.0, 0.3, 0.7, 1.0]
const ENEMY_BUFF := [1.0, 1.0, 1.3, 1.5]
const SUIT_LOSS_PER_SECOND := [0.0, 1.0, 4.0, 6.0]

@export var auto_cycle := true
@export var calm_duration := 30.0
## Placeholder until the slot reel exists; the roll itself is Sam's.
@export var mutation_roll_duration := 5.0
@export var drizzle_duration := 60.0
@export var downpour_min_duration := 60.0
@export var downpour_max_duration := 90.0
@export var clearing_duration := 15.0
## How fast storm_intensity eases toward its target, in intensity per second.
@export var intensity_ramp := 0.1

var phase: Phase = Phase.CALM
var wave := 1
var phase_time_left := 0.0
var running := false
## Smoothed value every system reads.
var storm_intensity := 0.0
var target_intensity := 0.0
var storm_state: StormState = StormState.CLEAR


func _ready() -> void:
	if auto_cycle and _is_host():
		start_run.call_deferred()


func _process(delta: float) -> void:
	if running:
		phase_time_left = maxf(phase_time_left - delta, 0.0)
		if auto_cycle and _is_host() and phase_time_left <= 0.0:
			next_phase()

	var before := storm_intensity
	storm_intensity = move_toward(storm_intensity, target_intensity, intensity_ramp * delta)
	if storm_intensity != before:
		var new_state := _state_for(storm_intensity)
		storm_state = new_state
		storm_changed.emit(storm_state, storm_intensity)


func _unhandled_input(event: InputEvent) -> void:
	if not OS.is_debug_build() or not _is_host():
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_F1:
				next_phase()
			KEY_F2:
				set_phase(Phase.CALM, FINAL_WAVE)


## Host: start wave 1 at Calm.
func start_run() -> void:
	set_phase(Phase.CALM, 1)


## Host: advance one phase. After Clearing the next wave starts at Calm.
## After the final wave's Clearing the cycle stops.
func next_phase() -> void:
	if phase == Phase.CLEARING:
		if wave >= FINAL_WAVE:
			running = false
			return
		set_phase(Phase.CALM, wave + 1)
	else:
		set_phase((phase + 1) as Phase, wave)


## Host: jump to a phase. Sends it to every client.
func set_phase(new_phase: Phase, new_wave: int) -> void:
	if not _is_host():
		push_warning("WeatherManager.set_phase called on a client")
		return
	var duration := _duration_for(new_phase)
	_apply_phase(new_phase, new_wave, duration)
	if multiplayer.has_multiplayer_peer() and multiplayer.get_peers().size() > 0:
		_receive_phase.rpc(new_phase, new_wave, duration)


## Host: send the current phase to one peer (call when a player joins mid-run).
func sync_to_peer(peer_id: int) -> void:
	if _is_host():
		_receive_phase.rpc_id(peer_id, phase, wave, phase_time_left)
		_receive_intensity.rpc_id(peer_id, storm_intensity)


func phase_name() -> String:
	return PHASE_NAMES[phase]


func storm_name() -> String:
	return STORM_NAMES[storm_state]


func is_raining() -> bool:
	return storm_state != StormState.CLEAR


## Multiplier for enemy speed and damage at the current storm state.
func enemy_buff() -> float:
	return ENEMY_BUFF[storm_state]


## Suit integrity an exposed player loses per second right now.
func suit_loss_per_second() -> float:
	return SUIT_LOSS_PER_SECOND[storm_state]


@rpc("authority", "call_remote", "reliable")
func _receive_phase(new_phase: Phase, new_wave: int, time_left: float) -> void:
	_apply_phase(new_phase, new_wave, time_left)


@rpc("authority", "call_remote", "reliable")
func _receive_intensity(value: float) -> void:
	storm_intensity = value


func _apply_phase(new_phase: Phase, new_wave: int, time_left: float) -> void:
	phase = new_phase
	wave = new_wave
	phase_time_left = time_left
	running = true
	target_intensity = _target_for(new_phase, new_wave)
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


func _is_host() -> bool:
	return not multiplayer.has_multiplayer_peer() or multiplayer.is_server()
