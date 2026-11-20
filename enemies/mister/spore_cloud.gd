extends Area3D
## Damage cloud left by a Mister's spore, a Smog's acid glob, or the Spores
## mutation. Damages players standing in it, on the host only.
##
## Create clouds with SporeCloud.spawn(), not .new():
## - A cloud landing on top of a cloud of the same kind MERGES into it (bigger
##   area, refreshed lifetime) instead of stacking damage.
## - A cloud landing under an active Shield Dome fizzles, and existing clouds
##   inside a fresh dome dissipate: the dome keeps acid and spores out.
## - A player takes damage from at most one cloud per tick, and none
##   while under a dome.

const MAX_RADIUS_ACID := 5.5
const MAX_RADIUS_SPORE := 4.5

var damage_per_second := 6.0
var radius := 2.5
var lifetime := 4.0
var source: Node = null
var acid := false
var hazard_id := 0

var _age := 0.0
var _damage_time := 0.0
var _mesh_material := StandardMaterial3D.new()
var _shape_resource: Shape3D
var _visuals: Array[Node3D] = []
var _base_radius := 2.5

## body instance id -> msec it was last damaged by any cloud (one tick per 0.2 s).
static var _hit_frame := {}


## Spawn (or merge into) a cloud at `at`. Returns the cloud that now covers
## the spot, or null if a Shield Dome kept it out. Runs the same way on every
## peer, so all copies merge alike.
static func spawn(parent: Node, at: Vector3, is_acid: bool, cloud_radius: float, cloud_lifetime: float,
		dps: float, cloud_source: Node = null, cloud_hazard_id := 0) -> Node:
	var tree := parent.get_tree()
	if _in_dome(at, tree, cloud_radius * 0.35):
		if not Net.dedicated:
			ShotFX.puff(parent, at + Vector3.UP * 0.3, Color(0.55, 0.95, 1.0, 0.7), 0.4, 0.5)
		return null
	for node in tree.get_nodes_in_group("spore_clouds"):
		var other := node as Area3D
		if other == null or other.is_queued_for_deletion() or bool(other.get("acid")) != is_acid:
			continue
		var offset := at - other.global_position
		offset.y = 0.0
		var other_radius := float(other.get("radius"))
		if offset.length() < other_radius + cloud_radius * 0.6:
			other.call("_absorb", at, cloud_radius, cloud_lifetime, dps)
			if cloud_hazard_id > 0 and int(other.get("hazard_id")) == 0:
				other.set("hazard_id", cloud_hazard_id)
			return other
	var cloud := (load("res://enemies/mister/spore_cloud.gd") as GDScript).new() as Area3D
	cloud.set("acid", is_acid)
	cloud.set("radius", cloud_radius)
	cloud.set("lifetime", cloud_lifetime)
	cloud.set("damage_per_second", dps)
	cloud.set("source", cloud_source if is_instance_valid(cloud_source) else null)
	cloud.set("hazard_id", cloud_hazard_id)
	parent.add_child(cloud, true)
	cloud.global_position = at
	return cloud


static func _in_dome(point: Vector3, tree: SceneTree, margin := 0.0) -> bool:
	for dome in tree.get_nodes_in_group("active_flares"):
		if dome.is_queued_for_deletion() or str(dome.get("id")) != "shield_dome":
			continue
		var offset: Vector3 = point - dome.global_position
		offset.y = 0.0
		if offset.length() <= float(dome.data.effect_radius) + margin:
			return true
	return false


## Merge another landing into this cloud: the areas add up (capped), the
## center shifts toward the new one by area, the clock refreshes. Damage does
## not stack: it takes the stronger of the two.
func _absorb(at: Vector3, other_radius: float, other_lifetime: float, dps: float) -> void:
	var a1 := radius * radius
	var a2 := other_radius * other_radius
	var center := (global_position * a1 + at * a2) / (a1 + a2)
	center.y = global_position.y
	global_position = center
	radius = minf(sqrt(a1 + a2), MAX_RADIUS_ACID if acid else MAX_RADIUS_SPORE)
	var left := maxf(lifetime - _age, other_lifetime)
	_age = 0.0
	lifetime = left
	damage_per_second = maxf(damage_per_second, dps)
	_apply_radius()


