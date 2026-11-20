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
##
## The host owns the reels, the timers and the tally; every step is broadcast,
## so all peers show the same result. Pulls and votes are per peer id and come
## to the host, which counts one each.

signal roll_started
signal pulls_changed(pulled: int, needed: int)
signal roll_result(symbols: Array, mutations: Array, jackpot: bool)
signal vote_started(options: Array)
signal vote_cast(index: int)
signal mutations_changed(active: Array)
signal player_mutations_changed(active: Array)

const PULL_TIME := 5.0
const LAND_TIME := 3.0
const VOTE_TIME := 6.0

var table: MutationTable
## Active enemy mutations for the current wave (cleared at Clearing).
var active: Array[String] = []
## Accumulated player mutations for the current run (cleared on new run).
var player_mutations: Array[String] = []
## New player mutation(s) granted by the most recent roll (for the reel UI).
var last_player_mutations: Array[String] = []
var stage := ""  # "", "pulling", "landing", "voting"

var _timer := 0.0
var _pulled := {}            # peer id -> true (host only)
var _pending: Array = []
var _last_jackpot := false
var _votes := {}             # peer id -> option index (host only)
var _local_voted := false
var _local_pulled := false


func _ready() -> void:
	table = load("res://game/mutation_table.tres")


# ------------------------------------------------------------------ steps
func begin() -> void:
	if not Net.is_host():
		return
	_apply_begin()
	Net.rpc_to_all(_begin_rpc)


func _apply_begin() -> void:
	stage = "pulling"
	_timer = PULL_TIME
	_pulled.clear()
	_last_jackpot = false
	_local_voted = false
	_local_pulled = false
	WeatherManager.hold = true
	roll_started.emit()
	pulls_changed.emit(0, GameManager.player_count())


@rpc("authority", "call_remote", "reliable")
func _begin_rpc() -> void:
	_apply_begin()


## Clear wave-scoped enemy mutations (at Clearing). Player mutations persist.
func clear() -> void:
	if not Net.is_host():
		return
	_apply_clear()
	Net.rpc_to_all(_clear_rpc)


func _apply_clear() -> void:
	active.clear()
	stage = ""
	mutations_changed.emit(active)


@rpc("authority", "call_remote", "reliable")
func _clear_rpc() -> void:
	_apply_clear()


## Clear both enemy and player mutations when starting or resetting a run.
func reset_run() -> void:
	if not Net.is_host():
		return
	_apply_reset_run()
	Net.rpc_to_all(_reset_run_rpc)


func _apply_reset_run() -> void:
	active.clear()
	player_mutations.clear()
	last_player_mutations.clear()
	stage = ""
	mutations_changed.emit(active)
	player_mutations_changed.emit(player_mutations)


@rpc("authority", "call_remote", "reliable")
func _reset_run_rpc() -> void:
	_apply_reset_run()


## Late joiner: the enemy and player mutations currently in play.
func sync_to_peer(peer_id: int) -> void:
	if Net.is_host():
		_sync_active.rpc_id(peer_id, active, player_mutations)


@rpc("authority", "call_remote", "reliable")
func _sync_active(enemy_list: Array, player_list: Array) -> void:
	active.assign(enemy_list)
	player_mutations.assign(player_list)
	mutations_changed.emit(active)
	player_mutations_changed.emit(player_mutations)


func has(id: String) -> bool:
	return active.has(id)


func has_player(id: String) -> bool:
	return player_mutations.has(id)


## Dev / testing: activate one enemy mutation immediately.
func force_enemy_mutation(id: String) -> void:
	if not Net.is_host() or table.get_entry(id) == null:
		return
	if not active.has(id):
		active.append(id)
	Net.rpc_to_all(_sync_active, [active, player_mutations])
	mutations_changed.emit(active)
	var entry := table.get_entry(id)
	GameManager.show_banner("MUTATION: " + entry.display_name.to_upper(), entry.color, 2.5)


