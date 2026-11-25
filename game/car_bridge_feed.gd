extends RefCounted
## Translates the running Cloud Play client's state to the car wire format.

const Cumulus := preload("res://enemies/boss/boss_cumulus.gd")
const SporeProjectile := preload("res://enemies/mister/spore_projectile.gd")
const SporeCloud := preload("res://enemies/mister/spore_cloud.gd")
const ReviveSpot := preload("res://player/revive_spot.gd")
const MAX_EVENTS := 256
const PHASE_NAMES := ["calm", "calm", "drizzle", "downpour", "clearing"]
const SUPPLY_KINDS := {"supply": "ammo", "ammo_box": "ammo", "ammo": "ammo",
	"health": "health", "suit": "suit", "scrap": "scrap", "scrap_large": "scrap"}

var lightning := false
var _tree: SceneTree
var _events: Array[Dictionary] = []
var _puddles := {}
var _hurt := 0.0
var _hurt_dir: Variant
var _hurt_ms := 0


func _init(tree: SceneTree) -> void:
	_tree = tree


func snapshot(me: Player, loot: RunLoot, tick: int, ack: int, now: int) -> Dictionary:
	var players := []
	var enemies := []
	var alive := 0
	for p: Player in GameManager.players():
		if p != me:
			players.append(_other_player(p))
		if p.state == "turned":
			enemies.append({"id": -p.get_multiplayer_authority(), "type": "turned",
				"pos": vec(p.global_position), "yaw": angle(p.rotation.y),
				"hp": fraction(p.health, p.turned_health), "anim": _walk_anim(p.velocity)})
			alive += 1
	for enemy: EnemyBase in _tree.get_nodes_in_group("enemies"):
		if enemy.is_queued_for_deletion():
			continue
		enemies.append(_enemy(enemy))
		alive += 1
	var boss := _tree.get_first_node_in_group("boss") as Cumulus
	if boss:
		enemies.append(_boss(boss))
		alive += int(not boss.dead)
	if tick % 4 == 1:
		_update_puddles()
	var phase: String = PHASE_NAMES[WeatherManager.phase]
	if WeatherManager.storm_state == WeatherManager.StormState.ACID_STORM:
		phase = "acid_storm"
	var snap := {"t": "snap", "tick": tick, "t_ms": now, "ack": ack,
		"you": _local_player(me), "players": players, "enemies": enemies,
		"pickups": _pickups(loot), "projectiles": _projectiles(loot),
		"weather": {"phase": phase, "intensity": angle(WeatherManager.storm_intensity),
			"wave": WeatherManager.wave, "phase_time_left": decimal(WeatherManager.phase_time_left),
			"lightning": lightning},
		"run": {"alive_enemies": alive, "wave": WeatherManager.wave, "endless": GameManager.endless,
			"shared_decon": GameManager.decon_charges, "score": GameManager.endless_score}}
	lightning = false
	return snap


func _local_player(p: Player) -> Dictionary:
	var holder := RunLoot.holder(p)
	var slots := []
	for item: ItemInstance in holder.slots:
		if not item:
			slots.append(null)
			continue
		var def := ItemCatalog.definition(item.id)
		var gun := def.kind == ItemDefinition.Kind.GUN
		slots.append({"item": item.id, "name": def.display_name, "ammo": item.count if gun else null,
			"mag": def.weapon.mag_size if gun else null,
			"reserve": int(holder.reserves.get(def.ammo_type, 0)) if gun else null,
			"count": 1 if gun else item.count})
	return {"id": p.get_multiplayer_authority(), "pos": vec(p.global_position), "vel": vec(p.velocity),
		"yaw": angle(p.rotation.y), "pitch": angle(p.head.rotation.x), "state": p.state,
		"hp": decimal(p.health), "hp_max": decimal(p.max_health), "suit": decimal(p.suit_integrity), "suit_max": 100,
		"exposed": p.exposed, "sheltered": p.sheltered, "in_puddle": p.in_puddle,
		"crouch": p.is_crouching, "aiming": p.aiming, "reloading": holder.reload_remaining() > 0.0,
		"slot": holder.current + 1, "slots": slots, "scrap": holder.scrap,
		"revive": angle(p.interact_progress) if p._hold_target is ReviveSpot else 0.0,
		"interact_progress": angle(p.interact_progress), "prompt": p.interact_prompt,
		"pouch": holder.active_pouch, "grenades": holder.grenades, "domes": holder.domes}


func _other_player(p: Player) -> Dictionary:
	var holder := RunLoot.holder(p)
	return {"id": p.get_multiplayer_authority(), "name": p.display_name, "pos": vec(p.global_position),
		"yaw": angle(p.rotation.y), "pitch": angle(p.head.rotation.x), "state": p.state,
		"item": holder.equipped_id, "crouch": null, "suit_color": "#" + p.suit_color.to_html(false),
		"skin": Cosmetics.skin_name(p.skin)}


