extends Node
## Child of GameManager: mystery crates (host).
## - Each Calm: old crates go, CRATES_PER_CALM new ones appear at random
##   crate_spawn markers; from wave 2 one is a Double-or-nothing crate (needs 2
##   players, so not in solo).
## - Opening rolls LootTable.tres: 70% common, 25% rare, 5% cursed. Pity rule:
##   nobody gets a cursed weapon twice in a row (rerolls to rare).
## - Double-or-nothing: 50% both openers get a rare, 50% a cursed weapon is
##   forced on a random player.

const DOUBLE_WINDOW := 1.5

var loot: LootTable
var CrateScene: PackedScene
var DoubleCrateScene: PackedScene
## Drought protection: after this many crates without a cursed roll, the
## next eligible roll is cursed.
const CURSED_DROUGHT := 8
var _since_cursed := 0
var _last_cursed := {}  # player instance id -> true if their last roll was cursed
var _double_waiting := {}  # crate instance id -> [player, time]
var _clock := 0.0
var _crate_seq := 0


func _ready() -> void:
	loot = load("res://crates/loot_table.tres")
	CrateScene = load("res://crates/crate.tscn")
	DoubleCrateScene = load("res://crates/double_crate.tscn")


func _process(delta: float) -> void:
	_clock += delta


func spawn_for_calm() -> void:
	if not Net.is_host():
		return
	var parent := _container()
	if parent == null:
		return
	Perf.mark("crates spawn wave %d" % WeatherManager.wave)
	for old in get_tree().get_nodes_in_group("crates"):
		old.queue_free()
	Net.rpc_to_run(_clear_crates, [])
	var markers := get_tree().get_nodes_in_group("crate_spawn").duplicate()
	markers.shuffle()
	var count := mini(GameManager.CRATES_PER_CALM[GameManager.player_count()], markers.size())
	for i in count:
		var double := i == 0 and WeatherManager.wave >= 2 and not GameManager.is_solo()
		# Names are the contract: a client's "open crate" request finds the same
		# path here, so every crate gets a unique one for the whole run.
		_crate_seq += 1
		var node_name := "C_%d" % _crate_seq
		var at: Vector3 = (markers[i] as Node3D).global_position
		var yaw := randf() * TAU
		_spawn(parent, node_name, double, at, yaw)
		Net.rpc_to_run(_spawn_crate, [node_name, double, at, yaw])
	# Playtest: the gap between rounds felt empty. Drop one crate a few steps
	# in front of every player so there's always something to open nearby.
	var map: RID = parent.get_world_3d().navigation_map
	for player in GameManager.players():
		if player.get("state") == "dead" or not (player is Node3D):
			continue
		var forward: Vector3 = -(player as Node3D).global_basis.z
		forward.y = 0.0
		var want: Vector3 = (player as Node3D).global_position + forward.normalized() * 3.0
		var at: Vector3 = want
		if NavigationServer3D.map_get_iteration_id(map) > 0:
			at = NavigationServer3D.map_get_closest_point(map, want)
		_crate_seq += 1
		var node_name := "C_%d" % _crate_seq
		var yaw := randf() * TAU
		_spawn(parent, node_name, false, at, yaw)
		Net.rpc_to_run(_spawn_crate, [node_name, false, at, yaw])


func sync_to_peer(peer_id: int) -> void:
	for crate in get_tree().get_nodes_in_group("crates"):
		if not crate.is_queued_for_deletion() and not crate.get_node("Interact").opened:
			_spawn_crate.rpc_id(peer_id, crate.name, crate.double, crate.global_position, crate.rotation.y)


func _spawn(parent: Node, node_name: String, double: bool, at: Vector3, yaw: float) -> void:
	var crate := (DoubleCrateScene if double else CrateScene).instantiate()
	crate.name = node_name
	crate.set("double", double)
	parent.add_child(crate, true)
	crate.global_position = at
	crate.rotation.y = yaw


@rpc("authority", "call_remote", "reliable")
func _spawn_crate(node_name: String, double: bool, at: Vector3, yaw: float) -> void:
	var parent := _container()
	if parent == null or parent.has_node(node_name):
		return
	_spawn(parent, node_name, double, at, yaw)


@rpc("authority", "call_remote", "reliable")
func _clear_crates() -> void:
	for old in get_tree().get_nodes_in_group("crates"):
		old.queue_free()


func open(crate: Node, player: Node) -> void:
	var interact: Node = crate.get_node("Interact")
	if interact.opened:
		return
	if crate.double:
		_open_double(crate, player)
		return
	interact.opened = true
	var item := _roll(player)
	_reveal(crate, item)
	get_tree().create_timer(1.3).timeout.connect(_give.bind(player, item))


