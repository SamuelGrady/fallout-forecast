extends Node
## Fixed Weather Service stations and one airdrop per Calm. Paid rolls enqueue
## location-bound rewards; the opening player's node can leave during a spin.

const BASE_PRICE := 20
const PRICE_STEP := 5
const DOUBLE_WINDOW := 2.0
const CURSED_DROUGHT := 8
const STATION_TABLE := preload("res://crates/loot_table.tres")

var loot: LootTable = STATION_TABLE
var stations: Dictionary = {}
var airdrop: SupplyStation
var _pending: Array[Dictionary] = []
var _holds: Dictionary = {}
var _waiting: Dictionary = {}
var _cursed_last: Dictionary = {}
var _since_cursed := 0
var _run := 0
var _drop_wave := 0
var _pending_drop := false
var _clock := 0.0

func begin_run() -> void:
	var registry := RunLoot.find(get_tree())
	_run = registry.run_id
	_stations_from_markers(registry)
	_pending.clear()
	_holds.clear()
	_waiting.clear()
	_cursed_last.clear()
	_since_cursed = 0
	_drop_wave = 0
	_pending_drop = false
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
	if _pending_drop and WeatherManager.phase == WeatherManager.Phase.CALM and not is_instance_valid(airdrop):
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
	_waiting.clear()
	for key: String in stations.keys():
		var station: Variant = stations[key]
		if is_instance_valid(station):
			_set_price(station as SupplyStation, BASE_PRICE)
	_pending_drop = true
	_try_spawn_airdrop()

func _try_spawn_airdrop() -> void:
	var at := _drop_point()
	if at == Vector3.INF:
		return
	_pending_drop = false
	Perf.mark("crates spawn wave %d" % WeatherManager.wave)
	_make_airdrop(at, SupplyStation.DESCENT)
	Net.rpc_to_run(_airdrop_spawn, [_run, at, SupplyStation.DESCENT])
	GameManager.show_banner("WEATHER SERVICE SUPPLY DROP", Color("#ffc365"), 3.2)
	_airdrop_cue()
	Net.rpc_to_run(_announce_drop, [_run])

func end_calm() -> void:
	_pending_drop = false
	if is_instance_valid(airdrop) and not airdrop.opened:
		_remove_drop(_run)
		Net.rpc_to_run(_remove_drop, [_run])

func _drop_point() -> Vector3:
	var registry := RunLoot.find(get_tree())
	var map := registry.get_world_3d().navigation_map
	if NavigationServer3D.map_get_iteration_id(map) == 0:
		return Vector3.INF
	var points: Array[Vector3] = []
	var fallback := Vector3.INF
	var furthest := -INF
	var all_players := GameManager.players()
	var space := registry.get_world_3d().direct_space_state
	for marker: Node3D in get_tree().get_nodes_in_group("crate_spawn"):
		var at := NavigationServer3D.map_get_closest_point(map, marker.global_position)
		if at.distance_to(marker.global_position) > 2.5:
			continue
		var sky := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 0.4, at + Vector3.UP * 45.0, 1)
		if not space.intersect_ray(sky).is_empty():
			continue
		var nearest := INF
		for player: Node3D in all_players:
			var player_nav := NavigationServer3D.map_get_closest_point(map, player.global_position)
			var route := NavigationServer3D.map_get_path(map, player_nav, at, true)
			if route.is_empty() or route[-1].distance_to(at) > 0.9:
				nearest = -INF
				break
			nearest = minf(nearest, player.global_position.distance_to(at))
		if nearest >= 20.0:
			points.append(at)
		if nearest > furthest:
			furthest = nearest
			fallback = at
	return fallback if points.is_empty() else points[RNG.rng.randi_range(0, points.size() - 1)]

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

func request_hold(key: String, mode: String, step: String, player: Node) -> void:
	if Net.is_host():
		_handle_hold(_run, key, mode, step, player)
	else:
		_hold_request.rpc_id(1, _run, key, mode, step)

@rpc("any_peer", "call_remote", "reliable")
func _hold_request(run: int, key: String, mode: String, step: String) -> void:
	var peer := multiplayer.get_remote_sender_id()
	if Net.is_host() and Net.run_peers.has(peer):
		_handle_hold(run, key, mode, step, GameManager.player_for_peer(peer))

