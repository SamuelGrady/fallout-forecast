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
var _last_cursed := {}  # player instance id -> true if their last roll was cursed
var _double_waiting := {}  # crate instance id -> [player, time]
var _clock := 0.0


func _ready() -> void:
	loot = load("res://crates/loot_table.tres")
	CrateScene = load("res://crates/crate.tscn")
	DoubleCrateScene = load("res://crates/double_crate.tscn")


func _process(delta: float) -> void:
	_clock += delta


func spawn_for_calm() -> void:
	var parent := _container()
	if parent == null:
		return
	for old in get_tree().get_nodes_in_group("crates"):
		old.queue_free()
	var markers := get_tree().get_nodes_in_group("crate_spawn").duplicate()
	markers.shuffle()
	var count := mini(GameManager.CRATES_PER_CALM[GameManager.player_count()], markers.size())
	for i in count:
		var double := i == 0 and WeatherManager.wave >= 2 and not GameManager.is_solo()
		var crate := (DoubleCrateScene if double else CrateScene).instantiate()
		parent.add_child(crate, true)
		crate.global_position = (markers[i] as Node3D).global_position
		crate.rotation.y = randf() * TAU


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
	if not waiting.is_empty() and waiting[0] != player and _clock - float(waiting[1]) <= DOUBLE_WINDOW:
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
			var victim: Node = GameManager.players().pick_random()
			_reveal(crate, cursed, "CURSED for %s!" % victim.get("display_name"))
			get_tree().create_timer(1.3).timeout.connect(_give.bind(victim, cursed))
	else:
		_double_waiting[key] = [player, _clock]
		GameManager.show_banner("DOUBLE OR NOTHING: a partner has %.1f s!" % DOUBLE_WINDOW, Color("FFE04A"), 1.5)


func _roll(player: Node) -> String:
	var tier := RNG.weighted_index([loot.common_weight, loot.rare_weight, loot.cursed_weight])
	var pid := player.get_instance_id()
	if tier == 2 and _last_cursed.get(pid, false):
		tier = 1
	_last_cursed[pid] = tier == 2
	var items: Array = [loot.common_items, loot.rare_items, loot.cursed_items][tier]
	if items.is_empty():
		items = loot.common_items
	return items[RNG.rng.randi() % items.size()]


func _reveal(crate: Node, item: String, override_text := "") -> void:
	var pool: Array = (loot.common_items + loot.rare_items + loot.cursed_items).map(func(i): return loot.display_name(i))
	var text := override_text if override_text != "" else loot.display_name(item)
	crate.play_spin(text, loot.tier_of(item), pool)


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