## Dev / testing or roll reward: add one unowned player mutation.
func grant_random_player_mutation() -> String:
	if not Net.is_host():
		return ""
	var picked := _pick_player_mutations(1)
	if picked.is_empty():
		return ""
	var id: String = picked[0]
	player_mutations.append(id)
	last_player_mutations.assign(picked)
	_apply_player_grant_effects(picked)
	Net.rpc_to_all(_sync_active, [active, player_mutations])
	player_mutations_changed.emit(player_mutations)
	var info: Dictionary = GameManager.PLAYER_MUTATIONS[id]
	GameManager.show_banner("PLAYER MUTATION: " + str(info.name), info.color, 2.6)
	return id


func is_voting() -> bool:
	return stage == "voting"


# ------------------------------------------------------------------ levers
func lever_prompt(player: Node) -> String:
	if stage != "pulling" or player.get("state") != "ok":
		return ""
	if Net.is_host():
		return "" if _pulled.has(player.get_multiplayer_authority()) else "Pull the lever"
	return "" if _local_pulled else "Pull the lever"


func pull(player: Node) -> void:
	if stage != "pulling":
		return
	if not Net.is_host():
		# Show the prompt as spent straight away; the host confirms the count.
		_local_pulled = true
		_request_pull.rpc_id(1)
		return
	_count_pull(player.get_multiplayer_authority())


@rpc("any_peer", "call_remote", "reliable")
func _request_pull() -> void:
	if not Net.is_host() or stage != "pulling":
		return
	_count_pull(multiplayer.get_remote_sender_id())


func _count_pull(peer_id: int) -> void:
	if _pulled.has(peer_id):
		return
	_pulled[peer_id] = true
	var needed := GameManager.player_count()
	pulls_changed.emit(_pulled.size(), needed)
	_sync_pulls.rpc(_pulled.size(), needed)


@rpc("authority", "call_remote", "reliable")
func _sync_pulls(pulled: int, needed: int) -> void:
	pulls_changed.emit(pulled, needed)


# ------------------------------------------------------------------ clock
func _process(delta: float) -> void:
	if stage == "":
		return
	_local_vote_input()
	if not Net.is_host():
		return
	_timer -= delta
	match stage:
		"pulling":
			if _timer <= 0.0 or _pulled.size() >= GameManager.player_count():
				_roll()
		"landing":
			if _timer <= 0.0:
				if _pending.size() > 1:
					_open_vote()
				else:
					_finish(_pending)
		"voting":
			if _timer <= 0.0:
				_resolve_vote()


func _local_vote_input() -> void:
	if stage != "voting" or _local_voted:
		return
	for i in mini(_pending.size(), 2):
		if Input.is_action_just_pressed("weapon_%d" % (i + 1)):
			vote(i)
			return
	if Settings.using_gamepad:
		if Input.is_action_just_pressed("ui_left"):
			vote(0)
		elif Input.is_action_just_pressed("ui_right"):
			vote(1)


## One vote per player per roll. Keys, the reel's buttons and the gamepad all
## come through here; a client's vote is forwarded to the host, which tallies
## by peer id so each player counts once.
func vote(index: int) -> bool:
	if stage != "voting" or _local_voted or index < 0 or index > 1:
		return false
	_local_voted = true
	if Net.is_host():
		_votes[multiplayer.get_unique_id()] = index
	else:
		_request_vote.rpc_id(1, index)
	vote_cast.emit(index)
	return true


@rpc("any_peer", "call_remote", "reliable")
func _request_vote(index: int) -> void:
	if not Net.is_host() or stage != "voting":
		return
	_votes[multiplayer.get_remote_sender_id()] = clampi(index, 0, 1)


func _open_vote() -> void:
	stage = "voting"
	_timer = VOTE_TIME
	_votes.clear()
	_local_voted = false
	vote_started.emit(_pending)
	Net.rpc_to_all(_vote_rpc, [_pending])


