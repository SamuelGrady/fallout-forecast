extends Node
## Weather Service vending and airdrop inventory.

const STATION_TABLE := preload("res://crates/loot_table.tres")
const VENDING_POOLS := [
	["med_tin", "suit_patch", "frag", "shield_dome", "umbrella", "bleach_bomb", "bait_radio"],
	["pump_shotgun", "spray_rifle", "nail_driver", "rock_salt", "hunting_rifle", "pressure_washer",
		"battery_zapper", "flare_launcher"],
	["lightning_rod", "harpoon", "leaf_blower", "flare_launcher", "battery_zapper",
		"boombox_launcher", "leaky_nailgun", "lucky_penny_revolver"],
]
const VENDING_PRICES := [6, 11, 18]
## Two regular scrap pickups buy a Tuned primary during the first intermission.
const WAVE_TWO_PRIMARY_PRICE := 10
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
var _holds: Dictionary = {}
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
	_holds.clear()
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
	for marker: Marker3D in get_tree().get_nodes_in_group("crate_station"):
		var station := SupplyStation.new()
		station.key = str(marker.name)
		station.name = marker.name
		registry.add_child(station)
		station.global_transform = marker.global_transform
		stations[station.key] = station

func _physics_process(delta: float) -> void:
	if not Net.is_host() or not GameManager.run_active or GameManager.finished:
		return
	_clock += delta
	# Drops land during Calm; Drizzle is a fallback if the navmesh wasn't ready.
	if _pending_drop and _clock >= _retry_drop_at and WeatherManager.phase in [WeatherManager.Phase.CALM,
			WeatherManager.Phase.MUTATION_ROLL, WeatherManager.Phase.DRIZZLE]:
		_try_spawn_airdrop()
	for key: int in _holds.keys():
		var hold: Dictionary = _holds[key]
		if _clock - hold.start > 2.5 or not _valid(GameManager.player_for_peer(key), hold.station, hold.mode):
			_holds.erase(key)

func start_calm() -> void:
	if not Net.is_host() or _drop_wave == WeatherManager.wave:
		return
	_drop_wave = WeatherManager.wave
	last_drop_position = Vector3.INF
	for key: String in stations.keys():
		var station: Variant = stations[key]
		if is_instance_valid(station):
			_restock(station as SupplyStation)
	# Wave 1 Calm is starter-pick time; every later Calm gets a between-wave drop.
	if WeatherManager.wave < 2 or _launched_wave == WeatherManager.wave:
		return
	if is_instance_valid(airdrop) and not airdrop.opened:
		_remove_drop(_run)
		Net.rpc_to_run(_remove_drop, [_run])
	var banner: Array = _drop_banner(WeatherManager.wave)
	GameManager.show_banner(banner[0], banner[1], 3.2)
	_airdrop_cue()
	Net.rpc_to_run(_announce_drop, [_run])
	_pending_drop = true
	_try_spawn_airdrop()

func _drop_banner(wave: int) -> Array:
	match LootTable.airdrop_grade(wave):
		0:
			return ["SURPLUS SUPPLY DROP INBOUND", BroadcastUI.PAPER.lerp(Color("#ffc365"), 0.35)]
		1:
			return ["TUNED SUPPLY DROP INBOUND", BroadcastUI.CYAN]
		2:
			return ["OVERCLOCKED SUPPLY DROP INBOUND", Color("#ffc365")]
		_:
			return ["APEX SUPPLY DROP INBOUND", Color("#ff884d")]