func _open_double(crate: Node, player: Node) -> void:
	var key := crate.get_instance_id()
	var waiting: Array = _double_waiting.get(key, [])
	if GameManager.is_solo():
		# Solo variant: the same coin flip, both outcomes land on you.
		waiting = [player, _clock]
	if not waiting.is_empty() and (waiting[0] != player or GameManager.is_solo()) and _clock - float(waiting[1]) <= DOUBLE_WINDOW:
		crate.get_node("Interact").opened = true
		_double_waiting.erase(key)
		var partner: Node = waiting[0]
		if RNG.chance(0.5):
			var a: String = loot.rare_items.pick_random()
			var b: String = loot.rare_items.pick_random()
			_reveal(crate, a, "TWO RARES!")
			get_tree().create_timer(1.3).timeout.connect(_give.bind(player, a))
			get_tree().create_timer(1.3).timeout.connect(_give.bind(partner, b))
		else:
			var cursed: String = loot.cursed_items.pick_random()
			var victim: Node = player if GameManager.is_solo() else GameManager.players().pick_random()
			_reveal(crate, cursed, "CURSED for %s!" % victim.get("display_name"))
			get_tree().create_timer(1.3).timeout.connect(_give.bind(victim, cursed))
	else:
		_double_waiting[key] = [player, _clock]
		if crate.has_method("set_partner_waiting"):
			crate.set_partner_waiting(DOUBLE_WINDOW)


func _roll(player: Node) -> String:
	var tier := RNG.weighted_index([loot.common_weight, loot.rare_weight, loot.cursed_weight])
	var pid := player.get_instance_id()
	if _since_cursed >= CURSED_DROUGHT and not loot.cursed_items.is_empty():
		tier = 2
	if tier == 2 and _last_cursed.get(pid, false):
		tier = 1
	_last_cursed[pid] = tier == 2
	_since_cursed = 0 if tier == 2 else _since_cursed + 1
	var items: Array = [loot.common_items, loot.rare_items, loot.cursed_items][tier]
	if items.is_empty():
		items = loot.common_items
	# Reroll within the tier against what this player can actually use, then
	# fall back to ammo or a decon charge instead of a wasted reward.
	var useful := items.filter(func(i): return _is_useful(player, i))
	if not useful.is_empty():
		return useful[RNG.rng.randi() % useful.size()]
	return "ammo" if _is_useful(player, "ammo") else "decon"


func _is_useful(player: Node, item: String) -> bool:
	var holder: Node = player.get_node_or_null("Head/Camera3D/WeaponHolder")
	match item:
		"medkit":
			return float(player.get("health")) < float(player.get("max_health")) * 0.95
		"suit_patch":
			return float(player.get("suit_integrity")) < 95.0
		"tarp":
			return not player.get("has_tarp")
		"flares":
			if holder == null:
				return false
			return holder.loadout.any(func(w): return w.kind == WeaponData.Kind.FLARE)
		"ammo", "base_ammo":
			if holder == null:
				return true
			for i in holder.loadout.size():
				if holder.reserve[i] < holder.loadout[i].reserve_ammo:
					return true
			return false
	return true


## Every peer plays the spin and lands on the same result.
func _reveal(crate: Node, item: String, override_text := "") -> void:
	var pool: Array = (loot.common_items + loot.rare_items + loot.cursed_items).map(func(i): return loot.display_name(i))
	var text := override_text if override_text != "" else loot.display_name(item)
	var tier := loot.tier_of(item)
	_apply_reveal(crate.name, text, tier, pool, item)
	_apply_reveal.rpc(crate.name, text, tier, pool, item)


@rpc("authority", "call_remote", "reliable")
func _apply_reveal(node_name: String, text: String, tier: String, pool: Array, item_id: String) -> void:
	var parent := _container()
	if parent == null:
		return
	var crate := parent.get_node_or_null(node_name)
	if crate == null:
		return
	# Opened is host state, but every peer's prompt has to stop offering it.
	var interact := crate.get_node_or_null("Interact")
	if interact:
		interact.set("opened", true)
	crate.play_spin(text, tier, pool, item_id)


func _give(player: Node, item: String) -> void:
	if not is_instance_valid(player):
		return
	if item == "decon":
		GameManager.add_decon_charge(1)
		return
	if item.begins_with("weapon:"):
		var w := load(item.trim_prefix("weapon:")) as WeaponData
		if w:
			GameManager.record_cursed(player, w.display_name)
	player.grant(item)


func _container() -> Node:
	var scene := GameManager._world()
	if scene == null:
		return null
	var holder := scene.get_node_or_null("Crates")
	if holder == null:
		holder = Node3D.new()
		holder.name = "Crates"
		scene.add_child(holder)
	return holder
