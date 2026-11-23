class_name RunLoot
extends Node3D
## Scene authority (peer 1). World ids are scoped to this run.
const STARTER_KITS := ["pump_shotgun", "nail_driver", "service_revolver"]
var starter_chosen := false
var _starter_claims: Dictionary = {}
var run_id := 0
var clock := 0.0
var _next_id := 0
var _next_instance := 0
var pickups: Dictionary = {}
var projectiles: Dictionary = {}
var discoveries: Array[String] = []
var _scan_at := 0.0
var _sync_at := 0.0

static func find(tree: SceneTree) -> RunLoot:
	return tree.get_first_node_in_group("run_loot") as RunLoot

func _ready() -> void:
	add_to_group("run_loot")
	if Net.is_host():
		Net.run_peer_loaded.connect(sync_to_peer)

func begin(id: int) -> void:
	run_id = id
	for player: Node in GameManager.players():
		holder(player).send_state()

func starter_available() -> bool:
	return run_id > 0 and not starter_chosen and WeatherManager.wave == 1 and WeatherManager.running

func choose_starter(index: int) -> void:
	if not starter_available() or not Net.can_send_run_rpc():
		return
	if Net.is_host():
		_grant_starter(run_id, Net.local_id(), index)
	else:
		_request_starter.rpc_id(1, run_id, index)

@rpc("any_peer", "call_remote", "reliable")
func _request_starter(run: int, index: int) -> void:
	var peer := multiplayer.get_remote_sender_id()
	if Net.is_host() and Net.run_peers.has(peer):
		_grant_starter(run, peer, index)

func _grant_starter(run: int, peer: int, index: int) -> void:
	if run != run_id or not GameManager.run_active or GameManager.finished or WeatherManager.wave != 1 \
			or _starter_claims.has(peer) or index < 0 or index >= STARTER_KITS.size():
		return
	var player := GameManager.player_for_peer(peer)
	if player == null:
		return
	var inventory := holder(player)
	if not inventory.can_act():
		return
	var kit_id: String = STARTER_KITS[index]
	var slot0 := inventory.slots[0]
	var replace_slot0 := slot0 == null or slot0.id == "service_revolver"
	var fallback_slot := -1 if replace_slot0 else inventory.slots.find(null)
	if not replace_slot0 and fallback_slot < 0:
		return
	var item := make_item(kit_id)
	if item == null:
		return
	_starter_claims[peer] = true
	if replace_slot0:
		inventory.slots[0] = item
		var definition := ItemCatalog.definition(item.id)
		if definition and definition.kind == ItemDefinition.Kind.GUN and not definition.ammo_type.is_empty():
			var cap: int = int(ItemCatalog.CAPS[definition.ammo_type])
			var starter: int = cap if item.id == "service_revolver" else mini(cap, maxi(definition.weapon.mag_size * 2, int(cap * 0.5)))
			inventory._seeded_ammo[definition.ammo_type] = true
			inventory.reserves[definition.ammo_type] = mini(cap, maxi(int(inventory.reserves.get(definition.ammo_type, 0)), starter))
		inventory.current = 0
		inventory._cancel_actions()
		inventory.send_state()
	else:
		inventory.accept_pickup(item)
		if item.id == "service_revolver":
			var cap: int = int(ItemCatalog.CAPS["revolver"])
			inventory._seeded_ammo["revolver"] = true
			inventory.reserves["revolver"] = cap
		if inventory.slots[fallback_slot] == item and inventory.current != fallback_slot:
			inventory.select_slot(fallback_slot)
		else:
			inventory.send_state()
	if peer == Net.local_id():
		_starter_accepted(run)
	else:
		_starter_accepted.rpc_id(peer, run)

@rpc("authority", "call_remote", "reliable")
func _starter_accepted(run: int) -> void:
	if run == run_id and not starter_chosen:
		starter_chosen = true
		Sound.play("pickup")

func _physics_process(delta: float) -> void:
	if not Net.is_host() or run_id == 0:
		return
	clock += delta
	if clock >= _scan_at:
		_scan_at = clock + 0.12
		_scan_pickups()
	if clock >= _sync_at and not projectiles.is_empty():
		_sync_at = clock + 0.1
		var flight: Array = []
		for id: int in projectiles:
			var effect: Node3D = projectiles[id]
			if not effect.deployed:
				flight.append([id, effect.global_position, effect.velocity])
		if not flight.is_empty():
			Net.rpc_to_run(_flight, [run_id, flight])

