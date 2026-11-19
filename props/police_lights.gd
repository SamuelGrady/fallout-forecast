extends Node3D
## Alternating red/blue light bar for a parked police car. Adds two
## OmniLight3Ds above the car when it loads. Cosmetic, local only.

@export var height := 2.6
@export var flash_rate := 2.5
@export var energy := 3.0
@export var light_range := 9.0

var _red := OmniLight3D.new()
var _blue := OmniLight3D.new()
var _t := 0.0


func _ready() -> void:
	for pair in [[_red, Color(1, 0.1, 0.1), -0.4], [_blue, Color(0.15, 0.3, 1), 0.4]]:
		var light: OmniLight3D = pair[0]
		light.light_color = pair[1]
		light.omni_range = light_range
		light.position = Vector3(pair[2], height, 0)
		add_child(light)
	_t = randf() * 2.0


func _process(delta: float) -> void:
	_t += delta * flash_rate
	var phase := fmod(_t, 2.0)
	_red.light_energy = energy if phase < 1.0 else 0.0
	_blue.light_energy = 0.0 if phase < 1.0 else energy
