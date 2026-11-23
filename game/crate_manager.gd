extends Node
## Weather Service vending, double-or-nothing and airdrop inventory.

const BASE_PRICE := 20
const PRICE_STEP := 5
const DOUBLE_WINDOW := 2.0
const STATION_TABLE := preload("res://crates/loot_table.tres")
const VENDING_POOLS := [
	["med_tin", "suit_patch", "frag", "shield_dome", "umbrella", "bleach_bomb", "bait_radio"],
	["pump_shotgun", "spray_rifle", "nail_driver", "rock_salt", "hunting_rifle", "pressure_washer",
		"battery_zapper", "flare_launcher"],
	["lightning_rod", "harpoon", "leaf_blower", "flare_launcher", "battery_zapper",
		"boombox_launcher", "leaky_nailgun", "lucky_penny_revolver"],
]
const VENDING_PRICES := [6, 11, 18]
const VENDING_LEGENDARY_CHANCE := 0.05
const EARLY_VENDING_POOLS := [
	["med_tin", "suit_patch", "frag", "shield_dome", "umbrella"],
	["pump_shotgun", "spray_rifle", "nail_driver", "rock_salt", "hunting_rifle", "pressure_washer"],
	["lightning_rod", "harpoon", "leaf_blower", "flare_launcher", "battery_zapper"],
]

var loot: LootTable = STATION_TABLE
var stations: Dictionary = {}
var airdrop: SupplyStation
var last_drop_position := Vector3.INF
var _pending: Array[Dictionary] = []
var _holds: Dictionary = {}
var _waiting: Dictionary = {}
var _offer_serial := 0
var _vending_rng := RandomNumberGenerator.new()
var _run := 0
var _drop_wave := 0
var _launched_wave := 0
var _pending_drop := false
var _retry_drop_at := 0.0
var _clock := 0.0

func begin_run() -> void:
	var registry := RunLoot.find(get_tree())
	_run = registry.run_id
	_stations_from_markers(registry)
	_pending.clear()
	_holds.clear()
	_waiting.clear()
	_offer_serial = 0
	_drop_wave = 0
	_launched_wave = 0
	last_drop_position = Vector3.INF
	_pending_drop = false
	_retry_drop_at = 0.0
	_clock = 0.0
	if is_instance_valid(airdrop):
		airdrop.queue_free()
	airdrop = null

func _stations_from_markers(registry: RunLoot) -> void:
	for key: String in stations.keys():
		var old: Variant = stations[key]
		if is_instance_valid(old):
			(old as Node).queue_free()
	stations.clear()
	var markers := get_tree().get_nodes_in_group("crate_station")
	for i in markers.size():
		var marker := markers[i] as Marker3D
		var station := SupplyStation.new()
		station.key = str(marker.name)
		station.name = marker.name
		station.has_double = i == 0
		registry.add_child(station)
		station.global_transform = marker.global_transform
		stations[station.key] = station

func _physics_process(delta: float) -> void:
	if not Net.is_host() or not GameManager.run_active or GameManager.finished:
		return
	_clock += delta
	if _pending_drop and WeatherManager.phase == WeatherManager.Phase.DRIZZLE and _clock >= _retry_drop_at:
		_try_spawn_airdrop()
	for key: int in _holds.keys():
		var hold: Dictionary = _holds[key]
		if _clock - hold.start > 2.5 or not _valid(GameManager.player_for_peer(key), hold.station, hold.mode):
			_holds.erase(key)
	for i in range(_pending.size() - 1, -1, -1):
		var roll := _pending[i]
		if roll.due <= _clock:
			_drop_reward(roll)
			_pending.remove_at(i)

func start_calm() -> void:
	if not Net.is_host() or _drop_wave == WeatherManager.wave:
		return
	_drop_wave = WeatherManager.wave
	last_drop_position = Vector3.INF
	_waiting.clear()
	for key: String in stations.keys():
		var station: Variant = stations[key]
		if is_instance_valid(station):
			var cabinet := station as SupplyStation
			_set_price(cabinet, BASE_PRICE)
			_restock(cabinet)
	GameManager.show_banner("OVERCLOCKED SUPPLY DROP IN DRIZZLE", Color("#ffc365"), 3.2)
	_airdrop_cue()
	Net.rpc_to_run(_announce_drop, [_run])