static func holder(player: Node) -> WeaponHolder:
	return player.get_node("Head/Camera3D/WeaponHolder") as WeaponHolder

func make_item(id: String, tier := 0) -> ItemInstance:
	var definition := ItemCatalog.definition(id)
	if definition == null:
		return null
	_next_instance += 1
	var count := definition.weapon.mag_size if definition.kind == ItemDefinition.Kind.GUN else definition.spawn_count
	return ItemInstance.new(_next_instance, id, 0 if definition.is_cursed() else tier, count)

func spawn_item(id: String, at: Vector3, tier := 0, claim_peer := 0) -> int:
	return spawn_pickup(make_item(id, tier), at, "", 0.0, claim_peer)

func spawn_pickup(item: ItemInstance, at: Vector3, flavor := "", expires := 0.0, claim_peer := 0) -> int:
	if not Net.is_host() or (item == null and flavor.is_empty()):
		return 0
	_next_id += 1
	var row := [at, item.encode() if item else [], flavor, claim_peer]
	_add_pickup(_next_id, row, item, clock + expires if expires > 0.0 else 0.0)
	Net.rpc_to_run(_spawn, [run_id, _next_id, row])
	return _next_id

func _add_pickup(id: int, row: Array, item: ItemInstance, expires := 0.0) -> void:
	var node := WorldPickup.new()
	node.registry = self
	node.pickup_id = id
	node.item = item
	node.flavor = row[2]
	node.claim_peer = row[3]
	node.position = to_local(row[0])
	add_child(node)
	pickups[id] = {"node": node, "expires": expires, "ready": clock + 0.3, "release": clock + 7.0}

@rpc("authority", "call_remote", "reliable")
func _spawn(run: int, id: int, row: Array) -> void:
	if run == run_id:
		_add_pickup(id, row, ItemInstance.decode(row[1]))

func remove_pickup(id: int, collector := 0) -> void:
	_remove(run_id, id, collector)
	Net.rpc_to_run(_remove, [run_id, id, collector])

@rpc("authority", "call_remote", "reliable")
func _remove(run: int, id: int, collector: int) -> void:
	if run != run_id or not pickups.has(id):
		return
	var node: WorldPickup = pickups[id].node
	pickups.erase(id)
	node.hide()
	node.queue_free()
	if collector != 0 and collector == Net.local_id():
		Sound.play("pickup", -10.0)

@rpc("authority", "call_remote", "reliable")
func _release(run: int, id: int) -> void:
	if run == run_id and pickups.has(id):
		pickups[id].node.claim_peer = 0

func clear_supplies() -> void:
	for id: int in pickups.keys():
		if pickups[id].node.flavor == "supply":
			remove_pickup(id)

func _scan_pickups() -> void:
	var players := GameManager.players()
	for id: int in pickups.keys():
		var record: Dictionary = pickups[id]
		var node: WorldPickup = record.node
		if record.expires > 0.0 and record.expires <= clock:
			remove_pickup(id)
			continue
		if node.claim_peer != 0 and (clock >= record.release or not Net.roster.has(node.claim_peer)):
			_release(run_id, id)
			Net.rpc_to_run(_release, [run_id, id])
		if node.item or clock < record.ready:
			continue
		for player: Node3D in players:
			if _reachable(node, player, GameManager.pickup_reach()) and _collect_supply(node.flavor, player):
				remove_pickup(id, player.get_multiplayer_authority())
				break

const SCRAP_VALUES := {"scrap": 5, "scrap_large": 15}