func _enemy(enemy: EnemyBase) -> Dictionary:
	var anim := _walk_anim(enemy._net_vel if enemy._net_age < 0.15 else Vector3.ZERO)
	if enemy._attack_flash_left > 0.0:
		anim = "windup"
	if not enemy._net_has_target:
		anim = "spawn"
	var hp: Variant = fraction(enemy.health, enemy.max_health) if enemy.miniboss_wave > 0 else null
	return {"id": enemy.net_id, "type": enemy_type(enemy), "pos": vec(enemy.global_position),
		"yaw": angle(enemy.rotation.y), "hp": hp, "anim": anim}


func _boss(boss: Cumulus) -> Dictionary:
	var hp := 0.0
	var maximum := 0.0
	for i in boss.part_health.size():
		hp += boss.part_health[i]
		maximum += boss.part_max[i]
	return {"id": 0, "type": "cumulus", "pos": vec(boss.global_position), "yaw": angle(boss.rotation.y),
		"hp": 0.0 if boss.dead else fraction(hp, maximum), "anim": "die" if boss.dead else "idle"}


static func enemy_type(enemy: EnemyBase) -> String:
	return enemy.scene_file_path.get_file().get_basename()


static func _walk_anim(velocity: Vector3) -> String:
	return "walk" if Vector2(velocity.x, velocity.z).length_squared() > 0.05 else "idle"


func _pickups(loot: RunLoot) -> Array:
	var rows := []
	for record: Dictionary in loot.pickups.values():
		var node: WorldPickup = record.node
		var item := node.item.id if node.item else node.flavor
		var kind: String = SUPPLY_KINDS.get(node.flavor, "item")
		if node.item and ItemCatalog.definition(item).kind == ItemDefinition.Kind.GUN:
			kind = "weapon"
		rows.append({"id": node.pickup_id, "item": item, "pos": vec(node.global_position), "kind": kind})
	for crate: SupplyStation in _tree.get_nodes_in_group("crates"):
		if not crate.is_queued_for_deletion():
			var kind := "airdrop" if crate.is_drop else "station"
			rows.append({"id": -crate.get_instance_id(), "item": kind, "pos": vec(crate.global_position), "kind": kind})
	return rows


func _projectiles(loot: RunLoot) -> Array:
	var rows := []
	for projectile: WeaponProjectile in loot.projectiles.values():
		if not projectile.is_queued_for_deletion():
			rows.append({"id": projectile.seq, "kind": projectile.id, "pos": vec(projectile.global_position),
				"vel": vec(Vector3.ZERO if projectile.deployed else projectile.velocity)})
	for hazard in _tree.get_nodes_in_group("enemy_hazards"):
		if hazard is SporeProjectile and not hazard.is_queued_for_deletion():
			rows.append({"id": -hazard.hazard_id, "kind": "acid_glob" if hazard.acid else "spore",
				"pos": vec(hazard.global_position), "vel": vec(hazard._velocity)})
	return rows


func _update_puddles() -> void:
	var live := {}
	for puddle: Area3D in _tree.get_nodes_in_group("puddles"):
		var radius: float = puddle.radius()
		if radius > 0.25:
			_puddle(live, puddle.get_instance_id(), puddle.global_position, radius)
	for zone: SporeCloud in _tree.get_nodes_in_group("spore_clouds"):
		if zone.acid and not zone.is_queued_for_deletion():
			for shape: CollisionShape3D in zone._shapes:
				_puddle(live, shape.get_instance_id(), shape.global_position, shape.shape.radius)
	for id: int in _puddles:
		if not live.has(id):
			var row: Dictionary = _puddles[id].duplicate()
			row.on = false
			event(row)
	_puddles = live


func _puddle(live: Dictionary, id: int, at: Vector3, radius: float) -> void:
	var row: Dictionary = _puddles.get(id, {})
	if row.is_empty() or absf(row.radius - radius) >= 0.10:
		row = {"e": "puddle", "id": id, "pos": vec(at), "radius": decimal(radius), "on": true}
		event(row)
	live[id] = row


func event(row: Dictionary) -> void:
	if _events.size() < MAX_EVENTS:
		_events.append(row)


func hurt(amount: float) -> void:
	_hurt += amount


func hurt_from(at: Vector3, player: Player) -> void:
	_hurt_dir = vec((at - player.global_position).normalized())
	_hurt_ms = Time.get_ticks_msec()


func take_events() -> Array[Dictionary]:
	if _hurt > 0.0:
		var direction: Variant = _hurt_dir if Time.get_ticks_msec() - _hurt_ms < 250 else null
		event({"e": "hurt", "dir": direction, "amt": decimal(_hurt)})
		_hurt = 0.0
		_hurt_dir = null
	var events := _events
	_events = []
	return events


static func vec(value: Vector3) -> Array:
	return [decimal(value.x), decimal(value.y), decimal(value.z)]


static func decimal(value: float) -> float:
	return roundf(value * 100.0) / 100.0


static func angle(value: float) -> float:
	return roundf(value * 1000.0) / 1000.0


static func fraction(value: float, maximum: float) -> float:
	return angle(clampf(value / maxf(maximum, 0.001), 0.0, 1.0))
