class_name BuildingKit
extends RefCounted
## Geometry is authored in metres from the centre of the collision box's floor.
## +Z is the entrance. Each material is one indexed surface of the final mesh.

const CREAM := "f5dfaf"
const INK := "283849"
const CHROME := "afc6c9"
const NIGHT := "294758"
const BLUE_GLASS := "507f89"
const LAMP := "ffcf86"
const RED := "c84448"
const MINT := "9adaca"
const BRICK := "d39278"
const TEXTURES := {
	"brick": preload("res://props/brick.png"),
	"stucco": preload("res://props/stucco.png"),
	"tile": preload("res://props/tile.png"),
	"shingles_teal": preload("res://assets/textures/shingles_teal.png"),
	"siding": preload("res://assets/textures/siding.png"),
	"sidewalk": preload("res://assets/textures/sidewalk.png"),
	"wood": preload("res://assets/textures/wood.png"),
}

var size: Vector3
var front: float
var frame := Transform3D.IDENTITY
var surfaces := {}
static var materials := {}


func _init(dimensions: Vector3) -> void:
	size = dimensions
	front = size.z * 0.5


## Keys combine paint, optional world-triplanar texture, and optional emission.
func surface(key: String) -> SurfaceTool:
	if not surfaces.has(key):
		var tool := SurfaceTool.new()
		tool.begin(Mesh.PRIMITIVE_TRIANGLES)
		if not materials.has(key):
			var fields := key.split("/")
			var mat := StandardMaterial3D.new()
			mat.albedo_color = Color(fields[0])
			mat.roughness = 0.85
			if fields.size() > 1 and fields[1] == "lit":
				mat.emission_enabled = true
				mat.emission = mat.albedo_color
				mat.emission_energy_multiplier = 0.48
			elif fields.size() > 1:
				mat.albedo_texture = TEXTURES[fields[1]]
				mat.uv1_triplanar = true
				mat.uv1_world_triplanar = true
				mat.uv1_scale = Vector3.ONE * 0.52
				mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
			materials[key] = mat
		tool.set_material(materials[key])
		surfaces[key] = tool
	return surfaces[key]


func finish() -> MeshInstance3D:
	var mesh := ArrayMesh.new()
	for tool: SurfaceTool in surfaces.values():
		tool.index()
		tool.commit(mesh)
	var model := MeshInstance3D.new()
	model.name = "Architecture"
	model.mesh = mesh
	return model


## Godot's front faces wind clockwise. The supplied outward direction also
## disambiguates the winding of sloped roofs and turned facade sections.
func face(key: String, points: PackedVector3Array, outward: Vector3) -> void:
	var normal := (points[2] - points[0]).cross(points[1] - points[0]).normalized()
	if normal.dot(outward) < 0:
		points.reverse()
		normal = -normal
	var tool := surface(key)
	for i in range(1, points.size() - 1):
		for p: Vector3 in [points[0], points[i], points[i + 1]]:
			tool.set_normal(frame.basis * normal)
			tool.set_uv(Vector2(p.x + p.z, p.y))
			tool.add_vertex(frame * p)


func box(key: String, x: float, y: float, z: float, w: float, h: float, d: float) -> void:
	var lo := Vector3(x - w * 0.5, y - h * 0.5, z - d * 0.5)
	var hi := Vector3(x + w * 0.5, y + h * 0.5, z + d * 0.5)
	var a := Vector3(lo.x, lo.y, hi.z)
	var b := Vector3(hi.x, lo.y, hi.z)
	var c := Vector3(hi.x, hi.y, lo.z)
	var e := Vector3(lo.x, hi.y, lo.z)
	var f := Vector3(lo.x, hi.y, hi.z)
	var g := Vector3(hi.x, lo.y, lo.z)
	face(key, [a, f, hi, b], Vector3.BACK)
	face(key, [lo, g, c, e], Vector3.FORWARD)
	face(key, [lo, e, f, a], Vector3.LEFT)
	face(key, [b, hi, c, g], Vector3.RIGHT)
	face(key, [f, e, c, hi], Vector3.UP)
	face(key, [lo, a, b, g], Vector3.DOWN)


func shell(key: String) -> void:
	box(key, 0, size.y * 0.5, 0, size.x, size.y, size.z)


## Set a work plane for front, back and side joinery. Distances along its Z
## axis are measured outwards from the wall surface.
func wall(yaw: float) -> void:
	var basis := Basis(Vector3.UP, yaw)
	var distance := front if absf(basis.z.z) > 0.5 else size.x * 0.5
	frame = Transform3D(basis, basis.z * distance)