@rpc("authority", "call_remote", "reliable")
func _vote_rpc(options: Array) -> void:
	_pending = options
	stage = "voting"
	_timer = VOTE_TIME
	_votes.clear()
	_local_voted = false
	vote_started.emit(options)


## Host: cancel the option that fewer people voted for.
func _resolve_vote() -> void:
	var zero := 0
	var one := 0
	for peer_id in _votes:
		if int(_votes[peer_id]) == 0:
			zero += 1
		else:
			one += 1
	var cancel := 0
	if one > zero:
		cancel = 1
	elif zero == one:
		cancel = RNG.rng.randi_range(0, 1)
	var keep: Array = _pending.duplicate()
	keep.remove_at(cancel)
	_finish(keep)


# ------------------------------------------------------------------ reels
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
	_last_jackpot = jackpot
	_pending = [pick]
	if jackpot:
		var rest := table.entries.filter(func(e): return e.id != pick)
		_pending.append(rest[RNG.weighted_index(rest.map(func(e): return e.weight))].id)
	stage = "landing"
	_timer = LAND_TIME
	roll_result.emit(symbols, _pending, jackpot)
	Net.rpc_to_all(_result_rpc, [symbols, _pending, jackpot])


@rpc("authority", "call_remote", "reliable")
func _result_rpc(symbols: Array, pending: Array, jackpot: bool) -> void:
	_pending = pending
	stage = "landing"
	roll_result.emit(symbols, pending, jackpot)


func _pick_player_mutations(count: int) -> Array[String]:
	var pool: Array[String] = []
	for id in GameManager.PLAYER_MUTATIONS.keys():
		if not player_mutations.has(id):
			pool.append(id)
	var picked: Array[String] = []
	for _i in count:
		if pool.is_empty():
			break
		var idx := RNG.rng.randi_range(0, pool.size() - 1)
		picked.append(pool[idx])
		pool.remove_at(idx)
	return picked


func _apply_player_grant_effects(granted: Array) -> void:
	if not Net.is_host():
		return
	if "chitin_suit" in granted:
		for p in GameManager.players():
			if p.has_method("apply_max_health_bonus"):
				p.apply_max_health_bonus(25.0)


func _finish(result: Array) -> void:
	var granted := _pick_player_mutations(2 if _last_jackpot else 1)
	var updated_player: Array = player_mutations.duplicate()
	for id in granted:
		if not updated_player.has(id):
			updated_player.append(id)
	_apply_player_grant_effects(granted)
	_apply_finish(result, updated_player, granted, true)
	Net.rpc_to_all(_finish_rpc, [result, updated_player, granted])
	WeatherManager.hold = false
	if WeatherManager.phase == WeatherManager.Phase.MUTATION_ROLL:
		WeatherManager.next_phase()


func _apply_finish(result: Array, player_list: Array, granted: Array, announce: bool) -> void:
	active.assign(result)
	player_mutations.assign(player_list)
	last_player_mutations.assign(granted)
	stage = ""
	mutations_changed.emit(active)
	player_mutations_changed.emit(player_mutations)
	if announce and not active.is_empty():
		var enemy_names := active.map(func(id): return table.get_entry(id).display_name.to_upper())
		var text := "ENEMIES: " + " + ".join(PackedStringArray(enemy_names))
		if not granted.is_empty():
			var p_names := granted.map(func(id): return str(GameManager.PLAYER_MUTATIONS[id].name))
			text += "  |  YOU: " + " + ".join(PackedStringArray(p_names))
		GameManager.show_banner(text, table.get_entry(active[0]).color, 3.2)


@rpc("authority", "call_remote", "reliable")
func _finish_rpc(result: Array, player_list: Array, granted: Array) -> void:
	# The host's show_banner already reached this peer; don't re-broadcast.
	_apply_finish(result, player_list, granted, false)
