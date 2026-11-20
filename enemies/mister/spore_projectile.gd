extends Node3D
## A spore glob on a ballistic arc. When it lands (or hits something) it leaves
## a SporeCloud. Spawned by the host; damage happens only on the host.

const SporeCloud := preload("res://enemies/mister/spore_cloud.gd")

var damage_per_second := 6.0
var source: Node = null
var acid := false

var _velocity := Vector3.ZERO
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _age := 0.0
var _trail_left := 0.0
var _marker: MeshInstance3D


func _ready() -> void:
	add_to_group("enemy_hazards")
	var mesh := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radial_segments = 12
	sphere.rings = 6
	sphere.radius = 0.2
	sphere.height = 0.4
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("#ecfb5b") if acid else Color(0.5, 1.0, 0.3)
	material.emission_enabled = true
	material.emission = material.albedo_color
	sphere.material = material
	mesh.mesh = sphere
	add_child(mesh)


## Aim so the glob lands on `target` after `time` seconds.
func launch(from: Vector3, target: Vector3, time: float) -> void:
	global_position = from
	_velocity = (target - from) / time + Vector3.UP * 0.5 * _gravity * time
	# Landing ring at the target so players can step out before it bursts.
	_marker = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.outer_radius = 3.0 if acid else 2.5
	torus.inner_radius = torus.outer_radius - .20
	torus.rings = 24
	torus.ring_segments = 4
	_marker.mesh = torus
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(1.0, .87, .22, .9) if acid else Color(0.7, 1.0, 0.3, 0.7)
	_marker.material_override = material
	get_parent().add_child(_marker)
	_marker.global_position = target + Vector3.UP * 0.06
	_marker.scale = Vector3.ONE * 0.3
	_marker.create_tween().tween_property(_marker, "scale", Vector3.ONE, time)


func _physics_process(delta: float) -> void:
	if GameManager.victory_locked or GameManager.finished:
		queue_free()
		return
	_age += delta
	_velocity.y -= _gravity * delta
	var step := _velocity * delta
	var query := PhysicsRayQueryParameters3D.create(global_position, global_position + step, 1 << 0)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty() or _age > 5.0:
		_burst(hit.get("position", global_position))
		return
	global_position += step
	_trail_left -= delta
	if _trail_left <= 0.0 and not Net.dedicated:
		_trail_left = 0.05
		var color := Color(.84, .83, .18, .8) if acid else Color(0.55, 1.0, 0.3, 0.7)
		ShotFX.puff(get_parent(), global_position, color, 0.1, 0.35)


func _exit_tree() -> void:
	if is_instance_valid(_marker):
		_marker.queue_free()


func _burst(at: Vector3) -> void:
	if acid:
		var query := PhysicsRayQueryParameters3D.create(at + Vector3.UP * .16, at + Vector3.DOWN * 12.0, 1)
		var floor_hit := get_world_3d().direct_space_state.intersect_ray(query)
		at = floor_hit.get("position", at)
	Sound.play_at("smog_splash" if acid else "spore_burst", at)
	var cloud := SporeCloud.new()
	cloud.damage_per_second = damage_per_second
	cloud.source = source if is_instance_valid(source) else null
	if acid:
		cloud.acid = true
		cloud.lifetime = 8.0
		cloud.radius = 3.0
	get_parent().add_child(cloud, true)
	cloud.global_position = at
	queue_free()
