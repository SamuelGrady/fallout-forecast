extends Node
## Common Open Protocol listener and the authoritative Thin tier.

const Wire := preload("res://game/open_protocol_wire.gd")
const Binary := preload("res://game/thin_client_binary.gd")
const Feed := preload("res://game/thin_client_feed.gd")
const MapOutline := preload("res://game/thin_client_map.gd")
const FULL_TIER_PATH := "res://game/open_protocol/full_tier.gd"
const VERSION := 1
const MAX_CONNECTIONS := 12


class Session:
	var wire: Wire
	var input: ThinClientInput
	var state := ""
	var rate := 20
	var radius := 0.0
	var max_enemies := -1
	var next_snap := 0
	var tick := 0
	var last_lobby := {}
	var feed: Feed
	var draft_open := false


var _websocket := TCPServer.new()
var _raw := TCPServer.new()
var _join_code := ""
var _sessions: Array[Session] = []
var _by_id: Dictionary = {}
var _next_id := 2
var _maps: Array[Dictionary] = []
var _map_cache := {}
var _downs := {}


func listen(ws_port: int, tcp_port: int, join_code: String) -> Error:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_join_code = join_code
	if ws_port > 0:
		var err := _websocket.listen(ws_port)
		if err != OK:
			return err
	if tcp_port > 0:
		var err := _raw.listen(tcp_port)
		if err != OK:
			_websocket.stop()
			return err
	for map in Maps.available():
		if not map.get("dev_only", false):
			_maps.append({"id": map.id, "name": map.name})
	Net.roster_changed.connect(_broadcast_lobby)
	Net.chat_received.connect(func(_who: String, _message: String): _broadcast_lobby())
	Net.run_started.connect(_start_run)
	GameManager.run_finished.connect(_on_results)
	GameManager.banner.connect(func(message: String, _color: Color, _seconds: float):
		_record_event({"e": "banner", "text": message}))
	GameManager.mutations.cards_dealt.connect(_on_draft)
	GameManager.mutations.draft_resolved.connect(func(_index: int):
		for session: Session in _by_id.values():
			if session.draft_open:
				session.draft_open = false
				session.wire.send_message({"t": "draft_done"}))
	GameManager.tape_choice_changed.connect(_on_tape)
	WeatherManager.lightning_struck.connect(_on_lightning)
	WeatherManager.ambient_lightning_struck.connect(_on_lightning)
	return OK


func _process(_delta: float) -> void:
	_accept(_websocket, true)
	_accept(_raw, false)
	var now := Time.get_ticks_msec()
	for session: Session in _sessions.duplicate():
		var packets := session.wire.poll(1 if session.state.is_empty() else Wire.MAX_BATCH)
		if session.wire.closed:
			_dispose(session)
			continue
		for packet in packets:
			_receive(session, packet)
			if session.wire.closing or session not in _sessions:
				break
		if session not in _sessions or session.wire.closing or not session.input:
			continue
		if session.state == "loading":
			_check_player(session)
		if session.state == "run" and now >= session.next_snap:
			_snapshot(session, now)


func _accept(listener: TCPServer, websocket: bool) -> void:
	for _i in 4:
		if not listener.is_connection_available():
			return
		var stream := listener.take_connection()
		if _sessions.size() >= MAX_CONNECTIONS:
			stream.disconnect_from_host()
			continue
		var session := Session.new()
		session.wire = Wire.new(stream, websocket)
		_sessions.append(session)


func input_for(id: int) -> ThinClientInput:
	var session: Session = _by_id.get(id)
	return session.input if session else null