func start_drizzle() -> void:
	if not Net.is_host() or _launched_wave == WeatherManager.wave or is_instance_valid(airdrop):
		return
	_pending_drop = true
	_try_spawn_airdrop()

func _try_spawn_airdrop() -> void:
	_retry_drop_at = _clock + 0.5
	var at := _drop_point()
	if at == Vector3.INF:
		return
	_pending_drop = false
	_launched_wave = WeatherManager.wave
	last_drop_position = at
	Perf.mark("crates spawn wave %d" % WeatherManager.wave)
	_make_airdrop(at, SupplyStation.DESCENT)
	Net.rpc_to_run(_airdrop_spawn, [_run, at, SupplyStation.DESCENT])

func end_wave() -> void:
	_pending_drop = false
	if is_instance_valid(airdrop) and not airdrop.opened:
		_remove_drop(_run)
		Net.rpc_to_run(_remove_drop, [_run])

func _drop_point() -> Vector3:
	var registry := RunLoot.find(get_tree())
	var map := registry.get_world_3d().navigation_map
	if NavigationServer3D.map_get_iteration_id(map) == 0:
		return Vector3.INF
	var fallback := Vector3.INF
	var best_score := INF
	var all_players := GameManager.players().filter(func(p): return p.state == "ok")
	if all_players.is_empty():
		return Vector3.INF
	var space := registry.get_world_3d().direct_space_state
	var shelter := PhysicsPointQueryParameters3D.new()
	shelter.collision_mask = 1 << 3
	shelter.collide_with_bodies = false
	shelter.collide_with_areas = true
	for marker: Node3D in get_tree().get_nodes_in_group("crate_spawn"):
		var at := NavigationServer3D.map_get_closest_point(map, marker.global_position)
		if at.distance_to(marker.global_position) > 2.5:
			continue
		var sky := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 0.4, at + Vector3.UP * 45.0, 1)
		if not space.intersect_ray(sky).is_empty():
			continue
		shelter.position = at + Vector3.UP * 1.5
		if not space.intersect_point(shelter, 1).is_empty():
			continue
		var nearest_route := INF
		for player: Node3D in all_players:
			var player_nav := NavigationServer3D.map_get_closest_point(map, player.global_position)
			var route := NavigationServer3D.map_get_path(map, player_nav, at, true)
			if route.is_empty() or route[-1].distance_to(at) > 0.9:
				continue
			var length := player.global_position.distance_to(route[0])
			for i in range(1, route.size()):
				length += route[i - 1].distance_to(route[i])
			nearest_route = minf(nearest_route, length)
		var score := absf(nearest_route - 22.0)
		if score < best_score:
			var floor_hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(at + Vector3.UP * 0.3, at - Vector3.UP * 2.0, 1))
			if floor_hit.is_empty():
				continue
			best_score = score
			fallback = floor_hit.position
	return fallback

func _make_airdrop(at: Vector3, descent: float) -> void:
	if is_instance_valid(airdrop):
		airdrop.queue_free()
		airdrop = null
	var registry := RunLoot.find(get_tree())
	var drop := SupplyStation.new()
	drop.name = "Airdrop"
	drop.key = "Airdrop"
	drop.is_drop = true
	drop.descent_left = descent
	drop.position = registry.to_local(at)
	registry.add_child(drop)
	airdrop = drop

@rpc("authority", "call_remote", "reliable")
func _airdrop_spawn(run: int, at: Vector3, descent: float) -> void:
	if run == _run:
		_make_airdrop(at, descent)

func _airdrop_cue() -> void:
	if not Net.dedicated:
		Sound.play("gun_supply_drop", -8.0)

