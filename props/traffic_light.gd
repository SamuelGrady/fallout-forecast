extends Node3D
## Cycles three lamp meshes (children named Red, Amber, Green) and blinks
## amber during the Acid Storm, like the grid is failing. Cosmetic, local only.

@export var green_time := 6.0
@export var amber_time := 2.0
@export var red_time := 6.0

var _t := 0.0
var _lamps := {}


func _ready() -> void:
	for lamp_name in ["Red", "Amber", "Green"]:
		var lamp := get_node_or_null(lamp_name) as MeshInstance3D
		if lamp:
			var material := StandardMaterial3D.new()
			material.emission_enabled = true
			material.disable_fog = true
			lamp.material_override = material
			_lamps[lamp_name] = material


func _process(delta: float) -> void:
	_t += delta
	var lit := ""
	if WeatherManager.storm_state == WeatherManager.StormState.ACID_STORM:
		lit = "Amber" if fmod(_t, 1.0) < 0.5 else ""
	else:
		var cycle := fmod(_t, green_time + amber_time + red_time)
		lit = "Green" if cycle < green_time else ("Amber" if cycle < green_time + amber_time else "Red")
	var colors := {"Red": Color(1, 0.1, 0.05), "Amber": Color(1, 0.6, 0.05), "Green": Color(0.1, 1, 0.3)}
	for lamp_name in _lamps:
		var m: StandardMaterial3D = _lamps[lamp_name]
		var on: bool = lamp_name == lit
		m.albedo_color = colors[lamp_name] if on else colors[lamp_name] * 0.15
		m.emission = colors[lamp_name] if on else Color.BLACK
		m.emission_energy_multiplier = 3.0 if on else 0.0