func _receive(session: Session, packet: Dictionary) -> void:
	var message: Variant
	if packet.text:
		message = JSON.parse_string(packet.data.get_string_from_utf8())
	elif session.wire.encoding == "bin" and session.input:
		message = Binary.input(packet.data)
	if not message is Dictionary or not message.get("t") is String:
		_fail(session, "Expected an Open Protocol message")
		return
	if session.state.is_empty():
		_hello(session, message)
		return
	match message.t:
		"ping":
			session.wire.send_message({"t": "pong", "ms": message.get("ms")})
		"leave":
			_status(session, "disconnected", "Left session")
			_release_player(session)
			session.wire.close()
		"lobby":
			if session.state in ["lobby", "results"]:
				_lobby_action(session.input.id, message)
		"in":
			if session.state == "run":
				session.input.enqueue(message)
		"choice":
			if session.state == "run":
				_choose(session.input.id, message)
		"map_req":
			_send_map(session)


func _hello(session: Session, message: Dictionary) -> void:
	if message.t != "hello" or ThinClientInput.integer(message.get("v"), 1, 1, 0) != VERSION:
		_fail(session, "Expected hello with Open Protocol v%d" % VERSION)
		return
	if not _join_code.is_empty() and message.get("code") != _join_code:
		_fail(session, "Invalid join code")
		return
	var enc: Variant = message.get("enc", "json")
	if enc not in ["json", "bin"]:
		_fail(session, "Unsupported encoding")
		return
	session.wire.encoding = enc
	session.wire.deadline = 0
	match message.get("tier", "thin"):
		"full":
			if ResourceLoader.exists(FULL_TIER_PATH):
				_sessions.erase(session)
				var tier = load(FULL_TIER_PATH)
				tier.accept(session.wire, message)
			else:
				_fail(session, "full tier unavailable")
			return
		"thin":
			pass
		_:
			_fail(session, "Unsupported tier")
			return
	if Net.roster.size() >= Net.MAX_PLAYERS:
		_fail(session, "SERVER FULL")
		return
	var name_value: Variant = message.get("name")
	var callsign := Net._clean_chat(name_value).left(18) if name_value is String else ""
	while Net.roster.has(_next_id) or _next_id in multiplayer.get_peers():
		_next_id += 1
	var id := _next_id
	_next_id += 1
	session.rate = ThinClientInput.integer(message.get("rate"), 2, 20, 20)
	var radius: Variant = message.get("radius")
	session.radius = clampf(radius, 1, 500) if ThinClientInput.number(radius) and radius > 0 else 0.0
	session.max_enemies = ThinClientInput.integer(message.get("max_enemies"), 0, 256, -1)
	session.input = ThinClientInput.new(id)
	_by_id[id] = session
	Net.add_thin_player(id, "THIN PLAYER" if callsign.is_empty() else callsign)
	session.wire.send_message({"t": "welcome", "v": VERSION, "game_protocol": Net.PROTOCOL, "you": id,
		"maps": _maps, "tier": "thin", "enc": enc, "rate": session.rate,
		"radius": session.radius, "max_enemies": session.max_enemies})
	_status(session, "lobby")
	_send_lobby(session)
	if Net.run_active:
		_load_run(session)


func _release_player(session: Session) -> void:
	if session.input:
		var id := session.input.id
		session.input.clear()
		session.input = null
		_by_id.erase(id)
		Net.remove_roster_peer(id)
		GameManager.remove_ready_peer(id)
		GameManager.mutations.remove_vote(id)
		_on_tape()


func _dispose(session: Session) -> void:
	_release_player(session)
	session.wire.dispose()
	_sessions.erase(session)


func _fail(session: Session, message: String) -> void:
	session.wire.send_message({"t": "error", "msg": message})
	_release_player(session)
	session.wire.close()


func _status(session: Session, state: String, msg := "") -> void:
	session.state = state
	session.wire.send_message({"t": "status", "state": state, "msg": msg})


func _lobby_action(id: int, message: Dictionary) -> void:
	match message.get("a"):
		"ready":
			if message.get("v") is bool:
				Net.set_ready_for_peer(id, message.v)
		"vote":
			if message.get("map") is String:
				Net.set_vote_for_peer(id, message.map)
		"start":
			Net.force_start_for_peer(id)
		"chat":
			if message.get("text") is String:
				Net.send_chat_for_peer(id, message.text)


