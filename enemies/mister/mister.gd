extends EnemyBase
## Mister: ranged. Holds at data.attack_range from its target, backs away when
## a player gets closer than keep_away, and lobs spore arcs that leave a short
## damage cloud where they land. Its attack_cooldown is the time between lobs.

const SporeProjectile := preload("res://enemies/mister/spore_projectile.gd")

@export var keep_away := 7.0
@export var flight_time := 1.2


func in_range_move(to_target: Vector3, buff: float) -> Vector3:
	if to_target.length() < keep_away:
		return -to_target.normalized() * data.move_speed * buff
	return Vector3.ZERO


func attack(victim: Node3D, amount: float) -> void:
	var spore := SporeProjectile.new()
	spore.damage_per_second = amount
	spore.source = self
	get_parent().add_child(spore, true)
	var start := global_position + Vector3.UP * 1.8
	spore.launch(start, victim.global_position, flight_time)
	attacked.emit(victim, amount)
