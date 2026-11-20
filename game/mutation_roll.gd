extends Node
## Child of GameManager: the Mutation Roll.
## 1. Mutation Roll phase starts: WeatherManager holds the phase; every player
##    gets "[E] Pull the lever" (5 s, or until everyone has pulled).
## 2. The host spins three reels (weighted). The symbol on 2+ reels is the
##    wave's mutation; three different symbols = the middle reel's.
## 3. Three of a kind = JACKPOT: a second mutation stacks on top and players
##    vote (keys 1 / 2, 6 s) to cancel one of the two.
## 4. The result is announced and the storm moves on to Drizzle. Mutations last
##    until Clearing.

signal roll_started
signal pulls_changed(pulled: int, needed: int)
signal roll_result(symbols: Array, mutations: Array, jackpot: bool)
signal vote_started(options: Array)
signal vote_cast(index: int)
signal mutations_changed(active: Array)

const PULL_TIME := 5.0
const LAND_TIME := 3.0
const VOTE_TIME := 6.0

var table: MutationTable


func _ready() -> void:
	table = load("res://game/mutation_table.tres")
var active: Array[String] = []
var stage := ""  # "", "pulling", "landing", "voting"
var _timer := 0.0
var _pulled := {}
var _pending: Array = []
var _votes := {}
var _local_voted := false


func begin() -> void:
	stage = "pulling"
	_timer = PULL_TIME
	_pulled.clear()
	_local_voted = false
	WeatherManager.hold = true
	roll_started.emit()
	pulls_changed.emit(0, GameManager.player_count())


func clear() -> void:
	active.clear()
	stage = ""
	mutations_changed.emit(active)


func has(id: String) -> bool:
	return active.has(id)


func lever_prompt(player: Node) -> String:
	if stage == "pulling" and not _pulled.has(player.get_instance_id()) and player.get("state") == "ok":
		return "Pull the lever"
	return ""


func pull(player: Node) -> void:
	if stage != "pulling":
		return
	_pulled[player.get_instance_id()] = true
	pulls_changed.emit(_pulled.size(), GameManager.player_count())


func is_voting() -> bool:
	return stage == "voting"


func _process(delta: float) -> void:
	if stage == "":
		return
	if stage == "voting" and not _local_voted:
		for i in 2:
			if Input.is_action_just_pressed("weapon_%d" % (i+1)):
				vote(i)
		if Settings.using_gamepad:
			if Input.is_action_just_pressed("ui_left"):
				vote(0)
			elif Input.is_action_just_pressed("ui_right"):
				vote(1)
	_timer -= delta
	match stage:
		"pulling":
			if _timer <= 0.0 or _pulled.size() >= GameManager.player_count():
				_roll()
		"landing":
			if _timer <= 0.0:
				if _pending.size() > 1:
					stage = "voting"
					_timer = VOTE_TIME
					_votes.clear()
					vote_started.emit(_pending)
				else:
					_finish(_pending)
		"voting":
			if _timer <= 0.0:
				var cancel := 0 if int(_votes.get(0, 0)) > int(_votes.get(1, 0)) else (1 if int(_votes.get(1, 0)) > int(_votes.get(0, 0)) else RNG.rng.randi_range(0, 1))
				var keep: Array = _pending.duplicate()
				keep.remove_at(cancel)
				_finish(keep)


func _roll() -> void:
	var weights := table.weights()
	var symbols: Array = []
	for i in 3:
		symbols.append(table.entries[RNG.weighted_index(weights)].id)
	var pick: String = symbols[1]
	for s in symbols:
		if symbols.count(s) >= 2:
			pick = s
	var jackpot: bool = symbols.count(symbols[0]) == 3
	_pending = [pick]
	if jackpot:
		var rest := table.entries.filter(func(e): return e.id != pick)
		_pending.append(rest[RNG.weighted_index(rest.map(func(e): return e.weight))].id)
	stage = "landing"
	_timer = LAND_TIME
	roll_result.emit(symbols, _pending, jackpot)


func _finish(result: Array) -> void:
	active.assign(result)
	stage = ""
	mutations_changed.emit(active)
	var perks := GameManager.active_perks()
	if not perks.is_empty() and GameManager.is_host():
		var names := perks.map(func(p): return p[0])
		GameManager.show_banner("PERK: " + " + ".join(PackedStringArray(names)), Color("6ee7f2"), 2.4)
	WeatherManager.hold = false
	if WeatherManager.phase == WeatherManager.Phase.MUTATION_ROLL:
		WeatherManager.next_phase()


func vote(index: int) -> bool:
	if stage != "voting" or _local_voted or index < 0 or index > 1:
		return false
	_local_voted = true
	_votes[index] = int(_votes.get(index,0)) + 1
	vote_cast.emit(index)
	return true
