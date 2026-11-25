extends Node
## One headless Cloud Play client, controlled by one car over a local WebSocket.
## The supervisor allocates each process an ephemeral loopback listener.

const PROTOCOL := 1
const SNAPSHOT_INTERVAL := 0.05
const MAX_PACKET_BYTES := 4096
const MAX_QUEUED_INPUTS := 32
const INPUT_TIMEOUT_MS := 500
const MOVE_ACTIONS := [&"move_left", &"move_right", &"move_forward", &"move_back"]
const BUTTON_ACTIONS := [
	&"fire", &"aim", &"jump", &"crouch", &"sprint", &"reload", &"interact",
	&"use_item", &"drop_item", &"ping", &"ready_up", &"throw_grenade", &"throw_dome",
]
const Feed := preload("res://game/car_bridge_feed.gd")

var upstream := Net.CLOUD_URL
var _listener := TCPServer.new()
var _socket: WebSocketPeer
var _deadline_ms := 0
var _closing := false
var _state := ""
var _maps: Array[Dictionary] = []
var _last_lobby := ""
var _player: Player
var _loot: RunLoot
var _feed: Feed
var _snapshot_left := 0.0
var _tick := 0
var _starter_retry_ms := 0
var _draft_open := false
var _inputs: Array[Dictionary] = []
var _last_input_ms := 0
var _last_seq := -1
var _ack := -1
var _move := Vector2.ZERO
var _look := Vector2.ZERO
var _has_look := false
var _buttons := 0
var _slot := 0
var _wheel := 0
var _slot_action: StringName
var _wheel_action: StringName


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_physics_priority = -100
	Engine.max_fps = 60
	_start.call_deferred()


func _start() -> void:
	var port := 8790
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--listen="):
			var value := arg.trim_prefix("--listen=")
			port = value.to_int() if value.is_valid_int() else -1
		elif arg.begins_with("--upstream="):
			upstream = arg.trim_prefix("--upstream=")
	if port < 0 or port > 65535 or not (upstream.begins_with("ws://") or upstream.begins_with("wss://")):
		push_error("Car bridge: invalid --listen or --upstream")
		get_tree().quit(1)
		return
	var error := _listener.listen(port, "127.0.0.1")
	if error != OK:
		push_error("Car bridge: could not listen on port %d (%s)" % [port, error_string(error)])
		get_tree().quit(1)
		return
	if get_tree().current_scene:
		get_tree().unload_current_scene()
	for map in Maps.available():
		if not map.get("dev_only", false):
			_maps.append({"id": map.id, "name": map.name})
	Net.roster_changed.connect(_on_roster)
	Net.chat_received.connect(func(_from: String, _message: String): _send_lobby())
	Net.connection_failed.connect(func():
		_fail(Net.last_error if not Net.last_error.is_empty() else "Could not join the upstream lobby"))
	Net.server_closed.connect(func(): _disconnect("Upstream server disconnected"))
	Net.run_started.connect(_on_load)
	GameManager.run_finished.connect(_on_results)
	GameManager.banner.connect(func(message: String, _color: Color, _seconds: float):
		if _feed: _feed.event({"e": "banner", "text": message}))
	GameManager.mutations.cards_dealt.connect(_on_draft)
	GameManager.mutations.draft_resolved.connect(func(_index: int):
		if _draft_open:
			_draft_open = false
			_send({"t": "draft_done"}))
	GameManager.tape_choice_changed.connect(_on_tape)
	WeatherManager.lightning_struck.connect(_on_lightning)
	WeatherManager.ambient_lightning_struck.connect(_on_lightning)
	print("CAR_BRIDGE_LISTEN %d" % _listener.get_local_port())