func _collect_supply(flavor: String, player: Node) -> bool:
	if SCRAP_VALUES.has(flavor):
		# Infected salvage: always collectible, shows "+X SCRAP" via earn_scrap.
		holder(player).earn_scrap(roundi(SCRAP_VALUES[flavor] * GameManager.scrap_pickup_scale()))
		return true
	var collected := false
	if flavor in ["ammo", "supply", "ammo_box"]:
		collected = holder(player).collect_ammo(flavor == "ammo_box")
	if flavor in ["health", "supply"] and player.health < player.max_health:
		player.heal(20.0)
		collected = true
	if flavor in ["suit", "supply"] and player.suit_integrity < 100.0:
		player.suit_integrity = minf(100.0, player.suit_integrity + 25.0)
		collected = true
	if flavor == "tarp" and not player.has_tarp:
		player.grant("tarp")
		collected = true
	if flavor == "decon" and GameManager.decon_charges < GameManager.decon_max:
		GameManager.add_decon_charge()
		collected = true
	return collected

func request_claim(id: int, expected: int, slot: int, player: Node) -> void:
	if Net.is_host():
		claim(run_id, id, expected, slot, player)
	else:
		_claim.rpc_id(1, run_id, id, expected, slot)

@rpc("any_peer", "call_remote", "reliable")
func _claim(run: int, id: int, expected: int, slot: int) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if Net.is_host() and Net.run_peers.has(sender):
		claim(run, id, expected, slot, GameManager.player_for_peer(sender))

func claim(run: int, id: int, expected: int, slot: int, player: Node3D) -> bool:
	if not Net.is_host() or run != run_id or run_id == 0 or not pickups.has(id) or player == null:
		return false
	var node: WorldPickup = pickups[id].node
	if not node.can_interact(player) or not _reachable(node, player, node.radius):
		return false
	var inventory := holder(player)
	# A selection queued behind the owner's last snapshot can be stale.
	if not inventory.can_act() or inventory.current != slot or inventory.selected_serial() != expected:
		return false
	var item := node.item
	if ItemCatalog.is_pouch(item.id):
		return _claim_pouch(id, node, inventory, player)
	var replaced := inventory.accept_pickup(item)
	if replaced == item:
		return false
	var at := node.global_position
	remove_pickup(id, player.get_multiplayer_authority())
	if replaced:
		spawn_pickup(replaced, at)
	if ItemCatalog.definition(item.id).is_cursed():
		GameManager.record_cursed(player, ItemCatalog.definition(item.id).display_name)
	inventory.send_state()
	return true

## Frags and domes fill the belt pouch. A full pouch leaves the pickup where it
## is; a partial fit takes what it can and leaves the rest on the same spot.
func _claim_pouch(id: int, node: WorldPickup, inventory: WeaponHolder, player: Node3D) -> bool:
	var item := node.item
	if inventory.pouch_full(item.id):
		inventory.notify_pouch_full(item.id)
		return false
	var left := inventory.add_pouch(item.id, item.count)
	var at := node.global_position
	remove_pickup(id, player.get_multiplayer_authority())
	if left > 0:
		spawn_pickup(ItemInstance.new(item.serial, item.id, item.tier, left), at)
	inventory.send_state(false)
	return true

func _reachable(node: WorldPickup, player: Node3D, reach: float) -> bool:
	if player.state != "ok" or player.global_position.distance_to(node.global_position) > reach:
		return false
	var eye: Vector3 = holder(player).camera.global_position
	var query := PhysicsRayQueryParameters3D.create(eye, node.interact_point(), 1)
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()

func ground_at(player: Node3D, offset: Vector3) -> Vector3:
	var p := player.global_position
	var eye := p + Vector3.UP * 0.7
	var start := eye + offset
	var space := get_world_3d().direct_space_state
	if not space.intersect_ray(PhysicsRayQueryParameters3D.create(eye, start, 1)).is_empty():
		return Vector3.INF
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(start, start - Vector3.UP * 8.0, 1))
	if hit.is_empty() or (hit.normal as Vector3).y < 0.55:
		return Vector3.INF
	return (hit.position as Vector3) + Vector3.UP * 0.04

func milestone(id: String) -> void:
	if id in discoveries:
		return
	discoveries.append(id)
	Net.rpc_to_run(_discover, [run_id, id])
	if not Net.dedicated:
		_discover(run_id, id)

@rpc("authority", "call_remote", "reliable")
func _discover(run: int, id: String) -> void:
	if run != run_id:
		return
	var definition := ItemCatalog.definition(id)
	if definition.weapon.resource_path not in Settings.unlocked_guns:
		Settings.unlock_gun(definition.weapon.resource_path)
		GameManager.weapon_unlocked.emit(definition.display_name.to_upper())

