class_name NeonLettering
## Modelled sign lettering: each letter is bent glass tube from a stroke font,
## with rounded joints, mounted on a dark raceway with standoffs. The whole
## sign merges into one mesh (one draw call). `lit = false` paints the same
## strokes flat instead, for the water tower lettering.
##
## Letters are drawn on a 4 x 6 grid (x right, y up) and face +Z, like the
## Label3D they replace.

const GLYPHS := {
	"A": [[[0, 0], [0, 4], [2, 6], [4, 4], [4, 0]], [[0, 3], [4, 3]]],
	"B": [[[0, 0], [0, 6], [3, 6], [4, 5], [4, 4], [3, 3], [0, 3]], [[3, 3], [4, 2], [4, 1], [3, 0], [0, 0]]],
	"C": [[[4, 5], [3, 6], [1, 6], [0, 5], [0, 1], [1, 0], [3, 0], [4, 1]]],
	"D": [[[0, 0], [0, 6], [2, 6], [4, 4], [4, 2], [2, 0], [0, 0]]],
	"E": [[[4, 6], [0, 6], [0, 0], [4, 0]], [[0, 3], [3, 3]]],
	"F": [[[4, 6], [0, 6], [0, 0]], [[0, 3], [3, 3]]],
	"G": [[[4, 5], [3, 6], [1, 6], [0, 5], [0, 1], [1, 0], [3, 0], [4, 1], [4, 3], [2, 3]]],
	"H": [[[0, 0], [0, 6]], [[4, 0], [4, 6]], [[0, 3], [4, 3]]],
	"I": [[[1, 6], [3, 6]], [[2, 6], [2, 0]], [[1, 0], [3, 0]]],
	"J": [[[4, 6], [4, 1], [3, 0], [1, 0], [0, 1]]],
	"K": [[[0, 0], [0, 6]], [[4, 6], [0, 2]], [[1, 3], [4, 0]]],
	"L": [[[0, 6], [0, 0], [4, 0]]],
	"M": [[[0, 0], [0, 6], [2, 3], [4, 6], [4, 0]]],
	"N": [[[0, 0], [0, 6], [4, 0], [4, 6]]],
	"O": [[[1, 0], [0, 1], [0, 5], [1, 6], [3, 6], [4, 5], [4, 1], [3, 0], [1, 0]]],
	"P": [[[0, 0], [0, 6], [3, 6], [4, 5], [4, 4], [3, 3], [0, 3]]],
	"Q": [[[1, 0], [0, 1], [0, 5], [1, 6], [3, 6], [4, 5], [4, 1], [3, 0], [1, 0]], [[2, 2], [4, 0]]],
	"R": [[[0, 0], [0, 6], [3, 6], [4, 5], [4, 4], [3, 3], [0, 3]], [[2, 3], [4, 0]]],
	"S": [[[4, 5], [3, 6], [1, 6], [0, 5], [0, 4], [1, 3], [3, 3], [4, 2], [4, 1], [3, 0], [1, 0], [0, 1]]],
	"T": [[[0, 6], [4, 6]], [[2, 6], [2, 0]]],
	"U": [[[0, 6], [0, 1], [1, 0], [3, 0], [4, 1], [4, 6]]],
	"V": [[[0, 6], [2, 0], [4, 6]]],
	"W": [[[0, 6], [1, 0], [2, 3], [3, 0], [4, 6]]],
	"X": [[[0, 6], [4, 0]], [[4, 6], [0, 0]]],
	"Y": [[[0, 6], [2, 3], [4, 6]], [[2, 3], [2, 0]]],
	"Z": [[[0, 6], [4, 6], [0, 0], [4, 0]]],
	"0": [[[1, 0], [0, 1], [0, 5], [1, 6], [3, 6], [4, 5], [4, 1], [3, 0], [1, 0]], [[0, 1], [4, 5]]],
	"1": [[[1, 5], [2, 6], [2, 0]], [[1, 0], [3, 0]]],
	"2": [[[0, 5], [1, 6], [3, 6], [4, 5], [4, 4], [0, 0], [4, 0]]],
	"3": [[[0, 5], [1, 6], [3, 6], [4, 5], [4, 4], [3, 3], [4, 2], [4, 1], [3, 0], [1, 0], [0, 1]], [[1, 3], [3, 3]]],
	"4": [[[3, 0], [3, 6], [0, 2], [4, 2]]],
	"5": [[[4, 6], [0, 6], [0, 3], [3, 3], [4, 2], [4, 1], [3, 0], [0, 0]]],
	"6": [[[4, 5], [3, 6], [1, 6], [0, 5], [0, 1], [1, 0], [3, 0], [4, 1], [4, 2], [3, 3], [0, 3]]],
	"7": [[[0, 6], [4, 6], [1, 0]]],
	"8": [[[1, 3], [0, 4], [0, 5], [1, 6], [3, 6], [4, 5], [4, 4], [3, 3], [1, 3], [0, 2], [0, 1], [1, 0], [3, 0], [4, 1], [4, 2], [3, 3]]],
	"9": [[[4, 3], [1, 3], [0, 4], [0, 5], [1, 6], [3, 6], [4, 5], [4, 1], [3, 0], [1, 0]]],
	"-": [[[1, 3], [3, 3]]],
	"'": [[[2, 6], [2, 4.5]]],
	".": [[[2, 0], [2, 0.3]]],
}
const ADVANCE := 5.4  # grid units per letter, including the gap
const SPACE := 3.2
const LINE_GAP := 3.0