## The between-wave drop stays through the wave if unopened; this only
## retries a Calm launch that couldn't find a landing spot yet.
func start_drizzle() -> void:
	if Net.is_host() and _pending_drop and _launched_wave != WeatherManager.wave:
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
	var all_players := GameManager.players().filter(func(p): return p.state == "ok")
	if all_players.is_empty():
		return Vector3.INF
	var centroid := Vector3.ZERO
	var origins := PackedVector3Array()
	var nav_origins := PackedVector3Array()
	for player: Node3D in all_players:
		var at := player.global_position
		centroid += at
		origins.append(at)
		nav_origins.append(NavigationServer3D.map_get_closest_point(map, at))
	centroid /= float(all_players.size())
	var space := registry.get_world_3d().direct_space_state
	var shelter := PhysicsPointQueryParameters3D.new()
	shelter.collision_mask = 1 << 3
	shelter.collide_with_bodies = false
	shelter.collide_with_areas = true

	var best := Vector3.INF
	var best_score := INF

	# Build candidates: curated crate_spawn markers plus open-sky rings right near active players.
	var candidates := PackedVector3Array()
	for marker: Node3D in get_tree().get_nodes_in_group("crate_spawn"):
		candidates.append(marker.global_position)
	var curated_count := candidates.size()
	var anchors: Array[Vector3] = [centroid]
	for at: Vector3 in origins:
		if at.distance_to(centroid) > 6.0:
			anchors.append(at)
	for anchor: Vector3 in anchors:
		for radius: float in [9.0, 11.0, 16.0, 20.0]:
			for step in 12:
				var angle := float(step) * TAU / 12.0 + 0.25 * radius
				var probe := anchor + Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
				candidates.append(probe)

	for index in candidates.size():
		var raw := candidates[index]
		var curated := index < curated_count
		var at := NavigationServer3D.map_get_closest_point(map, raw)
		if at.distance_to(raw) > (2.5 if curated else 3.5):
			continue
		var too_close := false
		for origin: Vector3 in origins:
			if Vector2(at.x - origin.x, at.z - origin.z).length_squared() < 5.5 * 5.5:
				too_close = true
				break
		if too_close:
			continue
		var blocked_station := false
		for station: SupplyStation in stations.values():
			if is_instance_valid(station) and at.distance_to(station.global_position) < 3.5:
				blocked_station = true
				break
		if blocked_station:
			continue
		var sky := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 0.4, at + Vector3.UP * 45.0, 1)
		if not space.intersect_ray(sky).is_empty():
			continue
		shelter.position = at + Vector3.UP * 1.5
		if not space.intersect_point(shelter, 1).is_empty():
			continue
		var floor_hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(at + Vector3.UP * 0.5, at - Vector3.UP * 2.0, 1))
		if floor_hit.is_empty() or (floor_hit.normal as Vector3).y < 0.85:
			continue
		var nearest_route := INF
		for player_index in origins.size():
			var route := NavigationServer3D.map_get_path(map, nav_origins[player_index], at, true)
			if route.is_empty() or route[-1].distance_to(at) > 0.9:
				continue
			var length := origins[player_index].distance_to(route[0])
			for i in range(1, route.size()):
				length += route[i - 1].distance_to(route[i])
			nearest_route = minf(nearest_route, length)
		if not is_finite(nearest_route):
			continue
		# Prefer landing ~11m from the nearest player and close to the squad centroid.
		var score := absf(nearest_route - 11.0) + maxf(0.0, at.distance_to(centroid) - 16.0) * 0.35
		if curated and nearest_route <= 20.0:
			score -= 2.0
		if score < best_score:
			best_score = score
			best = floor_hit.position
	return best

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
		"ammo":
			return _buy_ammo(station, player)
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
		var price := WAVE_TWO_PRIMARY_PRICE if wave == 2 and i == 1 else int(VENDING_PRICES[i])
		offers[i] = [id, _vending_tier(i, wave), price, _offer_serial]
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
	if ItemCatalog.is_pouch(offer[0]) and inventory.pouch_full(offer[0]):
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
	var displaced := inventory.accept_pickup(item, true)
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

## Ammo is always in stock: no bay is consumed or restocked.
func _buy_ammo(station: SupplyStation, player: Node) -> bool:
	var inventory := RunLoot.holder(player)
	if not inventory.can_act() or not inventory.can_collect_ammo() or inventory.scrap < SupplyStation.AMMO_PRICE:
		return false
	if not inventory.collect_ammo(true):
		return false
	inventory.spend_scrap(SupplyStation.AMMO_PRICE)
	_display_roll(station, "ammo_box", 0, "AMMO REFILLED")
	return true

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
	var wave := WeatherManager.wave
	var weapons := GameManager.player_count() + loot.airdrop_bonus_weapons(wave)
	var supplies := loot.airdrop_supplies(wave)
	var tier := loot.airdrop_tier(wave)
	var reward_count := weapons + supplies.size()
	var space := registry.get_world_3d().direct_space_state
	for i in reward_count:
		var angle := i * TAU / reward_count
		var offset := Vector3(2.25, 0.0, 0.0).rotated(Vector3.UP, angle)
		var at := _safe_drop_spot(space, point, offset)
		if i < weapons:
			var weapon := _make_graded_item(registry, loot.roll_airdrop_weapon(wave), tier)
			registry.spawn_pickup(weapon, at)
		else:
			var id := supplies[i - weapons]
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
			cabinets[s.key] = s.offers
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
		_stock(run, key, cabinets[key])
	if not drop.is_empty():
		_make_airdrop(drop[0], drop[1])
