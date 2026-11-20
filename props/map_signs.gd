extends Node
## Convert fixed map labels into extruded, lit sign lettering and 3D destination pictograms.
## Simplifies repeated town-name text while preserving approach-angle readability.

const FONT := preload("res://assets/fonts/BarlowCondensed-SemiBold.ttf")

const RENAME := {
	"GasSign": "GAS",
	"DeckSign": "PLAZA",
	"QuarantineSignW": "QUARANTINE",
	"QuarantineSignE": "QUARANTINE",
}

const DOUBLE_SIDED := [
	"GasSign",
	"DeckSign",
	"QuarantineSignW",
	"QuarantineSignE",
]


func _ready() -> void:
	for label in get_parent().find_children("*", "Label3D", true, false):
		var parent := label.get_parent()
		# Decon stations now show physical charge cells and spray state in decon_shower.gd.
		if parent and parent.is_in_group("decon_shower"):
			label.text = ""
			label.visible = false
			continue
		var sign_name: String = label.name
		if sign_name == "FountainPlaque":
			_build_fountain_emblem(label)
			label.text = ""
			continue
		if sign_name == "ParkSign":
			_build_park_pictogram(label)
			label.text = ""
			continue
		if sign_name == "Sign" and parent and parent.name.begins_with("BusStop"):
			_build_bus_pictogram(label)
			label.text = ""
			continue
		if sign_name.begins_with("QuarantineSign"):
			_build_quarantine_sign(label)
			label.text = ""
			continue
		var text: String = RENAME.get(sign_name, label.text)
		var is_double := sign_name in DOUBLE_SIDED
		var add_board := sign_name != "PinecrestSign"
		_build_text_sign(label, text, is_double, add_board)
		label.text = ""


func _build_text_sign(label: Label3D, text: String, double_sided: bool, add_board: bool) -> void:
	var lettering := _make_text_mesh(text, label.font_size, label.pixel_size, label.modulate, 0.07)
	var aabb := lettering.mesh.get_aabb()
	if add_board:
		var board := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(aabb.size.x + 0.42, aabb.size.y + 0.24, 0.08)
		board.mesh = box
		board.position = Vector3(aabb.get_center().x, aabb.get_center().y, -0.07)
		board.material_override = _solid_mat(Color("#121a20"), 0.85)
		label.add_child(board)
		# Crisp rim frame so the sign reads cleanly at oblique angles.
		var frame := MeshInstance3D.new()
		var frame_box := BoxMesh.new()
		frame_box.size = Vector3(box.size.x + 0.08, box.size.y + 0.08, 0.05)
		frame.mesh = frame_box
		frame.position = board.position + Vector3(0.0, 0.0, -0.01)
		frame.material_override = _solid_mat(label.modulate.darkened(0.45), 0.7)
		label.add_child(frame)
	if double_sided:
		var back := _make_text_mesh(text, label.font_size, label.pixel_size, label.modulate, 0.07)
		back.rotation.y = PI
		back.position = Vector3(0.0, 0.0, -0.14)
		lettering.add_child(back)
	label.add_child(lettering)
	label.set_meta("lettering", lettering)


func _build_bus_pictogram(label: Label3D) -> void:
	# Double-sided retro transit plaque with 3D bus silhouette.
	var board := _make_box(Vector3(0.95, 0.95, 0.08), Color("#18324a"))
	label.add_child(board)
	var border := _make_box(Vector3(1.03, 1.03, 0.05), Color("#e6f2f5"))
	label.add_child(border)
	for side: float in [-1.0, 1.0]:
		var z := side * 0.055
		# Bus body
		var body := _make_box(Vector3(0.56, 0.46, 0.04), Color("#e6f2f5"), true)
		body.position = Vector3(0.0, 0.04, z)
		label.add_child(body)
		# Windshield cutout
		var glass := _make_box(Vector3(0.44, 0.18, 0.05), Color("#18324a"))
		glass.position = Vector3(0.0, 0.11, z + side * 0.006)
		label.add_child(glass)
		# Headlights
		for hx in [-0.17, 0.17]:
			var lamp := _make_box(Vector3(0.08, 0.06, 0.05), Color("#ffd257"), true)
			lamp.position = Vector3(hx, -0.09, z + side * 0.006)
			label.add_child(lamp)
		# Wheels
		for wx in [-0.18, 0.18]:
			var wheel := _make_box(Vector3(0.11, 0.11, 0.04), Color("#e6f2f5"), true)
			wheel.position = Vector3(wx, -0.23, z)
			label.add_child(wheel)