func _process(delta: float) -> void:
	if not _socket:
		if not _listener.is_connection_available():
			return
		var stream := _listener.take_connection()
		stream.set_no_delay(true)
		_listener.stop()
		_socket = WebSocketPeer.new()
		_socket.inbound_buffer_size = 65536
		_socket.outbound_buffer_size = 262144
		_socket.heartbeat_interval = 2.0
		_deadline_ms = Time.get_ticks_msec() + 5000
		if _socket.accept_stream(stream) != OK:
			get_tree().quit(1)
			return
	_socket.poll()
	var now := Time.get_ticks_msec()
	if _socket.get_ready_state() == WebSocketPeer.STATE_CLOSED:
		_leave()
		get_tree().quit()
		return
	if _closing:
		if now >= _deadline_ms:
			get_tree().quit()
		return
	if _deadline_ms > 0 and now >= _deadline_ms:
		_fail("Connection timed out")
		return
	for _i in mini(_socket.get_available_packet_count(), 64):
		var packet := _socket.get_packet()
		if not _socket.was_string_packet() or packet.size() > MAX_PACKET_BYTES:
			_fail("Expected a JSON text frame of at most %d bytes" % MAX_PACKET_BYTES)
			return
		var message: Variant = JSON.parse_string(packet.get_string_from_utf8())
		if not message is Dictionary:
			_fail("Expected a JSON object")
			return
		_receive(message)
		if _closing:
			return
	if _state == "loading":
		_check_player()
	if _state == "run":
		if not _loot.starter_chosen and _loot.starter_available() and now >= _starter_retry_ms:
			_loot.choose_starter(0)
			_starter_retry_ms = now + 500
		_snapshot_left -= delta
		if _snapshot_left <= 0.00001:
			_snapshot_left = maxf(0.0, _snapshot_left + SNAPSHOT_INTERVAL)
			_tick += 1
			_send(_feed.snapshot(_player, _loot, _tick, _ack, now))
			_flush_events()


func _receive(message: Dictionary) -> void:
	var kind: Variant = message.get("t")
	if _state.is_empty():
		if kind != "hello" or _integer(message.get("v"), 0, 1, 0) != PROTOCOL:
			_fail("Expected hello with car protocol v%d" % PROTOCOL)
			return
		var name_value: Variant = message.get("name")
		var callsign: String = name_value.strip_edges().left(18) if name_value is String else ""
		Net.local_name = "CAR" if callsign.is_empty() else callsign
		_status("connecting")
		_deadline_ms = Time.get_ticks_msec() + 10000
		if Net.join_cloud() != OK:
			_fail(Net.last_error)
		return
	match kind:
		"ping":
			_send({"t": "pong", "ms": message.get("ms")})
		"leave":
			_disconnect("Left Cloud Play")
		"lobby":
			if _state in ["lobby", "results"]:
				_lobby_action(message)
		"in":
			if _state == "run":
				_queue_input(message)
		"choice":
			if _state == "run":
				_choose(message)


func _lobby_action(message: Dictionary) -> void:
	match message.get("a"):
		"ready":
			if message.get("v") is bool:
				Net.set_ready(message.v)
		"vote":
			if message.get("map") is String:
				Net.vote_for_map(message.map)
		"start":
			Net.force_start()
		"chat":
			if message.get("text") is String:
				Net.send_chat(message.text)


func _on_roster() -> void:
	if _closing or not Net.is_online() or not Net.roster.has(Net.local_id()):
		return
	if _state == "connecting":
		_deadline_ms = 0
		_send({"t": "welcome", "v": PROTOCOL, "game_protocol": Net.PROTOCOL, "you": Net.local_id(), "maps": _maps})
		_status("lobby")
	_send_lobby()


func _send_lobby() -> void:
	if _closing or _state not in ["lobby", "results"]:
		return
	var roster := []
	for id in Net.roster:
		var info: Dictionary = Net.roster[id]
		var own: bool = id == Net.local_id()
		roster.append({"id": id, "name": info.name, "ready": info.ready,
			"vote": Net.lobby_my_vote if own else null, "car": true if own else null})
	var chat := []
	for entry in Net.chat_log:
		chat.append({"from": entry[0], "text": entry[1]})
	var data := JSON.stringify({"t": "lobby", "players": roster, "maps": _maps,
		"countdown": -1, "chat": chat, "vote_counts": Net.lobby_vote_counts})
	if data != _last_lobby:
		_last_lobby = data
		_send_text(data)


func _on_load() -> void:
	_status("loading")
	_send({"t": "load", "map": Net.run_map_id})
	_feed = Feed.new(get_tree())
	_snapshot_left = 0.0
	_starter_retry_ms = 0
	_last_lobby = ""
	_load_scene.call_deferred()


func _load_scene() -> void:
	if not _closing and get_tree().change_scene_to_file(Maps.RUN_SCENE) != OK:
		_fail("Could not load the run scene")


func _check_player() -> void:
	var player := get_tree().get_first_node_in_group("local_player") as Player
	var loot := RunLoot.find(get_tree())
	if not player or not loot or loot.run_id == 0 or not Net.can_send_run_rpc():
		return
	_player = player
	_loot = loot
	_player.hurt_from.connect(_feed.hurt_from.bind(_player))
	_status("run")
	if GameManager.mutations.is_voting():
		_on_draft(GameManager.mutations.enemy_pick, GameManager.mutations.cards)
	if GameManager.awaiting_tape_choice:
		_on_tape()