func sync_to_peer(peer: int) -> void:
	if run_id == 0:
		return
	var rows: Array = []
	for id: int in pickups:
		var node: WorldPickup = pickups[id].node
		rows.append([id, [node.global_position, node.item.encode() if node.item else [], node.flavor, node.claim_peer]])
	var effects: Array = []
	for id: int in projectiles:
		effects.append([id, projectiles[id].snapshot()])
	_snapshot.rpc_id(peer, run_id, rows, effects, discoveries, _starter_claims.has(peer))
	for player: Node in GameManager.players():
		var inventory := holder(player)
		inventory.sync_equip_to(peer)
		if player.get_multiplayer_authority() == peer:
			inventory.sync_private_to(peer)

@rpc("authority", "call_remote", "reliable")
func _snapshot(run: int, rows: Array, effects: Array, found: Array, chosen: bool) -> void:
	if run < run_id:
		return
	for record: Dictionary in pickups.values():
		record.node.queue_free()
	for effect: Node in projectiles.values():
		effect.queue_free()
	pickups.clear()
	projectiles.clear()
	run_id = run
	starter_chosen = chosen
	for row: Array in rows:
		_spawn(run, row[0], row[1])
	for row: Array in effects:
		_effect_spawn(run, row[0], row[1])
	for id: String in found:
		_discover(run, id)

func launch(id: String, from: Vector3, dir: Vector3, tier: int, shooter: Node3D) -> void:
	_next_id += 1
	var effect := _new_effect(_next_id, id, from, WeaponProjectile.launch_velocity(ItemCatalog.definition(id).weapon, dir), tier, shooter)
	Net.rpc_to_run(_effect_spawn, [run_id, _next_id, effect.snapshot()])

func _new_effect(seq: int, id: String, at: Vector3, velocity: Vector3, tier: int, shooter: Node3D) -> WeaponProjectile:
	var effect := WeaponProjectile.new()
	effect.configure(self, seq, id, at, velocity, tier, shooter)
	add_child(effect)
	projectiles[seq] = effect
	return effect

@rpc("authority", "call_remote", "reliable")
func _effect_spawn(run: int, seq: int, row: Array) -> void:
	if run != run_id:
		return
	var effect := _new_effect(seq, row[0], row[1], row[2], row[3], null)
	if row[4]:
		effect.deploy(row[1], row[5], row[6], false)

@rpc("authority", "call_remote", "unreliable_ordered")
func _flight(run: int, rows: Array) -> void:
	if run != run_id:
		return
	for row: Array in rows:
		var effect: WeaponProjectile = projectiles.get(row[0])
		if effect and not effect.deployed:
			effect.sync_flight(row[1], row[2])

func effect_deployed(seq: int, at: Vector3, life: float, yaw: float) -> void:
	Net.rpc_to_run(_effect_deploy, [run_id, seq, at, life, yaw])

@rpc("authority", "call_remote", "reliable")
func _effect_deploy(run: int, seq: int, at: Vector3, life: float, yaw: float) -> void:
	if run == run_id and projectiles.has(seq):
		projectiles[seq].deploy(at, life, yaw)

func effect_finished(seq: int, at: Vector3, blast: bool) -> void:
	_effect_end(run_id, seq, at, blast)
	Net.rpc_to_run(_effect_end, [run_id, seq, at, blast])

@rpc("authority", "call_remote", "reliable")
func _effect_end(run: int, seq: int, at: Vector3, blast: bool) -> void:
	if run == run_id and projectiles.has(seq):
		var effect: WeaponProjectile = projectiles[seq]
		projectiles.erase(seq)
		effect.finish(at, blast)

func place(id: String, at: Vector3, direction: Vector3, tier: int, shooter: Node3D) -> void:
	_next_id += 1
	var effect := _new_effect(_next_id, id, at, Vector3.ZERO, tier, shooter)
	effect.deploy(at, effect.data.effect_time, atan2(-direction.x, -direction.z))
	Net.rpc_to_run(_effect_spawn, [run_id, _next_id, effect.snapshot()])
