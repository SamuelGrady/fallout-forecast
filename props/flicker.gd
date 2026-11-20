extends Node
## Makes its parent flicker like a dying neon tube or a bad streetlight.
## Works on a Label3D (fades modulate) or a Light3D (dims light_energy).
## Purely local and cosmetic.

## Average seconds between flicker bursts.
@export var interval := 4.0
## How dark a flicker gets, 0-1 (1 = fully off).
@export var depth := 0.85
## Chance a burst is a long dropout instead of a stutter.
@export var dropout_chance := 0.15

var _base_energy := 1.0
var _base_alpha := 1.0
var _next := 0.0
var _burst := 0.0
var _rng := RandomNumberGenerator.new()

static var _seq := 0
static var _active_sign: Node = null
static var _next_sign_ms := 0


func _ready() -> void:
	_seq += 1
	_rng.seed = int(hash(str(get_path()))) ^ (_seq * 2654435761) ^ int(Time.get_ticks_usec())
	var target := get_parent()
	if target is Label3D:
		# Stagger neon signs widely so the street never blinks in unison.
		_next = _rng.randf_range(2.5, maxf(interval * 3.5, 14.0))
		_base_alpha = target.modulate.a
	else:
		_next = _rng.randf_range(0.5, interval * 2.0)
		if target is Light3D:
			_base_energy = target.light_energy


func _exit_tree() -> void:
	if _active_sign == self:
		_active_sign = null


func _process(delta: float) -> void:
	_next -= delta
	var level := 1.0
	var target := get_parent()
	var is_sign := target is Label3D
	if _burst > 0.0:
		_burst -= delta
		level = 1.0 - depth * (1.0 if _rng.randf() < 0.55 else 0.3)
		if _burst <= 0.0 and _active_sign == self:
			_active_sign = null
			_next_sign_ms = Time.get_ticks_msec() + _rng.randi_range(2800, 6200)
	elif _next <= 0.0:
		if is_sign:
			var now := Time.get_ticks_msec()
			if (is_instance_valid(_active_sign) and _active_sign != self) or now < _next_sign_ms:
				_next = _rng.randf_range(2.5, 6.0)
			else:
				_active_sign = self
				_next = _rng.randf_range(maxf(interval * 2.5, 10.0), maxf(interval * 5.0, 22.0))
				_burst = _rng.randf_range(0.45, 1.1) if _rng.randf() < dropout_chance else _rng.randf_range(0.08, 0.28)
		else:
			_next = _rng.randf_range(interval * 0.5, interval * 1.5)
			_burst = _rng.randf_range(0.6, 1.8) if _rng.randf() < dropout_chance else _rng.randf_range(0.08, 0.35)
	if target is Light3D:
		target.light_energy = _base_energy * level
	elif is_sign:
		target.modulate.a = _base_alpha * level
		if target.has_meta("lettering"):
			var mesh: Node3D = target.get_meta("lettering")
			mesh.visible = level > 0.3
			if mesh.has_meta("glow"):
				var glow := mesh.get_meta("glow") as OmniLight3D
				if is_instance_valid(glow):
					glow.light_energy = 0.9 * level