func _on_draft(_enemy: String, dealt: Array) -> void:
	if _state != "run":
		return
	var cards := []
	for id in dealt:
		var def: Dictionary = GameManager.PLAYER_MUTATIONS.get(id, {})
		cards.append({"id": id, "title": def.get("name"), "desc": def.get("desc"), "icon": id})
	_draft_open = true
	_send({"t": "draft", "kind": "mutation", "cards": cards, "time_left": GameManager.mutations.time_left})


func _on_tape() -> void:
	if _state == "run" and GameManager.awaiting_tape_choice:
		_send({"t": "tape", "time_left": null, "can_choose": Net.local_id() == GameManager.tape_decider()})


func _choose(message: Dictionary) -> void:
	match message.get("kind"):
		"mutation":
			var index := _integer(message.get("i"), 0, 2, -1)
			if index >= 0:
				GameManager.mutations.vote(index)
		"tape":
			var index := _integer(message.get("i"), 0, 1, -1)
			if index >= 0:
				GameManager.choose_tape(index == 0)


func _on_results(won: bool, results: Dictionary) -> void:
	if _state not in ["run", "loading"]:
		return
	_flush_events()
	_clear_input()
	_status("results")
	var players := []
	var kills := 0
	for row: Dictionary in results.get("players", {}).values():
		players.append({"name": row.name, "kills": row.kills,
			"downs": row.get("downs"), "revives": row.revives})
		kills += int(row.kills)
	_send({"t": "results", "won": won, "time_s": results.seconds, "waves": results.waves,
		"kills": kills, "players": players, "score": results.endless_score})
	_return_to_lobby.call_deferred()


func _return_to_lobby() -> void:
	if _closing:
		return
	_player = null
	_loot = null
	_feed = null
	_draft_open = false
	MenuState.reset()
	Net.end_run()
	GameManager.run_active = false
	GameManager.mutations.clear()
	WeatherManager.stop()
	get_tree().unload_current_scene()
	_send_lobby()


func _queue_input(message: Dictionary) -> void:
	var seq := _integer(message.get("seq"), 0, 9007199254740991, -1)
	if seq <= _last_seq:
		return
	var mv: Variant = message.get("mv")
	if not mv is Array or mv.size() != 2 or not _number(mv[0]) or not _number(mv[1]):
		return
	if not _number(message.get("yaw")) or not _number(message.get("pitch")):
		return
	_last_seq = seq
	_last_input_ms = Time.get_ticks_msec()
	var move := Vector2(clampf(mv[0], -1.0, 1.0), clampf(mv[1], -1.0, 1.0)).limit_length()
	var look := Vector2(wrapf(message.yaw, -PI, PI), clampf(message.pitch, -PI, PI))
	if not look.is_finite():
		return
	if _inputs.size() >= MAX_QUEUED_INPUTS:
		_inputs.pop_front()
	_inputs.append({"seq": seq, "move": move, "look": look,
		"buttons": _integer(message.get("b"), 0, (1 << BUTTON_ACTIONS.size()) - 1, 0),
		"slot": _integer(message.get("slot"), 0, 5, 0),
		"wheel": _integer(message.get("wheel"), -1, 1, 0)})


func _physics_process(_delta: float) -> void:
	if not is_instance_valid(_player) or _state != "run":
		return
	_release_weapon_edges()
	if Time.get_ticks_msec() - _last_input_ms > INPUT_TIMEOUT_MS or get_tree().paused:
		_set_move(Vector2.ZERO)
		_set_buttons(0)
		if get_tree().paused and _inputs.size() > 1:
			_inputs = [_inputs.back()]
		elif not get_tree().paused:
			_inputs.clear()
		return
	if not _inputs.is_empty():
		var frame: Dictionary = _inputs.pop_front()
		_look = frame.look
		_has_look = true
		_set_move(frame.move)
		_set_buttons(frame.buttons)
		_weapon_edges(frame.slot, frame.wheel)
		_ack = frame.seq
	if _has_look and not GameManager.awaiting_tape_choice:
		_player.apply_bridge_look(_look.x, _look.y)
	if Input.is_action_just_pressed("ping"):
		_ping()


func _set_move(move: Vector2) -> void:
	if move == _move:
		return
	_move = move
	var strengths := [-move.x, move.x, -move.y, move.y]
	for i in MOVE_ACTIONS.size():
		if strengths[i] > 0.0:
			Input.action_press(MOVE_ACTIONS[i], strengths[i])
		else:
			Input.action_release(MOVE_ACTIONS[i])


