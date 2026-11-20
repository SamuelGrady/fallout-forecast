extends "res://enemies/weather_enemy.gd"
## Disappears under a live puddle, then drags its victim toward the water.

var _puddle: Node3D
var _submerged := false
var _ripple: MeshInstance3D
var _ripple_time := 0.0
var _surface_left := 0.0
var _retreat_left := 0.0
var _ambush_used := false
var _lurk_left := 0.0
static var _ripple_mesh: TorusMesh
static var _ripple_material: StandardMaterial3D


func bind_puddle(puddle: Node3D) -> void:
	_puddle = puddle
	_puddle.set_meta("undertow", true)
	_lurk_left = 14.0
	global_position = _puddle.global_position + Vector3.UP * .09
	announce_tell("undertow_lurk", 0.0, -15.0)


func _wet() -> bool:
	return is_instance_valid(_puddle) and float(_puddle.call("radius")) > .25


func _physics_process(delta: float) -> void:
	if _submerged:
		_lurk_left -= delta
		if not _wet() or _lurk_left <= 0.0:
			_emerge(null)
		else:
			var victim := choose_target()
			var reach := float(_puddle.call("radius")) + 2.0
			if victim and global_position.distance_to(victim.global_position) <= reach and _has_attack_los(victim):
				_emerge(victim)
		_record_position()
		return
	if _stagger_left > 0.0:
		super._physics_process(delta)
		return
	if _surface_left > 0.0:
		_surface_left -= delta
		super._physics_process(delta)
		if _surface_left <= 0.0 and _wet():
			_retreat_left = 5.0
			_repath(_puddle.global_position)
		return
	if _retreat_left > 0.0 and _wet():
		_retreat_left -= delta
		if global_position.distance_to(_puddle.global_position) < .75:
			bind_puddle(_puddle)
			return
		var direction := _path_direction(_puddle.global_position)
		_face(direction)
		move_special(delta, direction * data.move_speed * speed_multiplier())
		return
	super._physics_process(delta)


func _emerge(victim: Node3D) -> void:
	_surface_left = 5.5
	_ambush_used = false
	if victim:
		_face(flat_direction(victim.global_position))
		_attack_victim = victim
		_attack_amount = data.damage * damage_multiplier()
		_windup_left = .6
		_attack_timer = data.attack_cooldown
	announce_tell("undertow_emerge", .6, -8.0)


func harpoon_surface() -> void:
	_retreat_left = 0.0
	if _submerged:
		_set_submerged(false)
		_emerge(null)
	_surface_left = maxf(_surface_left, 6.0)


func expose_for_cleanup() -> void:
	_release_puddle()
	if _submerged:
		_emerge(null)


func _exit_tree() -> void:
	_release_puddle()


func _release_puddle() -> void:
	if is_instance_valid(_puddle):
		_puddle.remove_meta("undertow")
	_puddle = null


func sync_tells(peer: int) -> void:
	if _submerged:
		get_parent()._play_enemy_tell.rpc_id(peer, net_id, "undertow_lurk", 0.0, -15.0)


func _can_attack(victim: Node3D) -> bool:
	if not _ambush_used and _wet() and _surface_left > 0.0:
		var reach := float(_puddle.call("radius")) + 2.15
		return victim.get("state") == "ok" and global_position.distance_to(victim.global_position) <= reach and _has_attack_los(victim)
	return super._can_attack(victim)


func _begin_attack(victim: Node3D, amount: float) -> void:
	_attack_victim = victim
	_attack_amount = amount
	_windup_left = .45
	announce_tell("undertow_emerge", _windup_left, -12.0)


func attack(victim: Node3D, amount: float) -> void:
	if not _ambush_used and victim.get("state") == "ok" and victim.has_method("pull_from_enemy"):
		var water := _puddle.global_position if _wet() else global_position
		var toward := water - victim.global_position
		toward.y = 0.0
		victim.pull_from_enemy(toward.normalized() * (9.0 if is_elite else 7.5))
		GameManager.achievement_event("undertow_drag", victim)
	_ambush_used = true
	super.attack(victim, amount)


func play_tell(cue: String, duration: float, volume: float) -> void:
	if cue == "undertow_lurk":
		_set_submerged(true)
	elif cue == "undertow_emerge":
		_set_submerged(false)
		if duration >= .6:
			show_warning(duration, 2.8, Color(.32, 1.0, .89, .78))
	super.play_tell(cue, duration, volume)


func _set_submerged(value: bool) -> void:
	_submerged = value
	if _model:
		_model.visible = not value
	collision_layer = 0 if value else 4
	if _ripple == null and value and not Net.dedicated:
		if _ripple_mesh == null:
			_ripple_mesh = TorusMesh.new()
			_ripple_mesh.inner_radius = .87
			_ripple_mesh.outer_radius = 1.0
			_ripple_mesh.rings = 20
			_ripple_mesh.ring_segments = 4
			_ripple_material = StandardMaterial3D.new()
			_ripple_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			_ripple_material.albedo_color = Color("#78d9cb")
		_ripple = MeshInstance3D.new()
		_ripple.mesh = _ripple_mesh
		_ripple.material_override = _ripple_material
		_ripple.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_ripple)
	if _ripple:
		_ripple.visible = value


func _process(delta: float) -> void:
	super._process(delta)
	if _submerged and _ripple:
		_ripple_time = fmod(_ripple_time + delta * 1.4, 1.0)
		var radius := .44 + _ripple_time * .70
		_ripple.scale = Vector3(radius, .12, radius)


func take_damage(amount: float, source: Node = null) -> void:
	if not _submerged or GameManager.victory_locked:
		super.take_damage(amount, source)


func make_corpse(throw_vec: Vector3) -> void:
	if _model:
		_model.show()
	super.make_corpse(throw_vec)
