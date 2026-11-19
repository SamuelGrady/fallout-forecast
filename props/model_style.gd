extends Node3D
## Put on the root of an instanced model (e.g. a Kenney .glb) to restyle every
## mesh inside it at runtime: a color tint over the model's own texture and
## the visual layers it renders on. Godot doesn't save edits to meshes inside
## an instanced .glb, so this does it when the scene loads.

## Multiplied with the model's texture. White leaves it unchanged.
@export var tint := Color.WHITE
## The model's texture (Kenney kits share one colormap per kit).
@export var texture: Texture2D
## Layer 2 = the local player's own body, hidden from their own camera.
@export_flags_3d_render var render_layers := 1


func _ready() -> void:
	var material: StandardMaterial3D = null
	if tint != Color.WHITE and texture:
		material = StandardMaterial3D.new()
		material.albedo_texture = texture
		material.albedo_color = tint
	for mesh in find_children("*", "MeshInstance3D", true, false):
		mesh.layers = render_layers
		if material:
			mesh.material_override = material
