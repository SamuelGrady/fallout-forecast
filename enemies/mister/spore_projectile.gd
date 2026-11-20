extends Node3D
## A spore glob on a ballistic arc. When it lands (or hits something) it leaves
## a SporeCloud. Spawned by the host; damage happens only on the host.

const SporeCloud := preload("res://enemies/mister/spore_cloud.gd")

var damage_per_second := 6.0
var source: Node = null

var _velocity := Vector3.ZERO
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _age := 0.0
var _trail_left := 0.0
var _marker: MeshInstance3D


func _ready() -> void:
	var mesh := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.2
	sphere.height = 0.4
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.5, 1.0, 0.3)
	material.emission_enabled = true
	material.emission = Color(0.4, 0.9, 0.2)
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
	torus.inner_radius = 2.3
	torus.outer_radius = 2.5
	torus.rings = 24
	_marker.mesh = torus
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(0.7, 1.0, 0.3, 0.7)
	_marker.material_override = material
	get_parent().add_child(_marker)
	_marker.global_position = target + Vector3.UP * 0.06
	_marker.scale = Vector3.ONE * 0.3
	_marker.create_tween().tween_property(_marker, "scale", Vector3.ONE, time)


func _physics_process(delta: float) -> void:
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
	if _trail_left <= 0.0:
		_trail_left = 0.05
		ShotFX.puff(get_parent(), global_position, Color(0.55, 1.0, 0.3, 0.7), 0.1, 0.35)


func _exit_tree() -> void:
	if is_instance_valid(_marker):
		_marker.queue_free()


func _burst(at: Vector3) -> void:
	Sound.play_at("spore_burst", at)
	var cloud := SporeCloud.new()
	cloud.damage_per_second = damage_per_second
	cloud.source = source if is_instance_valid(source) else null
	get_parent().add_child(cloud, true)
	cloud.global_position = at
	queue_free()
