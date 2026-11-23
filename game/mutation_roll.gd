extends Node
## Child of GameManager: the Mutation Draft (replaces the old slot reel).
## 1. Calm starts after a cleared wave (wave 2+): WeatherManager holds Calm
##    (its countdown pauses). The host rolls the wave's ENEMY mutation
##    (weighted, not chosen) and deals three PLAYER mutation cards.
## 2. Everyone picks one player card with 1 / 2 / 3 (D-pad on a controller).
##    Solo, the pick resolves at once; in a session the host tallies one vote
##    per peer and resolves when everyone has voted or DRAFT_TIME runs out
##    (most votes wins, ties at random, no votes = a random card).
## 3. The enemy mutation is active until Clearing; the picked player mutation
##    joins the squad's list for the run. After the result shows, the hold
##    lifts and the rest of Calm (shopping, ready-up) plays out as normal.
##
## The host owns the deck, the timer and the tally; every step is broadcast so
## every peer shows the same cards and result.

signal cards_dealt(enemy: String, cards: Array)
signal votes_changed(counts: Array)
signal vote_cast(index: int)
signal draft_resolved(index: int)
signal mutations_changed(active: Array)
signal player_mutations_changed(active: Array)

const DRAFT_TIME := 14.0
const RESULT_TIME := 2.2

var table: MutationTable
## Active enemy mutations for the current wave (cleared at Clearing).
var active: Array[String] = []
## Accumulated player mutations for the current run (cleared on new run).
var player_mutations: Array[String] = []
## Player mutation(s) granted by the most recent draft (for the HUD/banner).
var last_player_mutations: Array[String] = []
## "" | "voting" | "result"
var stage := ""
## This wave's rolled enemy mutation id.
var enemy_pick := ""
## The three dealt player mutation ids to choose between.
var cards: Array = []
var vote_counts: Array = [0, 0, 0]
var local_pick := -1
var time_left := 0.0

var _votes := {}  # peer id -> card index (host only)


func _ready() -> void:
	table = load("res://game/mutation_table.tres")


# ------------------------------------------------------------------ deal
func begin() -> void:
	if not Net.is_host():
		return
	WeatherManager.hold = true
	var plan := WeatherManager.WavePlan
	var forecast := WeatherManager.wave_modifier()
	var enemy: String = plan.FORECAST_MUTATION.get(forecast, "")
	var dealt: Array = []
	for id: String in plan.DRAFT_COUNTERS.get(forecast, []):
		if not player_mutations.has(id):
			dealt.append(id)
	dealt.append_array(_pick_player_mutations(3 - dealt.size(), dealt))
	_apply_deal(enemy, dealt)
	Net.rpc_to_all(_deal_rpc, [enemy, dealt])


func _apply_deal(enemy: String, dealt: Array) -> void:
	enemy_pick = enemy
	cards = dealt
	stage = "voting"
	time_left = DRAFT_TIME
	vote_counts = [0, 0, 0]
	local_pick = -1
	_votes.clear()
	cards_dealt.emit(enemy_pick, cards)
	votes_changed.emit(vote_counts)
	# Nothing left to draft (every player mutation owned): just apply the enemy.
	if cards.is_empty():
		time_left = 1.5


@rpc("authority", "call_remote", "reliable")
func _deal_rpc(enemy: String, dealt: Array) -> void:
	WeatherManager.hold = true
	_apply_deal(enemy, dealt)


# ------------------------------------------------------------------ vote
func is_voting() -> bool:
	return stage == "voting"


## One pick per player per draft; it can be changed until the draft resolves.
func vote(index: int) -> bool:
	if stage != "voting" or index < 0 or index >= cards.size():
		return false
	if local_pick == index:
		return false
	local_pick = index
	vote_cast.emit(index)
	if Net.is_host():
		_count_vote(multiplayer.get_unique_id() if Net.is_online() else 1, index)
	else:
		_request_vote.rpc_id(1, index)
	return true


@rpc("any_peer", "call_remote", "reliable")
func _request_vote(index: int) -> void:
	if not Net.is_host() or stage != "voting":
		return
	_count_vote(multiplayer.get_remote_sender_id(), clampi(index, 0, cards.size() - 1))


func _count_vote(peer_id: int, index: int) -> void:
	_votes[peer_id] = index
	vote_counts = [0, 0, 0]
	for p in _votes:
		vote_counts[int(_votes[p])] += 1
	votes_changed.emit(vote_counts)
	Net.rpc_to_all(_votes_rpc, [vote_counts])
	if _votes.size() >= GameManager.player_count():
		# Everyone has picked: resolve after a beat so the last pick shows.
		time_left = minf(time_left, 0.6)


@rpc("authority", "call_remote", "reliable")
func _votes_rpc(counts: Array) -> void:
	vote_counts = counts
	votes_changed.emit(vote_counts)