func _apply_radius() -> void:
	if _shape_resource is CylinderShape3D:
		(_shape_resource as CylinderShape3D).radius = radius
	elif _shape_resource is SphereShape3D:
		(_shape_resource as SphereShape3D).radius = radius
	var s := radius / _base_radius
	for visual in _visuals:
		visual.scale = Vector3(s, 1.0 if acid else s, s)


func _ready() -> void:
	add_to_group("spore_clouds")
	add_to_group("enemy_hazards")
	collision_layer = 0
	collision_mask = 1 << 1  # players
	monitorable = false
	_base_radius = radius
	var shape := CollisionShape3D.new()
	if acid:
		var cylinder := CylinderShape3D.new()
		cylinder.radius = radius
		cylinder.height = .36
		_shape_resource = cylinder
	else:
		var sphere_shape := SphereShape3D.new()
		sphere_shape.radius = radius
		_shape_resource = sphere_shape
	shape.shape = _shape_resource
	add_child(shape)
	if Net.dedicated:
		return

	var mesh := MeshInstance3D.new()
	if acid:
		var disc := CylinderMesh.new()
		disc.top_radius = radius
		disc.bottom_radius = radius
		disc.height = .024
		disc.radial_segments = 20
		mesh.mesh = disc
		mesh.position.y = .05
	else:
		var sphere := SphereMesh.new()
		sphere.radial_segments = 12
		sphere.rings = 6
		sphere.radius = radius
		sphere.height = radius * 2.0
		mesh.mesh = sphere
	_mesh_material.albedo_color = Color(.64, .84, .12, .65) if acid else Color(0.45, 0.9, 0.25, 0.35)
	_mesh_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mesh_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mesh_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.material_override = _mesh_material
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mesh)
	_visuals.append(mesh)
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = radius - 0.08
	torus.outer_radius = radius
	torus.rings = 24
	torus.ring_segments = 4
	ring.mesh = torus
	ring.position.y = 0.075
	var ring_material := StandardMaterial3D.new()
	ring_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_material.albedo_color = Color("#e7fc45") if acid else Color(0.7, 1.0, 0.3)
	ring.material_override = ring_material
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring)
	_visuals.append(ring)


func _physics_process(delta: float) -> void:
	_age += delta
	# A dome deployed over this cloud burns it off quickly.
	if _in_dome(global_position, get_tree()):
		_age += delta * 6.0
	_mesh_material.albedo_color.a = (.65 if acid else .35) * clampf(1.0 - _age / lifetime, 0.0, 1.0)
	if _age >= lifetime or GameManager.victory_locked or GameManager.finished:
		queue_free()
		return
	if not Net.is_host() or damage_per_second <= 0.0:
		return
	_damage_time += delta
	if _damage_time < 0.2:
		return
	var amount := damage_per_second * _damage_time
	_damage_time = 0.0
	var now := Time.get_ticks_msec()
	for body in get_overlapping_bodies():
		if not body is Player:
			continue
		var id := body.get_instance_id()
		if now - int(_hit_frame.get(id, -100000)) < 190:
			continue  # An overlapping cloud already ticked on this player.
		if _in_dome(body.global_position, get_tree()):
			continue
		if acid:
			var ray := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * .35, body.global_position + Vector3.UP * .35, 1)
			if not get_world_3d().direct_space_state.intersect_ray(ray).is_empty():
				continue
		_hit_frame[id] = now
		# The cloud outlives the enemy that spat it out.
		body.take_damage(amount, source if is_instance_valid(source) else null, true)
	if _hit_frame.size() > 64:
		_hit_frame.clear()
