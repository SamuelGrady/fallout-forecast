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


func _ready() -> void:
	_rng.randomize()
	_next = _rng.randf_range(0.5, interval * 2.0)
	var target := get_parent()
	if target is Light3D:
		_base_energy = target.light_energy
	elif target is Label3D:
		_base_alpha = target.modulate.a


func _process(delta: float) -> void:
	_next -= delta
	var level := 1.0
	if _burst > 0.0:
		_burst -= delta
		level = 1.0 - depth * (1.0 if _rng.randf() < 0.6 else 0.3)
	elif _next <= 0.0:
		_next = _rng.randf_range(interval * 0.5, interval * 1.5)
		_burst = _rng.randf_range(0.6, 1.8) if _rng.randf() < dropout_chance else _rng.randf_range(0.08, 0.35)
	var target := get_parent()
	if target is Light3D:
		target.light_energy = _base_energy * level
	elif target is Label3D:
		target.modulate.a = _base_alpha * level
		if target.has_meta("lettering"):
			var mesh: Node3D = target.get_meta("lettering")
			mesh.visible = level > 0.3