# ------------------------------------------------------------------ clock
func _process(delta: float) -> void:
	if stage == "":
		return
	time_left = maxf(0.0, time_left - delta)
	if stage == "voting":
		_local_input()
	if stage == "result" and time_left <= 0.0:
		# Every peer lifts its own hold once the result has shown, so the Calm
		# countdown resumes and ready-up opens. The draft never ends Calm.
		_finish_draft()
		return
	if not Net.is_host():
		return
	if stage == "voting" and time_left <= 0.0:
		_resolve()


func _finish_draft() -> void:
	stage = ""
	WeatherManager.hold = false
	if Net.is_host() and WeatherManager.phase == WeatherManager.Phase.MUTATION_ROLL:
		# Legacy phase value: go on to the storm like Calm would.
		WeatherManager.next_phase()


func _local_input() -> void:
	if Net.dedicated or get_tree().paused or not MenuState.stack.is_empty():
		return
	if get_tree().get_first_node_in_group("mutation_draft_ui") != null:
		return
	for i in cards.size():
		if Input.is_action_just_pressed("weapon_%d" % (i + 1)):
			vote(i)
			return
	if Settings.using_gamepad:
		if Input.is_action_just_pressed("ui_left"):
			vote(0)
		elif Input.is_action_just_pressed("ui_up"):
			vote(1)
		elif Input.is_action_just_pressed("ui_right"):
			vote(2)


func _resolve() -> void:
	var best := -1
	var top: Array = []
	for i in cards.size():
		var c: int = vote_counts[i]
		if c > best:
			best = c
			top = [i]
		elif c == best:
			top.append(i)
	var pick: int = top[RNG.rng.randi_range(0, top.size() - 1)] if not top.is_empty() else -1
	var enemy_list: Array = active.duplicate() if GameManager.endless else []
	if not enemy_pick.is_empty() and enemy_pick not in enemy_list:
		enemy_list.append(enemy_pick)
	var granted: Array = []
	var updated_player: Array = player_mutations.duplicate()
	if pick >= 0 and pick < cards.size() and not updated_player.has(cards[pick]):
		updated_player.append(cards[pick])
		granted.append(cards[pick])
	_apply_player_grant_effects(granted)
	_apply_result(pick, enemy_list, updated_player, granted, true)
	Net.rpc_to_all(_result_rpc, [pick, enemy_list, updated_player, granted])


func _apply_result(pick: int, enemy_list: Array, player_list: Array, granted: Array, _announce: bool) -> void:
	Perf.mark("mutation apply enemy=%s squad=%s" % [enemy_pick, str(granted[0]) if not granted.is_empty() else "none"])
	stage = "result"
	time_left = RESULT_TIME
	active.assign(enemy_list)
	player_mutations.assign(player_list)
	last_player_mutations.assign(granted)
	draft_resolved.emit(pick)
	mutations_changed.emit(active)
	player_mutations_changed.emit(player_mutations)
	# No result banner: the draft strip just showed both picks and the HUD
	# mutation row pulses with the new icons.


@rpc("authority", "call_remote", "reliable")
func _result_rpc(pick: int, enemy_list: Array, player_list: Array, granted: Array) -> void:
	# Clients apply the result quietly, like the host.
	_apply_result(pick, enemy_list, player_list, granted, false)


# ------------------------------------------------------------------ run scope
## Clear wave-scoped enemy mutations (at Clearing). Player mutations persist.
func clear() -> void:
	if not Net.is_host():
		return
	_apply_clear()
	Net.rpc_to_all(_clear_rpc)


func _apply_clear() -> void:
	active.clear()
	if stage != "":
		WeatherManager.hold = false
	stage = ""
	cards.clear()
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
	cards.clear()
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
		if stage == "voting":
			_deal_rpc.rpc_id(peer_id, enemy_pick, cards)


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


## No lever any more; kept so old callers compile.
func lever_prompt(_player: Node) -> String:
	return ""


func pull(_player: Node) -> void:
	pass


# ------------------------------------------------------------------ dev helpers
## Dev / testing: activate one enemy mutation immediately.
func force_enemy_mutation(id: String) -> void:
	if not Net.is_host() or table.get_entry(id) == null:
		return
	if not active.has(id):
		active.append(id)
	Net.rpc_to_all(_sync_active, [active, player_mutations])
	mutations_changed.emit(active)
	var entry := table.get_entry(id)
	GameManager.show_banner(entry.display_name.to_upper(), entry.color, 2.5)


## Dev / testing: add one unowned player mutation.
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
	GameManager.show_banner(str(info.name).to_upper(), info.color, 2.6)
	return id


func _pick_player_mutations(count: int, exclude: Array = []) -> Array[String]:
	var pool: Array[String] = []
	for id in GameManager.PLAYER_MUTATIONS.keys():
		if not player_mutations.has(id) and id not in exclude:
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