static var _tube_mesh: CylinderMesh
static var _joint_mesh: SphereMesh
static var _paint_mesh: BoxMesh


## `height` is the cap height in meters. Multi-line text uses "\n".
static func build(text: String, height: float, color: Color, lit := true, raceway := true) -> Node3D:
	var root := Node3D.new()
	root.name = "Neon"
	var unit := height / 6.0
	var lines := text.to_upper().split("\n")
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var radius := maxf(unit * 0.32, 0.012)
	var line_widths: Array[float] = []
	var total_height := lines.size() * 6.0 + (lines.size() - 1) * LINE_GAP
	for row in lines.size():
		var line: String = lines[row]
		var width := _line_width(line)
		line_widths.append(width)
		var x := -width * 0.5
		var y := total_height * 0.5 - 6.0 - row * (6.0 + LINE_GAP)
		for ch in line:
			if ch == " ":
				x += SPACE
				continue
			for stroke in GLYPHS.get(ch, []):
				for i in stroke.size():
					var a := Vector3((x + stroke[i][0]) * unit, (y + stroke[i][1]) * unit, 0.0)
					if lit:
						_add_joint(surface, a, radius)
					if i > 0:
						var b := Vector3((x + stroke[i - 1][0]) * unit, (y + stroke[i - 1][1]) * unit, 0.0)
						if lit:
							_add_tube(surface, b, a, radius)
						else:
							_add_paint(surface, b, a, radius * 1.6)
			x += ADVANCE
	surface.generate_normals()
	var letters := MeshInstance3D.new()
	letters.name = "Tubes"
	letters.mesh = surface.commit()
	letters.material_override = _tube_material(color) if lit else _paint_material(color)
	letters.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	letters.position.z = radius * 3.0 if lit else 0.01
	root.add_child(letters)
	if lit and raceway:
		# A dark metal raceway behind each line, on standoffs.
		for row in lines.size():
			var y := (total_height * 0.5 - 3.0 - row * (6.0 + LINE_GAP)) * unit
			var w := (line_widths[row] + 1.0) * unit
			var bar := MeshInstance3D.new()
			var box := BoxMesh.new()
			box.size = Vector3(w, unit * 1.6, unit * 0.9)
			bar.mesh = box
			bar.position = Vector3(0, y, -unit * 0.2)
			bar.material_override = _metal()
			root.add_child(bar)
			for sx in [-0.4, 0.0, 0.4]:
				var post := MeshInstance3D.new()
				var post_mesh := BoxMesh.new()
				post_mesh.size = Vector3(unit * 0.25, unit * 0.25, radius * 3.0)
				post.mesh = post_mesh
				post.position = Vector3(sx * w, y, radius * 1.5)
				post.material_override = _metal()
				root.add_child(post)
	if lit and not OS.has_feature("web"):
		# Colored wash on the wall behind the sign (skipped on Web to keep
		# WebGL2 forward lighting fast; the emissive neon tubes remain bright).
		var glow := OmniLight3D.new()
		glow.light_color = color
		glow.light_energy = 0.9
		glow.omni_range = clampf(height * 4.0, 2.0, 7.0)
		glow.position = Vector3(0, 0, unit * 4.0)
		glow.shadow_enabled = false
		root.add_child(glow)
		root.set_meta("glow", glow)
	root.set_meta("tubes", letters)
	return root


