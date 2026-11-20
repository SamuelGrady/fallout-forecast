extends "res://enemies/weather_enemy.gd"
## Inflates in a marked blast radius. Killing it early can start a chain reaction.

const SHOCK_COLOR := Color("#ff9b65")
var _fuse := 0.0
var _fuse_time := 0.0
var _natural_blast := false
var _blast_damage := 0.0
var _blast_visual := 0.0


func _physics_process(delta: float) -> void:
	if _fuse <= 0.0:
		super._physics_process(delta)
		return
	_fuse = maxf(0.0, _fuse - delta)
	move_special(delta, Vector3.ZERO)
	if _fuse == 0.0:
		_natural_blast = true
		health = 0.0
		die()


func _begin_attack(_victim: Node3D, amount: float) -> void:
	_fuse_time = 1.38 if is_elite else 1.72
	_fuse = _fuse_time
	_blast_damage = amount
	announce_tell("thunderhead_fuse", _fuse_time, -5.0)


func _blast_radius() -> float:
	return 6.3 if is_elite else 5.1


func _physics_blast(early: bool) -> void:
	if GameManager.victory_locked or not GameManager.run_active or GameManager.finished:
		return
	var radius := _blast_radius() * (.56 if early else 1.0)
	var amount := data.damage * damage_multiplier() * .38 if early else _blast_damage
	GameManager.broadcast_blast(global_position + Vector3.UP * .45, radius * .59, SHOCK_COLOR)
	for victim in targetable_players():
		if global_position.distance_to(victim.global_position) <= radius and _has_attack_los(victim):
			victim.take_damage(amount, self)
	if early:
		var source := _last_hit_by if is_instance_valid(_last_hit_by) else null
		for node in get_tree().get_nodes_in_group("enemies"):
			var enemy := node as EnemyBase
			if enemy != self and enemy.health > 0.0 and global_position.distance_to(enemy.global_position) <= radius and _has_attack_los(enemy):
				enemy.take_damage(amount * 2.1, source)
				enemy.knockback(flat_direction(enemy.global_position) * 5.0)


func die() -> void:
	if _dead:
		return
	Perf.mark("thunderhead blast")
	# Defer so chained Thunderheads each complete their own death before blasting.
	_physics_blast.call_deferred(not _natural_blast)
	super.die()


func play_tell(cue: String, duration: float, volume: float) -> void:
	super.play_tell(cue, minf(duration, .28), volume)
	if cue == "thunderhead_fuse":
		_blast_visual = duration
		_fuse_time = duration
		show_warning(duration, _blast_radius(), Color(1.0, .35, .17, .91))


func _process(delta: float) -> void:
	super._process(delta)
	if not _model:
		return
	_blast_visual = maxf(0.0, _blast_visual - delta)
	var charge := 0.0
	var focus := target if Net.is_host() else get_tree().get_first_node_in_group("local_player") as Node3D
	if _blast_visual > 0.0:
		charge = 1.0 - _blast_visual / _fuse_time
	elif is_instance_valid(focus):
		charge = clampf((11.0 - _flat_distance(focus.global_position)) / 20.0, 0.0, .38)
	_model.charge_amount = move_toward(_model.charge_amount, charge, delta * 2.4)


func is_critical_hit(height: float, _source: Node) -> bool:
	return height > 1.14 and height < 1.50