func _build_park_pictogram(label: Label3D) -> void:
	# Double-sided timber & enamel park marker with 3D layered pine tree silhouette.
	var post := _make_box(Vector3(0.14, 2.2, 0.14), Color("#4c3728"))
	post.position = Vector3(0.0, -1.1, 0.0)
	label.add_child(post)
	var board := _make_box(Vector3(1.15, 1.05, 0.1), Color("#1c3a27"))
	label.add_child(board)
	var rim := _make_box(Vector3(1.24, 1.14, 0.06), Color("#d7e6cf"))
	label.add_child(rim)
	for side: float in [-1.0, 1.0]:
		var z := side * 0.065
		var trunk := _make_box(Vector3(0.12, 0.24, 0.04), Color("#c29b6c"))
		trunk.position = Vector3(0.0, -0.28, z)
		label.add_child(trunk)
		# Three stacked tree tiers
		var tiers := [
			[0.62, 0.2, -0.1],
			[0.48, 0.2, 0.08],
			[0.3, 0.2, 0.25],
		]
		for tier in tiers:
			var foliage := MeshInstance3D.new()
			var prism := PrismMesh.new()
			prism.size = Vector3(tier[0], tier[1], 0.05)
			foliage.mesh = prism
			foliage.position = Vector3(0.0, tier[2], z)
			foliage.material_override = _solid_mat(Color("#7ee287"), 0.55, true)
			label.add_child(foliage)


func _build_quarantine_sign(label: Label3D) -> void:
	# Double-sided hazard yellow quarantine board with shield emblem + short "QUARANTINE".
	var board := _make_box(Vector3(3.1, 0.95, 0.09), Color("#1b1f22"))
	label.add_child(board)
	var top_bar := _make_box(Vector3(3.16, 0.12, 0.11), Color("#f5d142"), true)
	top_bar.position = Vector3(0.0, 0.45, 0.0)
	label.add_child(top_bar)
	var bot_bar := _make_box(Vector3(3.16, 0.12, 0.11), Color("#f5d142"), true)
	bot_bar.position = Vector3(0.0, -0.45, 0.0)
	label.add_child(bot_bar)
	# Hazard diamond emblem on the left of each side.
	for side: float in [-1.0, 1.0]:
		var z := side * 0.065
		var diamond := _make_box(Vector3(0.36, 0.36, 0.04), Color("#f5d142"), true)
		diamond.position = Vector3(-1.15 * side, 0.0, z)
		diamond.rotation.z = PI * 0.25
		label.add_child(diamond)
		var bar := _make_box(Vector3(0.06, 0.16, 0.05), Color("#15181b"))
		bar.position = Vector3(-1.15 * side, 0.03, z + side * 0.008)
		label.add_child(bar)
		var dot := _make_box(Vector3(0.06, 0.05, 0.05), Color("#15181b"))
		dot.position = Vector3(-1.15 * side, -0.1, z + side * 0.008)
		label.add_child(dot)
	var front := _make_text_mesh("QUARANTINE", 56, 0.009, Color("#f5d142"), 0.05)
	front.position = Vector3(0.22, 0.0, 0.055)
	var back := _make_text_mesh("QUARANTINE", 56, 0.009, Color("#f5d142"), 0.05)
	back.rotation.y = PI
	back.position = Vector3(-0.44, 0.0, -0.11)
	front.add_child(back)
	label.add_child(front)
	label.set_meta("lettering", front)


func _build_fountain_emblem(label: Label3D) -> void:
	# Replace redundant town-name plaque with a small cast-bronze civic crest.
	var plaque := _make_box(Vector3(0.68, 0.44, 0.06), Color("#5c4a32"))
	label.add_child(plaque)
	var rim := _make_box(Vector3(0.74, 0.5, 0.04), Color("#8c7348"))
	label.add_child(rim)
	var crest := MeshInstance3D.new()
	var prism := PrismMesh.new()
	prism.size = Vector3(0.26, 0.28, 0.05)
	crest.mesh = prism
	crest.position = Vector3(0.0, 0.02, 0.045)
	crest.material_override = _solid_mat(Color("#b5985e"), 0.5)
	label.add_child(crest)


func _make_text_mesh(text: String, font_size: int, pixel_size: float, color: Color, depth: float) -> MeshInstance3D:
	var lettering := MeshInstance3D.new()
	var mesh := TextMesh.new()
	mesh.font = FONT
	mesh.text = text
	mesh.font_size = font_size
	mesh.pixel_size = pixel_size
	mesh.depth = depth
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 0.85
	mesh.material = material
	lettering.mesh = mesh
	return lettering


func _make_box(size: Vector3, color: Color, emissive := false) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	node.material_override = _solid_mat(color, 0.7, emissive)
	return node


func _solid_mat(color: Color, roughness: float, emissive := false) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = roughness
	if emissive:
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = 0.65
	return mat