## Width of one line in grid units (no trailing gap).
static func _line_width(line: String) -> float:
	var width := 0.0
	for ch in line:
		width += SPACE if ch == " " else ADVANCE
	return maxf(width - (ADVANCE - 4.0), 0.0)


static func _add_tube(surface: SurfaceTool, a: Vector3, b: Vector3, radius: float) -> void:
	var length := a.distance_to(b)
	if length < 0.001:
		return
	if _tube_mesh == null:
		_tube_mesh = CylinderMesh.new()
		_tube_mesh.radial_segments = 4 if OS.has_feature("web") else 6
		_tube_mesh.rings = 1
		_tube_mesh.cap_top = false
		_tube_mesh.cap_bottom = false
	_tube_mesh.top_radius = 1.0
	_tube_mesh.bottom_radius = 1.0
	_tube_mesh.height = 1.0
	var dir := (b - a) / length
	if dir.y < 0.0:
		dir = -dir
	var basis := Basis(Quaternion(Vector3.UP, dir)) * Basis.from_scale(Vector3(radius, length, radius))
	surface.append_from(_tube_mesh, 0, Transform3D(basis, (a + b) * 0.5))


static func _add_joint(surface: SurfaceTool, at: Vector3, radius: float) -> void:
	if _joint_mesh == null:
		_joint_mesh = SphereMesh.new()
		_joint_mesh.radius = 1.0
		_joint_mesh.height = 2.0
		_joint_mesh.radial_segments = 4 if OS.has_feature("web") else 6
		_joint_mesh.rings = 2 if OS.has_feature("web") else 3
	surface.append_from(_joint_mesh, 0, Transform3D(Basis.from_scale(Vector3.ONE * radius), at))


static func _add_paint(surface: SurfaceTool, a: Vector3, b: Vector3, thickness: float) -> void:
	var length := a.distance_to(b)
	if length < 0.001:
		return
	if _paint_mesh == null:
		_paint_mesh = BoxMesh.new()
		_paint_mesh.size = Vector3.ONE
	var dir := (b - a) / length
	if dir.y < 0.0:
		dir = -dir
	var basis := Basis(Quaternion(Vector3.UP, dir)) * Basis.from_scale(Vector3(thickness, length + thickness, 0.02))
	surface.append_from(_paint_mesh, 0, Transform3D(basis, (a + b) * 0.5))


static func _tube_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color.lightened(0.35)
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 3.2
	material.roughness = 0.2
	return material


static func _paint_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.9
	return material


static var _metal_material: StandardMaterial3D
static func _metal() -> StandardMaterial3D:
	if _metal_material == null:
		_metal_material = StandardMaterial3D.new()
		_metal_material.albedo_color = Color("#1a1f26")
		_metal_material.metallic = 0.6
		_metal_material.roughness = 0.45
	return _metal_material