func _handle_hold(run: int, key: String, mode: String, step: String, player: Node) -> bool:
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
	if step == "begin":
		_holds[peer] = {"station": station, "mode": mode, "start": _clock}
		return false
	if step != "finish":
		return false
	var hold: Dictionary = _holds.get(peer, {})
	_holds.erase(peer)
	if hold.is_empty() or hold.station != station or hold.mode != mode or _clock - hold.start < 0.48:
		return false
	match mode:
		"airdrop":
			_open_airdrop()
			return true
		"double":
			return _open_double(station, player)
		_:
			if not RunLoot.holder(player).spend_scrap(station.price):
				return false
			_set_price(station, station.price + PRICE_STEP)
			var reward := _roll(player)
			_queue_reward(station, reward[0], reward[1])
			return true

func _valid(player: Node, target: SupplyStation, mode: String) -> bool:
	if not is_instance_valid(player) or not is_instance_valid(target) or player.state != "ok" or not target.available(mode) 			or not GameManager.run_active or GameManager.is_voting() or GameManager.awaiting_tape_choice:
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

func _roll(player: Node) -> Array:
	var tier := RNG.weighted_index([loot.common_weight, loot.rare_weight, loot.cursed_weight, loot.legendary_weight])
	var peer := player.get_multiplayer_authority()
	if _since_cursed >= CURSED_DROUGHT:
		tier = 2
	if tier == 2 and _cursed_last.get(peer, false):
		tier = 1
	_cursed_last[peer] = tier == 2
	_since_cursed = 0 if tier == 2 else _since_cursed + 1
	var pool := loot.pool(tier, WeatherManager.wave)
	var usable := pool.filter(func(id: String): return _useful(id, player))
	var id := _pick(usable if not usable.is_empty() else pool)
	var rarity := ItemCatalog.STANDARD
	if tier == 1:
		rarity = ItemCatalog.OVERCLOCKED if RNG.chance(0.14) else ItemCatalog.TUNED
	elif tier == 3:
		rarity = ItemCatalog.OVERCLOCKED
	return [id, rarity]

func _useful(id: String, player: Node) -> bool:
	match id:
		"ammo_box":
			return RunLoot.holder(player).can_collect_ammo()
		"tarp":
			return not player.has_tarp
		"decon":
			return GameManager.decon_charges < GameManager.decon_max
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
	var pool := loot.pool(1, WeatherManager.wave).filter(func(id: String): return ItemCatalog.definition(id) != null)
	# Air freight has a separate chance at the crate-exclusive legendary.
	var players := GameManager.player_count()
	var space := registry.get_world_3d().direct_space_state
	for i in players:
		var id := "disruptor" if RNG.chance(0.025) else _pick(pool)
		var tier := ItemCatalog.OVERCLOCKED if id == "disruptor" or RNG.chance(0.4) else ItemCatalog.TUNED
		var angle := i * TAU / players
		var offset := Vector3(1.5, 0.0, 0.0).rotated(Vector3.UP, angle)
		var at := _safe_drop_spot(space, point, offset)
		registry.spawn_item(id, at, tier)
	registry.spawn_pickup(null, _safe_drop_spot(space, point, Vector3(0.0, 0.0, 1.4)), "ammo_box")
	_remove_drop(_run)
	Net.rpc_to_run(_remove_drop, [_run])
	GameManager.show_banner("SUPPLY DROP OPENED", Color("#ffc365"), 2.1)

func _safe_drop_spot(space: PhysicsDirectSpaceState3D, center: Vector3, offset: Vector3) -> Vector3:
	var eye := center + Vector3.UP * 0.7
	var start := eye + offset
	if not space.intersect_ray(PhysicsRayQueryParameters3D.create(eye, start, 1)).is_empty():
		return center + Vector3.UP * 0.06
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(start, start - Vector3.UP * 5.0, 1))
	if hit.is_empty():
		return center + Vector3.UP * 0.06
	return (hit.position as Vector3) + Vector3.UP * 0.06

func sync_to_peer(peer: int) -> void:
	var prices: Dictionary = {}
	for key: String in stations.keys():
		var station: Variant = stations[key]
		if is_instance_valid(station):
			var s := station as SupplyStation
			prices[s.key] = s.price
	var drop: Array = [airdrop.global_position, airdrop.descent_left] if is_instance_valid(airdrop) else []
	_snapshot.rpc_id(peer, _run, prices, drop)

@rpc("authority", "call_remote", "reliable")
func _snapshot(run: int, prices: Dictionary, drop: Array) -> void:
	if run < _run:
		return
	_run = run
	var registry := RunLoot.find(get_tree())
	if not registry:
		return
	_stations_from_markers(registry)
	for key: String in prices:
		_price(run, key, prices[key])
	if not drop.is_empty():
		_make_airdrop(drop[0], drop[1])