@rpc("authority", "call_remote", "reliable")
func _announce_drop(run: int) -> void:
	if run == _run:
		_airdrop_cue()

@rpc("authority", "call_remote", "reliable")
func _remove_drop(run: int) -> void:
	if run == _run and is_instance_valid(airdrop):
		airdrop.hide()
		airdrop.queue_free()
		airdrop = null

func request_hold(key: String, mode: String, step: String, player: Node, offer_serial := 0) -> void:
	if Net.is_host():
		_handle_hold(_run, key, mode, step, player, offer_serial)
	else:
		_hold_request.rpc_id(1, _run, key, mode, step, offer_serial)

@rpc("any_peer", "call_remote", "reliable")
func _hold_request(run: int, key: String, mode: String, step: String, offer_serial: int) -> void:
	var peer := multiplayer.get_remote_sender_id()
	if Net.is_host() and Net.run_peers.has(peer):
		_handle_hold(run, key, mode, step, GameManager.player_for_peer(peer), offer_serial)

func _handle_hold(run: int, key: String, mode: String, step: String, player: Node, offer_serial := 0) -> bool:
	if not Net.is_host() or run != _run or not is_instance_valid(player):
		return false
	var peer := player.get_multiplayer_authority()
	if step == "cancel":
		_holds.erase(peer)
		return false
	var station := airdrop if key == "Airdrop" else stations.get(key) as SupplyStation
	if not _valid(player, station, mode):
		_holds.erase(peer)
		return false
	var offer := station.offer_for(mode)
	if not offer.is_empty() and offer[3] != offer_serial:
		_holds.erase(peer)
		return false
	if step == "begin":
		_holds[peer] = {"station": station, "mode": mode, "start": _clock, "offer_serial": offer_serial}
		return false
	if step != "finish":
		return false
	var hold: Dictionary = _holds.get(peer, {})
	_holds.erase(peer)
	if hold.is_empty() or hold.station != station or hold.mode != mode or hold.offer_serial != offer_serial or _clock - hold.start < 0.48:
		return false
	match mode:
		"airdrop":
			_open_airdrop()
			return true
		"double":
			return _open_double(station, player)
		_:
			return _purchase(station, mode, offer, player)

func _valid(player: Node, target: SupplyStation, mode: String) -> bool:
	if not is_instance_valid(player) or not is_instance_valid(target) or player.state != "ok" or not target.available(mode) \
			or not GameManager.run_active or GameManager.is_voting() or GameManager.awaiting_tape_choice:
		return false
	var pad := target.get_node_or_null(mode) as SupplyInteract
	if pad == null or pad.global_position.distance_to(player.global_position) > pad.radius:
		return false
	var eye := RunLoot.holder(player).camera.global_position
	return WeaponCombat.clear_path(target.get_world_3d(), eye, pad.global_position)

func _set_price(station: SupplyStation, cost: int) -> void:
	station.price = cost
	Net.rpc_to_run(_price, [_run, station.key, cost])

@rpc("authority", "call_remote", "reliable")
func _price(run: int, key: String, cost: int) -> void:
	if run == _run and stations.has(key):
		stations[key].price = cost

func _restock(station: SupplyStation, sold := -1) -> void:
	var offers := station.offers.duplicate()
	var wave := WeatherManager.wave
	var stock := EARLY_VENDING_POOLS if wave <= 2 else VENDING_POOLS
	if sold < 0:
		offers.resize(stock.size())
	for i in stock.size():
		if sold >= 0 and i != sold:
			continue
		var previous: String = station.offers[i][0] if i < station.offers.size() else ""
		var pool: Array = stock[i].filter(func(id: String): return id != previous)
		var id: String = pool[_vending_rng.randi_range(0, pool.size() - 1)]
		if i == 2 and wave >= 4 and previous != "disruptor" and _vending_rng.randf() < VENDING_LEGENDARY_CHANCE:
			id = "disruptor"
		_offer_serial += 1
		offers[i] = [id, _vending_tier(i, wave), VENDING_PRICES[i], _offer_serial]
	station.set_offers(offers)
	Net.rpc_to_run(_stock, [_run, station.key, offers])