func _broadcast_lobby() -> void:
	for session: Session in _by_id.values():
		_send_lobby(session)


func _send_lobby(session: Session) -> void:
	if session.state != "lobby":
		return
	var players := []
	for id: int in Net.roster:
		var info: Dictionary = Net.roster[id]
		players.append({"id": id, "name": info.name, "ready": info.ready,
			"vote": Net._map_votes.get(id, ""), "car": Net.is_thin_peer(id)})
	var chat := []
	for entry in Net.chat_log:
		chat.append({"from": entry[0], "text": entry[1]})
	var data := {"t": "lobby", "players": players, "maps": _maps,
		"countdown": -1, "chat": chat, "vote_counts": Net.lobby_vote_counts.duplicate()}
	if data != session.last_lobby:
		session.last_lobby = data
		session.wire.send_message(data)


func _start_run() -> void:
	_downs.clear()
	for session: Session in _by_id.values():
		_load_run(session)


func _load_run(session: Session) -> void:
	session.input.clear()
	session.feed = Feed.new(get_tree())
	session.feed.radius = session.radius
	session.feed.max_enemies = session.max_enemies
	session.next_snap = 0
	_status(session, "loading")
	session.wire.send_message({"t": "load", "map": Net.run_map_id})


func _check_player(session: Session) -> void:
	var player := GameManager.player_for_peer(session.input.id) as Player
	var loot := RunLoot.find(get_tree())
	if not GameManager.run_active or not player or not loot or loot.run_id == 0:
		return
	player.damaged.connect(session.feed.hurt)
	player.hurt_from.connect(session.feed.hurt_from.bind(player))
	loot.choose_thin_starter(session.input.id)
	_status(session, "run")
	if GameManager.mutations.is_voting():
		_send_draft(session, GameManager.mutations.cards)
	if GameManager.awaiting_tape_choice:
		_send_tape(session)


func _snapshot(session: Session, now: int) -> void:
	var player := GameManager.player_for_peer(session.input.id) as Player
	var loot := RunLoot.find(get_tree())
	if not player or not loot:
		return
	var interval := 1000.0 / session.rate
	session.next_snap = maxi(now + 1, session.next_snap + roundi(interval))
	session.tick += 1
	var frame := session.feed.snapshot(player, loot, session.tick, session.input.ack, now)
	if session.wire.encoding == "bin":
		session.wire.send_binary(Binary.snapshot(frame))
	else:
		session.wire.send_message(frame)
	_flush_events(session)


func _send_map(session: Session) -> void:
	var id := Net.run_map_id if Net.run_active else ""
	if not _map_cache.has(id):
		var scene := get_tree().current_scene
		var level := scene.get_node_or_null("Level") as Node3D if scene else null
		if id.is_empty() or level == null:
			session.wire.send_message({"t": "map", "id": null, "boxes": [], "bounds": null})
			return
		_map_cache[id] = MapOutline.describe(level, id)
	session.wire.send_message(_map_cache[id])


func _on_draft(_enemy: String, cards: Array) -> void:
	for session: Session in _by_id.values():
		if session.state == "run":
			_send_draft(session, cards)


func _send_draft(session: Session, dealt: Array) -> void:
	var cards := []
	for id in dealt:
		var def: Dictionary = GameManager.PLAYER_MUTATIONS.get(id, {})
		cards.append({"id": id, "title": def.get("name"), "desc": def.get("desc"), "icon": id})
	session.draft_open = true
	session.wire.send_message({"t": "draft", "kind": "mutation", "cards": cards,
		"time_left": GameManager.mutations.time_left})


func _on_tape() -> void:
	if GameManager.awaiting_tape_choice:
		for session: Session in _by_id.values():
			if session.state == "run":
				_send_tape(session)