func window(
	x: float, y: float, w: float, h: float, panes: int, trim: String, glass: String, sash := false
) -> void:
	box(trim, x, y, 0.055, w, h, 0.12)
	box(glass, x, y, 0.125, w - 0.16, h - 0.16, 0.045)
	for i in range(1, panes):
		box(trim, x - w * 0.5 + w * i / panes, y, 0.16, 0.075, h - 0.11, 0.055)
	if sash:
		box(trim, x, y + h * 0.1, 0.175, w - 0.12, 0.075, 0.05)
	box(trim, x, y - h * 0.5, 0.11, w + 0.14, 0.11, 0.24)


func door(x: float, paint: String, trim: String, glazed := true, floor_y := 0.0) -> void:
	box(trim, x, floor_y + 1.16, 0.06, 1.28, 2.32, 0.13)
	box(paint, x, floor_y + 1.08, 0.14, 1.07, 2.16, 0.06)
	if glazed:
		box(BLUE_GLASS, x, floor_y + 1.55, 0.183, 0.78, 0.93, 0.035)
	box(trim, x, floor_y + 0.5, 0.185, 0.79, 0.61, 0.04)
	box(paint, x, floor_y + 0.5, 0.21, 0.65, 0.47, 0.03)
	box(CHROME, x + 0.35, floor_y + 1.01, 0.24, 0.07, 0.19, 0.11)


func disc(key: String, x: float, y: float, z: float, radius: float, sides := 12) -> void:
	var pts := PackedVector3Array()
	for i in sides:
		var a := TAU * i / sides
		pts.append(Vector3(x + radius * cos(a), y + radius * sin(a), z))
	face(key, pts, Vector3.BACK)


## Hipped ends are controlled by ridge_inset. Offset the ridge for a saltbox,
## or rotate the work frame to turn the gable towards the street.
func ridge_roof(
	x: float,
	y: float,
	z: float,
	w: float,
	d: float,
	rise: float,
	ridge_inset: float,
	offset: float,
	roof: String,
	gable: String
) -> void:
	var fl := Vector3(x - w / 2, y, z + d / 2)
	var fr := Vector3(x + w / 2, y, z + d / 2)
	var bl := Vector3(x - w / 2, y, z - d / 2)
	var br := Vector3(x + w / 2, y, z - d / 2)
	var left := Vector3(x - w / 2 + ridge_inset, y + rise, z + offset)
	var right := Vector3(x + w / 2 - ridge_inset, y + rise, z + offset)
	face(roof, [fl, left, right, fr], Vector3.UP)
	face(roof, [bl, br, right, left], Vector3.UP)
	var end := roof if ridge_inset > 0.01 else gable
	face(end, [fl, bl, left], Vector3.LEFT)
	face(end, [fr, right, br], Vector3.RIGHT)
	box(gable, x, y - 0.08, z, w, 0.16, d)


## Four pitched faces between two rectangular courses (mansards / gambrels).
func slope_course(
	x: float, y: float, z: float, w: float, d: float, top_w: float, top_d: float, rise: float, key: String
) -> void:
	var ring := PackedVector3Array()
	var top := PackedVector3Array()
	for corner: Vector2 in [Vector2(-1, 1), Vector2(1, 1), Vector2(1, -1), Vector2(-1, -1)]:
		ring.append(Vector3(x + corner.x * w / 2, y, z + corner.y * d / 2))
		top.append(Vector3(x + corner.x * top_w / 2, y + rise, z + corner.y * top_d / 2))
	for i in 4:
		var j := (i + 1) % 4
		face(key, [ring[i], ring[j], top[j], top[i]], (ring[i] + ring[j]) * 0.5 - Vector3(x, y, z))
	face(key, top, Vector3.UP)


func rooftop_unit(x: float, z: float, width := 1.4) -> void:
	frame = Transform3D.IDENTITY
	var y := size.y
	box(INK, x, y + 0.09, z, width + 0.13, 0.18, 1.16)
	box(CHROME, x, y + 0.43, z, width, 0.56, 1.05)
	for i in 4:
		box(INK, x, y + 0.24 + i * 0.105, z + 0.535, width - 0.22, 0.055, 0.055)


func chimney(x: float, z: float, top: float, width: float, masonry: String) -> void:
	var bottom := size.y - 0.15
	box(masonry, x, (bottom + top) * 0.5, z, width, top - bottom, 0.76)
	box(CREAM, x, top, z, width + 0.17, 0.18, 0.92)
	box(INK, x, top + 0.13, z, width * 0.64, 0.13, 0.52)