func _vending_tier(bay: int, wave: int) -> int:
	if (bay == 2 and wave >= 2) or (bay == 1 and wave >= 4):
		return ItemCatalog.OVERCLOCKED
	if bay == 2 or (bay == 1 and wave >= 2):
		return ItemCatalog.TUNED
	return ItemCatalog.STANDARD

@rpc("authority", "call_remote", "reliable")
func _stock(run: int, key: String, offers: Array) -> void:
	if run == _run and stations.has(key):
		stations[key].set_offers(offers)

func _make_graded_item(registry: RunLoot, id: String, tier: int) -> ItemInstance:
	var item := registry.make_item(id, tier)
	if item:
		# Vending and airdrop upgrades apply even when the weapon is cursed.
		item.tier = tier
	return item

func _purchase(station: SupplyStation, mode: String, offer: Array, player: Node3D) -> bool:
	var registry := RunLoot.find(get_tree())
	var inventory := RunLoot.holder(player)
	if offer.is_empty() or not inventory.can_act() or inventory.scrap < int(offer[2]):
		return false
	var item := _make_graded_item(registry, offer[0], offer[1])
	if item == null:
		return false
	var drop_at := Vector3.INF
	if inventory.needs_swap(item):
		# Use the aim pad's dry approach side, allowing a full inventory to
		# buy without putting the displaced item behind the cabinet.
		var offset := -station.global_basis.z * 0.85
		drop_at = registry.ground_at(player, offset)
		if not drop_at.is_finite():
			drop_at = registry.ground_at(player, Vector3.ZERO)
		if not drop_at.is_finite():
			return false
	var bundle_count := item.count
	var displaced := inventory.accept_pickup(item)
	if displaced == item and item.count == bundle_count:
		return false
	if displaced:
		# A pouch can accept part of a bundle without swapping a hotbar item.
		if not drop_at.is_finite():
			drop_at = registry.ground_at(player, Vector3.ZERO)
		registry.spawn_pickup(displaced, drop_at if drop_at.is_finite() else player.global_position)
	inventory.scrap -= int(offer[2])
	var definition := ItemCatalog.definition(item.id)
	if definition.is_cursed():
		GameManager.record_cursed(player, definition.display_name)
	inventory.send_state()
	_display_roll(station, item.id, item.tier, "DISPENSED")
	_restock(station, SupplyStation.OFFER_PADS.find(mode))
	return true

func _open_double(station: SupplyStation, player: Node) -> bool:
	var peer := player.get_multiplayer_authority()
	var waiting: Array = _waiting.get(station.key, [])
	var partner: Node
	if not waiting.is_empty() and _clock - float(waiting[1]) <= DOUBLE_WINDOW:
		partner = GameManager.player_for_peer(waiting[0])
	if partner == player:
		return false
	if not _valid(partner, station, "double") or RunLoot.holder(partner).scrap < station.price:
		if RunLoot.holder(player).scrap >= station.price:
			_waiting[station.key] = [peer, _clock]
			_display_roll(station, "ammo_box", 0, "WAITING FOR PARTNER")
		return false
	if not RunLoot.holder(player).spend_scrap(station.price):
		return false
	RunLoot.holder(partner).spend_scrap(station.price)
	_waiting.erase(station.key)
	_set_price(station, station.price + PRICE_STEP)
	if RNG.chance(0.5):
		_queue_reward(station, _pick(loot.pool(1, WeatherManager.wave)), ItemCatalog.TUNED)
		_queue_reward(station, _pick(loot.pool(1, WeatherManager.wave)), ItemCatalog.TUNED)
	else:
		var players := GameManager.players()
		var victim: Node = players[RNG.rng.randi_range(0, players.size() - 1)]
		_queue_reward(station, _pick(loot.cursed_items), 0, victim.get_multiplayer_authority(), "CURSED · %s" % victim.display_name)
	return true