func _send_tape(session: Session) -> void:
	session.wire.send_message({"t": "tape", "time_left": null,
		"can_choose": session.input.id == GameManager.tape_decider()})


func _choose(id: int, message: Dictionary) -> void:
	var index := ThinClientInput.integer(message.get("i"), 0, 2, -1)
	match message.get("kind"):
		"mutation":
			GameManager.mutations.vote_for_peer(id, index)
		"tape":
			if index in [0, 1]:
				GameManager._apply_tape_choice(id, index == 0)


func _on_results(won: bool, results: Dictionary) -> void:
	var players := []
	var kills := 0
	for peer: int in results.players:
		var row: Dictionary = results.players[peer]
		players.append({"name": row.name, "kills": row.kills, "downs": _downs.get(peer, 0),
			"revives": row.revives})
		kills += int(row.kills)
	for session: Session in _by_id.values():
		_flush_events(session)
		session.input.clear()
		_status(session, "results")
		session.wire.send_message({"t": "results", "won": won, "time_s": results.seconds,
			"waves": results.waves, "kills": kills, "players": players, "score": results.endless_score})


func lobby_reset() -> void:
	for session: Session in _by_id.values():
		session.feed = null
		session.last_lobby = {}
		session.draft_open = false
		_status(session, "lobby")
		_send_lobby(session)


func ping(player: Player) -> void:
	var pings := get_tree().current_scene.get_node("Pings") as PingSystem
	if player.state == "downed":
		pings.send_for_peer(player.peer_id(), "revive", player.global_position)
	elif player.state == "ok":
		var row := pings.context_ping(player)
		pings.send_for_peer(player.peer_id(), row.kind, row.pos, row.enemy_id)


func _on_lightning(at: Vector3, _seed: int) -> void:
	for session: Session in _by_id.values():
		if session.feed:
			session.feed.lightning = true
	_record_event({"e": "lightning", "at": Feed.vec(at)})
	record_sound("thunder", at)


func record_shot(by: int, weapon: String, origin: Vector3, dir: Vector3, traces: Array) -> void:
	if _by_id.is_empty():
		return
	var muzzle := origin + dir * 0.55
	for trace: Array in traces:
		_record_event({"e": "shot", "by": by, "weapon": weapon, "from": Feed.vec(muzzle),
			"to": Feed.vec(trace[0])})
	var data := ItemCatalog.definition(weapon).weapon
	if not data.shot_sound.is_empty():
		record_sound(data.shot_sound, muzzle)


func record_hit(id: int, at: Vector3, amount: int, critical: bool) -> void:
	_record_event({"e": "hit", "at": Feed.vec(at), "head": critical, "dmg": amount}, id)


func record_down(id: int) -> void:
	_downs[id] = int(_downs.get(id, 0)) + 1


func record_kill(enemy: EnemyBase) -> void:
	_record_event({"e": "kill", "enemy": enemy.net_id, "type": Feed.enemy_type(enemy)})


func record_boss_kill() -> void:
	_record_event({"e": "kill", "enemy": 0, "type": "cumulus"})


func record_pickup(id: int, item: String) -> void:
	_record_event({"e": "pickup", "item": item}, id)
	_record_event({"e": "sound", "name": "pickup", "at": null}, id)


func record_sound(cue: String, at: Variant) -> void:
	if not _by_id.is_empty():
		_record_event({"e": "sound", "name": cue, "at": Feed.vec(at) if at is Vector3 else null})


func _record_event(row: Dictionary, only := 0) -> void:
	for peer: int in _by_id:
		if only == 0 or peer == only:
			var session: Session = _by_id[peer]
			if session.feed:
				session.feed.event(row)


func _flush_events(session: Session) -> void:
	if session.feed:
		var events := session.feed.take_events()
		if not events.is_empty():
			session.wire.send_message({"t": "ev", "list": events})