func _set_buttons(buttons: int) -> void:
	var changed := _buttons ^ buttons
	for i in BUTTON_ACTIONS.size():
		var bit := 1 << i
		if not (changed & bit):
			continue
		if buttons & bit:
			Input.action_press(BUTTON_ACTIONS[i])
		else:
			Input.action_release(BUTTON_ACTIONS[i])
	_buttons = buttons


func _weapon_edges(slot: int, wheel: int) -> void:
	if slot != _slot and slot != 0:
		_slot_action = StringName("weapon_%d" % slot)
		Input.action_press(_slot_action)
	if wheel != _wheel and wheel != 0:
		_wheel_action = &"weapon_next" if wheel > 0 else &"weapon_prev"
		Input.action_press(_wheel_action)
	_slot = slot
	_wheel = wheel


func _release_weapon_edges() -> void:
	if not _slot_action.is_empty():
		Input.action_release(_slot_action)
		_slot_action = &""
	if not _wheel_action.is_empty():
		Input.action_release(_wheel_action)
		_wheel_action = &""


func _ping() -> void:
	if GameManager.is_voting() or GameManager.awaiting_tape_choice:
		return
	var pings := get_tree().current_scene.get_node("Pings") as PingSystem
	if _player.state == "downed":
		pings.send("revive", _player.global_position)
	elif _player.state == "ok":
		var ping := pings.context_ping(_player)
		pings.send(ping.kind, ping.pos, ping.get("enemy_id", 0))


func _clear_input() -> void:
	_inputs.clear()
	_set_move(Vector2.ZERO)
	_set_buttons(0)
	_release_weapon_edges()
	_slot = 0
	_wheel = 0
	_has_look = false
	_last_seq = -1
	_ack = -1


func _on_lightning(at: Vector3, _seed: int) -> void:
	if _feed:
		_feed.lightning = true
		_feed.event({"e": "lightning", "at": Feed.vec(at)})
		record_sound("thunder", at)


func record_shot(by: int, weapon: String, muzzle: Vector3, traces: Array) -> void:
	if not _feed:
		return
	var start := Feed.vec(muzzle)
	for trace: Array in traces:
		_feed.event({"e": "shot", "by": by, "weapon": weapon, "from": start, "to": Feed.vec(trace[0])})


func record_hit(at: Vector3, amount: int, critical: bool) -> void:
	if _feed:
		_feed.event({"e": "hit", "at": Feed.vec(at), "head": critical, "dmg": amount})


func record_kill(id: int, enemy: EnemyBase, at: Vector3) -> void:
	if _feed:
		_feed.event({"e": "kill", "enemy": id, "type": Feed.enemy_type(enemy) if enemy else null})
		record_sound("enemy_death", at)


func record_boss_kill() -> void:
	if _feed:
		_feed.event({"e": "kill", "enemy": 0, "type": "cumulus"})


func record_hurt(amount: float) -> void:
	if _feed:
		_feed.hurt(amount)


func record_pickup(item: String) -> void:
	if _feed:
		_feed.event({"e": "pickup", "item": item})


func record_sound(cue: String, at: Variant) -> void:
	if _feed:
		_feed.event({"e": "sound", "name": cue, "at": Feed.vec(at) if at is Vector3 else null})


func _flush_events() -> void:
	if _feed:
		var events := _feed.take_events()
		if not events.is_empty():
			_send({"t": "ev", "list": events})


func _status(state: String, message := "") -> void:
	_state = state
	_send({"t": "status", "state": state, "msg": message})


func _send(message: Dictionary) -> void:
	_send_text(JSON.stringify(message, "", false))


func _send_text(data: String) -> void:
	if not _closing and _socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
		if _socket.send_text(data) != OK:
			_close.call_deferred()


func _fail(message: String) -> void:
	_send({"t": "error", "msg": message})
	_close()


func _disconnect(message: String) -> void:
	_status("disconnected", message)
	_close()


func _close() -> void:
	if _closing:
		return
	_closing = true
	_leave()
	_deadline_ms = Time.get_ticks_msec() + 1000
	_socket.close()


func _leave() -> void:
	_clear_input()
	if Net.is_online():
		Net.leave()


static func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))


static func _integer(value: Variant, low: int, high: int, fallback: int) -> int:
	if _number(value) and value >= low and value <= high and floorf(value) == value:
		return int(value)
	return fallback