func _pick(pool: Array) -> String:
	return pool[RNG.rng.randi_range(0, pool.size() - 1)]

func _queue_reward(station: SupplyStation, id: String, tier: int, peer := 0, title := "") -> void:
	var due := _clock + 1.35
	for roll: Dictionary in _pending:
		if roll.key == station.key:
			due = maxf(due, roll.due + 1.45)
	var at := station.global_position - station.global_basis.z * 1.16
	_pending.append({"key": station.key, "at": at, "id": id, "tier": tier, "peer": peer, "due": due})
	_display_roll(station, id, tier, loot.display_name(id) if title.is_empty() else title)

func _drop_reward(roll: Dictionary) -> void:
	var registry := RunLoot.find(get_tree())
	if ItemCatalog.definition(roll.id):
		registry.spawn_item(roll.id, roll.at, roll.tier, roll.peer)
	else:
		registry.spawn_pickup(null, roll.at, roll.id)

func _display_roll(station: SupplyStation, id: String, tier: int, title: String) -> void:
	station.reveal(id, tier, title)
	Net.rpc_to_run(_reveal, [_run, station.key, id, tier, title])

@rpc("authority", "call_remote", "reliable")
func _reveal(run: int, key: String, id: String, tier: int, title: String) -> void:
	if run != _run:
		return
	var station := airdrop if key == "Airdrop" else stations.get(key) as SupplyStation
	if is_instance_valid(station):
		station.reveal(id, tier, title)

func _open_airdrop() -> void:
	var registry := RunLoot.find(get_tree())
	var point := airdrop.global_position
	var players := GameManager.player_count()
	var reward_count := players + loot.airdrop_supplies.size()
	var space := registry.get_world_3d().direct_space_state
	for i in reward_count:
		var angle := i * TAU / reward_count
		var offset := Vector3(2.25, 0.0, 0.0).rotated(Vector3.UP, angle)
		var at := _safe_drop_spot(space, point, offset)
		if i < players:
			var weapon := _make_graded_item(registry, loot.roll_airdrop_weapon(), ItemCatalog.OVERCLOCKED)
			registry.spawn_pickup(weapon, at)
		else:
			var id := loot.airdrop_supplies[i - players]
			if id == "ammo_box":
				registry.spawn_pickup(null, at, id)
			else:
				registry.spawn_item(id, at)
	_remove_drop(_run)
	Net.rpc_to_run(_remove_drop, [_run])

func _safe_drop_spot(space: PhysicsDirectSpaceState3D, center: Vector3, offset: Vector3) -> Vector3:
	var eye := center + Vector3.UP * 0.7
	for distance: float in [1.0, 0.65]:
		var start := eye + offset * distance
		if not space.intersect_ray(PhysicsRayQueryParameters3D.create(eye, start, 1)).is_empty():
			continue
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(start, start - Vector3.UP * 5.0, 1))
		if not hit.is_empty():
			return (hit.position as Vector3) + Vector3.UP * 0.06
	return center + Vector3.UP * 0.06

func sync_to_peer(peer: int) -> void:
	var cabinets: Dictionary = {}
	for key: String in stations.keys():
		var station: Variant = stations[key]
		if is_instance_valid(station):
			var s := station as SupplyStation
			cabinets[s.key] = [s.price, s.offers]
	var drop: Array = [airdrop.global_position, airdrop.descent_left] if is_instance_valid(airdrop) else []
	_snapshot.rpc_id(peer, _run, cabinets, drop)

@rpc("authority", "call_remote", "reliable")
func _snapshot(run: int, cabinets: Dictionary, drop: Array) -> void:
	if run < _run:
		return
	_run = run
	var registry := RunLoot.find(get_tree())
	if not registry:
		return
	_stations_from_markers(registry)
	for key: String in cabinets:
		_price(run, key, cabinets[key][0])
		_stock(run, key, cabinets[key][1])
	if not drop.is_empty():
		_make_airdrop(drop[0], drop[1])
