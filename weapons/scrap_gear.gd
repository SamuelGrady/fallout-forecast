extends RefCounted
## Shared gear silhouette for the scrap icon and the extruded world pickup.

const BORE_RADIUS := 0.43
const ROOT_RADIUS := 0.70
const HALF_DEPTH := 0.15
const TEETH := 8

static var _mesh: ArrayMesh


static func outline() -> PackedVector2Array:
	var points := PackedVector2Array()
	for tooth in TEETH:
		var angle := tooth * TAU / TEETH
		points.append(Vector2.from_angle(angle - 0.25) * ROOT_RADIUS)
		points.append(Vector2.from_angle(angle - 0.14))
		points.append(Vector2.from_angle(angle + 0.14))
		points.append(Vector2.from_angle(angle + 0.25) * ROOT_RADIUS)
	return points


static func bore_point(outer: Vector2) -> Vector2:
	return outer.normalized() * BORE_RADIUS


static func mesh() -> ArrayMesh:
	if _mesh != null:
		return _mesh
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var profile := outline()
	for i in profile.size():
		var outer_a := profile[i]
		var outer_b := profile[(i + 1) % profile.size()]
		var inner_a := bore_point(outer_a)
		var inner_b := bore_point(outer_b)
		var front_outer_a := Vector3(outer_a.x, outer_a.y, HALF_DEPTH)
		var front_outer_b := Vector3(outer_b.x, outer_b.y, HALF_DEPTH)
		var front_inner_a := Vector3(inner_a.x, inner_a.y, HALF_DEPTH)
		var front_inner_b := Vector3(inner_b.x, inner_b.y, HALF_DEPTH)
		var depth := Vector3.FORWARD * (2.0 * HALF_DEPTH)
		var back_outer_a := front_outer_a + depth
		var back_outer_b := front_outer_b + depth
		var back_inner_a := front_inner_a + depth
		var back_inner_b := front_inner_b + depth
		_add_quad(surface, front_inner_a, front_inner_b, front_outer_b, front_outer_a)
		_add_quad(surface, back_inner_a, back_outer_a, back_outer_b, back_inner_b)
		_add_quad(surface, front_outer_a, front_outer_b, back_outer_b, back_outer_a)
		_add_quad(surface, front_inner_a, back_inner_a, back_inner_b, front_inner_b)
	_mesh = surface.commit()
	return _mesh


static func _add_quad(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	# Godot's front faces use clockwise winding.
	surface.set_normal((c - a).cross(b - a).normalized())
	for vertex: Vector3 in [a, b, c, a, c, d]:
		surface.add_vertex(vertex)
