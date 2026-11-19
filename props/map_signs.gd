extends Node
## Convert fixed map labels into extruded, lit sign lettering.
func _ready() -> void:
	for label in get_parent().find_children("*", "Label3D", true, false):
		var lettering := MeshInstance3D.new()
		var mesh := TextMesh.new()
		mesh.font = preload("res://assets/fonts/BarlowCondensed-SemiBold.ttf")
		mesh.text = label.text
		mesh.font_size = label.font_size
		mesh.pixel_size = label.pixel_size
		mesh.depth = 0.08
		var material := StandardMaterial3D.new()
		material.albedo_color = label.modulate
		material.emission_enabled = true
		material.emission = label.modulate
		material.emission_energy_multiplier = 0.7
		mesh.material = material
		lettering.mesh = mesh
		label.add_child(lettering)
		label.text = ""
		label.set_meta("lettering", lettering)
