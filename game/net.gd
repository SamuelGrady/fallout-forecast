extends Node
## Autoload "Net": the session, the lobby roster and LAN discovery.
##
## One place answers "am I the host?". Every script used to carry its own copy
## of that check; now they all ask Net. Offline counts as host, exactly as
## before, so solo play runs the same code path as a hosted game.
##
## Transport is WebSocketMultiplayerPeer everywhere (so browser builds can
## play): a LAN host listens for ws:// on TCP PORT, and the cloud server sits
## behind Caddy's TLS at CLOUD_URL (wss://). Topology is client/server.
## Clients can only talk to the host, never to each other, so every
## client-to-client message goes client -> host -> clients: see the
## "_push_* / _apply_*" pairs on Player and MutationRoll.
##
## Discovery (desktop only; browsers have no UDP): the host answers UDP probes
## on DISCOVERY_PORT; the join screen broadcasts a probe to 255.255.255.255
## (and 127.0.0.1, so a second window on the same machine shows up) and lists
## whatever answers. The reply advertises the host's ws port.

signal roster_changed
signal servers_changed
signal peer_joined(peer_id: int)
signal run_started
signal connection_failed
signal server_closed
signal joined_server

## The public dedicated server (server/README.md). Desktop and web builds both
## join it with join_cloud(); keep this URL stable, the web export uses it.
const CLOUD_URL := "wss://fallout.drew.place/"
const CLOUD_HOST := "fallout.drew.place"
## Bump whenever an rpc or the scene layout changes: a client and server on
## different builds are turned away with a message instead of desyncing.
const PROTOCOL := 11
## Give up on a join that hasn't connected after this long.
const CONNECT_TIMEOUT := 8.0

## WebSocket (TCP) port a host listens on; the cloud container uses it too.
const PORT := 7777
const DISCOVERY_PORT := 7778
const MAX_PLAYERS := 4
const GAME_ID := "acidrain"
const PROBE := "acidrain:probe"
const SCAN_INTERVAL := 1.0
## A server not seen for this long drops off the list.
const SERVER_TIMEOUT := 3.0
const PING_INTERVAL := 1.0

enum Mode { OFFLINE, HOST, CLIENT }

var mode: Mode = Mode.OFFLINE
var local_name := ""
## peer id -> {"name": String, "ready": bool, "color": int, "skin": int}
## color / skin index Cosmetics.COLORS / SKINS; the host keeps colours unique.
var roster := {}
## Lobby choice can be RANDOM. The run id always names an actual level.
var lobby_map_id := Maps.DEFAULT_ID
var run_map_id := Maps.DEFAULT_ID
var lobby_votes_enabled := false
var lobby_vote_counts := {}
var lobby_my_vote := ""
## Host only. Remote peers get the counts and their own confirmed choice.
var _map_votes := {}
## ip -> {"name": String, "players": int, "max": int, "port": int}
var servers := {}
## True between the lobby's START and the results screen.
var run_active := false
## Headless dedicated server (`-- --server`): hosts with no local player, so
## peer 1 is never in the roster. See game/dedicated_server.gd.
var dedicated := false
## Why the last join failed, for the join screen ("" = no answer).
var last_error := ""
## Host-measured smoothed RTT in milliseconds per connected client peer id.
var peer_rtt_ms := {}
## Client: most recent RTT reported back from the host (ms).
var local_rtt_ms := 0.0

var _connect_left := 0.0
var _host_port := PORT
var _ping_timer := 0.0
var _ping_seq := 0
var _ping_sent_ms := {}  # peer_id -> {"seq": int, "ms": int}

var _beacon: PacketPeerUDP
var _scout: PacketPeerUDP
var _scanning := false
var _scan_timer := 0.0
var _seen := {}


func _ready() -> void:
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	if "--server" in OS.get_cmdline_user_args():
		dedicated = true
		var server := Node.new()
		server.name = "DedicatedServer"
		server.set_script(load("res://game/dedicated_server.gd"))
		add_child(server)


func _process(delta: float) -> void:
	if _connect_left > 0.0:
		_connect_left -= delta
		if _connect_left <= 0.0 and mode == Mode.CLIENT:
			last_error = "NO ANSWER FROM THE SERVER."
			_on_connection_failed()
	if mode == Mode.HOST and is_online():
		_ping_timer -= delta
		if _ping_timer <= 0.0:
			_ping_timer = PING_INTERVAL
			_send_rtt_pings()
	if _beacon:
		_pump_beacon()
	if _scanning:
		_scan_timer -= delta
		if _scan_timer <= 0.0:
			_scan_timer = SCAN_INTERVAL
			_send_probe()
		_pump_scout()
		_expire_servers()


# ------------------------------------------------------------------ session
## Offline is the host of a game of one. Clients are the only non-hosts.
func is_host() -> bool:
	return mode != Mode.CLIENT


## A joined session, as opposed to solo. Guards every rpc that needs a peer.
func is_online() -> bool:
	return mode != Mode.OFFLINE and multiplayer.has_multiplayer_peer()


func is_offline() -> bool:
	return mode == Mode.OFFLINE


func local_id() -> int:
	return multiplayer.get_unique_id()


func peer_count() -> int:
	return maxi(roster.size(), 1)


## Browsers can't host or listen for LAN probes; they only join.
func can_host() -> bool:
	return not OS.has_feature("web")


## Open a session. Returns OK, or an error the lobby can show.
## as_player = false is the dedicated server: no roster entry for peer 1.
func host(port := PORT, as_player := true, default_map := Maps.DEFAULT_ID) -> Error:
	leave()
	if not can_host():
		return ERR_UNAVAILABLE
	var peer := WebSocketMultiplayerPeer.new()
	var err := peer.create_server(port)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	_host_port = port
	mode = Mode.HOST
	lobby_map_id = Maps.fallback(default_map)
	lobby_votes_enabled = not as_player
	var custom := Settings.player_name.strip_edges().left(18)
	local_name = (custom if custom != "" else "HOST") if as_player else "CLOUD SERVER"
	roster.clear()
	if as_player:
		roster[1] = {"name": local_name, "ready": false}
		_assign_cosmetic(1, Settings.suit_color, Settings.suit_skin)
	start_beacon()
	roster_changed.emit()
	return OK


## Join the public cloud server (CLOUD_URL). Same path on desktop and web.
func join_cloud() -> Error:
	return join(cloud_url())


## The server JOIN GAME uses: Settings' custom address, or the public one.
func cloud_url() -> String:
	var custom := Settings.server_url.strip_edges()
	return to_url(custom) if custom != "" else CLOUD_URL


## "192.168.1.20", "host:9000", "ws://..." or "wss://..." -> a WebSocket URL.
func to_url(address: String, port := PORT) -> String:
	var target := address.strip_edges()
	if target.begins_with("ws://") or target.begins_with("wss://"):
		return target
	var colon := target.rfind(":")
	if colon > 0 and target.count(":") == 1:
		return "ws://%s/" % target
	return "ws://%s:%d/" % [target, port]


## Join a session. connection_failed / joined_server arrive later, by signal.
## address is anything to_url() accepts.
func join(address: String, port := PORT) -> Error:
	leave()
	last_error = ""
	var url := to_url(address, port)
	var peer := WebSocketMultiplayerPeer.new()
	var err := peer.create_client(url)
	if err != OK:
		last_error = "BAD ADDRESS %s." % url
		return err
	# Set the mode before the peer, so the handshake's callbacks see CLIENT.
	mode = Mode.CLIENT
	roster.clear()
	multiplayer.multiplayer_peer = peer
	_connect_left = CONNECT_TIMEOUT
	return OK


## Drop the session. Safe to call when there isn't one.
func leave() -> void:
	chat_log.clear()
	stop_beacon()
	stop_scanning()
	mode = Mode.OFFLINE
	run_active = false
	lobby_map_id = Maps.DEFAULT_ID
	run_map_id = Maps.DEFAULT_ID
	lobby_votes_enabled = false
	lobby_vote_counts.clear()
	lobby_my_vote = ""
	_map_votes.clear()
	run_peers.clear()
	_connect_left = 0.0
	roster.clear()
	peer_rtt_ms.clear()
	_ping_sent_ms.clear()
	local_rtt_ms = 0.0
	# Mode is already OFFLINE, so the disconnects this triggers are ignored.
	# Back to Godot's default offline peer, not null: with no peer at all,
	# every is_multiplayer_authority() and rpc() in solo play errors.
	if not multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	roster_changed.emit()


## Anyone can start the run without waiting for everyone to ready up. A player
## host starts it directly; a client asks the host, which starts it (the
## dedicated server listens for force_start_requested).
signal force_start_requested(by: String)


func force_start() -> void:
	if is_host():
		if dedicated:
			force_start_requested.emit(local_name)
		else:
			request_start()
	elif is_online():
		_request_force_start.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func _request_force_start() -> void:
	if not is_host() or run_active:
		return
	var peer := multiplayer.get_remote_sender_id()
	if not roster.has(peer):
		return
	var who := str(roster[peer].get("name", "PLAYER"))
	if dedicated:
		force_start_requested.emit(who)
	else:
		request_start()


func set_ready(value: bool) -> void:
	if is_host():
		if roster.has(1):
			roster[1]["ready"] = value
		_broadcast_roster()
		roster_changed.emit()
	elif is_online():
		_request_ready.rpc_id(1, value)


func set_lobby_map(id: String) -> void:
	if not is_host() or not is_online() or run_active or lobby_votes_enabled:
		return
	if id == Maps.RANDOM_ID or Maps.is_available(id):
		lobby_map_id = id
		_broadcast_roster()
		roster_changed.emit()


func vote_for_map(id: String) -> void:
	if not is_host() and is_online() and lobby_votes_enabled and not run_active:
		_request_map_vote.rpc_id(1, id)


@rpc("any_peer", "call_remote", "reliable")
func _request_map_vote(id: String) -> void:
	if not is_host() or run_active or not lobby_votes_enabled:
		return
	var peer := multiplayer.get_remote_sender_id()
	if not roster.has(peer) or (id != Maps.RANDOM_ID and not Maps.is_available(id)):
		return
	_map_votes[peer] = id
	_broadcast_roster()
	roster_changed.emit()


## Change our suit colour / skin. The host may hand back a different colour
## if someone already wears that one; the roster says what we really got.
func set_cosmetic(color: int, skin: int) -> void:
	if not is_online() or run_active:
		return
	if is_host():
		if roster.has(1):
			_assign_cosmetic(1, color, skin)
			_broadcast_roster()
			roster_changed.emit()
	else:
		_request_cosmetic.rpc_id(1, color, skin)


# ------------------------------------------------------------------ lobby chat
## A line of lobby chat arrived (from anyone, including us via the host).
signal chat_received(sender: String, text: String)
const CHAT_MAX := 100
const CHAT_HISTORY := 30
## Recent lines, so someone opening the lobby sees the conversation.
var chat_log: Array = []  # [[sender, text], ...]
var _chat_last_ms := {}   # peer id -> last accepted message (host only)


## Send a chat line. Goes through the host, which cleans and rate-limits it.
func send_chat(text: String) -> void:
	var clean := _clean_chat(text)
	if clean == "" or not is_online():
		return
	if is_host():
		_accept_chat(1, local_name, clean)
	else:
		_request_chat.rpc_id(1, clean)


@rpc("any_peer", "call_remote", "reliable")
func _request_chat(text: String) -> void:
	if not is_host():
		return
	var peer := multiplayer.get_remote_sender_id()
	if not roster.has(peer):
		return
	_accept_chat(peer, str(roster[peer].get("name", "PLAYER")), _clean_chat(text))


func _accept_chat(peer: int, sender: String, text: String) -> void:
	if text == "":
		return
	var now := Time.get_ticks_msec()
	if now - int(_chat_last_ms.get(peer, -10000)) < 700:
		return
	_chat_last_ms[peer] = now
	if dedicated:
		print("[chat] %s: %s" % [sender, text])
	rpc_to_all(_chat_rpc, [sender, text])
	_store_chat(sender, text)


@rpc("authority", "call_remote", "reliable")
func _chat_rpc(sender: String, text: String) -> void:
	_store_chat(sender, _clean_chat(text))


func _store_chat(sender: String, text: String) -> void:
	chat_log.append([sender, text])
	if chat_log.size() > CHAT_HISTORY:
		chat_log.pop_front()
	chat_received.emit(sender, text)


## Plain text only: no control characters, no BBCode, length-capped.
func _clean_chat(text: String) -> String:
	var out := ""
	for ch in text.strip_edges():
		var code := ch.unicode_at(0)
		if code >= 32 and code != 127:
			out += ch
	return out.replace("[", "(").replace("]", ")").left(CHAT_MAX)


func set_display_name(new_name: String) -> void:
	var clean := new_name.strip_edges().left(18)
	if clean == "":
		return
	local_name = clean
	if not is_online():
		return
	if is_host():
		if roster.has(1):
			roster[1]["name"] = clean
			_broadcast_roster()
			roster_changed.emit()
	else:
		_request_name.rpc_id(1, clean)


## Host: store a peer's look, nudging the colour to the next free one.
func _assign_cosmetic(peer_id: int, color: int, skin: int) -> void:
	var taken := []
	for other in roster:
		if int(other) != peer_id:
			taken.append(int(roster[other].get("color", -1)))
	roster[peer_id]["color"] = Cosmetics.free_color(color, taken)
	roster[peer_id]["skin"] = Cosmetics.wrap_skin(skin)


## Host: send everyone into the run.
func request_start() -> void:
	if not is_host() or run_active or roster.is_empty():
		return
	run_map_id = _resolve_lobby_map()
	run_active = true
	for peer in roster:
		if _is_peer_open(peer):
			_start_run.rpc_id(peer, run_map_id)
	run_started.emit()


func _resolve_lobby_map() -> String:
	if not lobby_votes_enabled or lobby_vote_counts.is_empty():
		return Maps.resolve(lobby_map_id)
	var most := 0
	var leaders: Array[String] = []
	for id: String in lobby_vote_counts:
		var count: int = lobby_vote_counts[id]
		if count > most:
			most = count
			leaders.clear()
		if count == most:
			leaders.append(id)
	var winner: String = leaders.pick_random()
	return Maps.resolve(winner)


## The run is over (results screen): late joiners should go to the lobby.
func end_run() -> void:
	var was_active := run_active
	run_active = false
	run_peers.clear()
	if was_active and is_host() and lobby_votes_enabled:
		_map_votes.clear()
		_broadcast_roster()


# ------------------------------------------------------------------ roster
func _on_connected() -> void:
	if mode != Mode.CLIENT:
		return
	var saved := Settings.player_name.strip_edges().left(18)
	if saved != "":
		local_name = saved
	elif local_name == "":
		local_name = "PLAYER %d" % multiplayer.get_unique_id()
	_connect_left = 0.0
	# Keep the hello RPC's argument types stable so older hosts can decline it.
	var hello := JSON.stringify({"name": local_name, "color": Settings.suit_color, "skin": Settings.suit_skin})
	_hello.rpc_id(1, hello, PROTOCOL)
	joined_server.emit()


# ------------------------------------------------------------------ run scene readiness
## Host: peers whose run scene (main.tscn) is loaded. High-rate relays go only
## to these, so a client still loading or leaving the run doesn't get RPCs
## for nodes it doesn't have yet ("Node not found" spam).
var run_peers := {}


## True when `peer_id` is connected and its underlying WebSocket is still OPEN.
func _is_peer_open(peer_id: int) -> bool:
	if not is_online():
		return false
	if peer_id not in multiplayer.get_peers():
		return false
	if multiplayer.multiplayer_peer is WebSocketMultiplayerPeer:
		var ws: WebSocketPeer = multiplayer.multiplayer_peer.get_peer(peer_id)
		return ws != null and ws.get_ready_state() == WebSocketPeer.STATE_OPEN
	return true


func _open_peers(exclude_peer := 0) -> PackedInt32Array:
	var result := PackedInt32Array()
	if not is_online():
		return result
	for peer in multiplayer.get_peers():
		if peer != exclude_peer and _is_peer_open(peer):
			result.append(peer)
	return result


func _broadcast_roster(exclude_peer := 0) -> void:
	lobby_vote_counts.clear()
	for id: String in _map_votes.values():
		lobby_vote_counts[id] = int(lobby_vote_counts.get(id, 0)) + 1
	for peer in roster:
		if peer != exclude_peer and _is_peer_open(peer):
			_push_roster.rpc_id(peer, roster, lobby_map_id, lobby_votes_enabled,
				lobby_vote_counts, str(_map_votes.get(peer, "")))


## Host: send `method` to every connected peer whose WebSocket is still OPEN.
func rpc_to_all(method: Callable, args: Array = []) -> void:
	for peer in _open_peers():
		Callable.create(method, "rpc_id").callv([peer] + args)


## Every peer: call when the run scene is ready (true) or being left (false).
signal run_peer_loaded(peer_id: int)


func report_in_run(value: bool) -> void:
	if not is_online():
		return
	if is_host():
		return
	_report_in_run.rpc_id(1, value)


@rpc("any_peer", "call_remote", "reliable")
func _report_in_run(value: bool) -> void:
	if not is_host():
		return
	var peer := multiplayer.get_remote_sender_id()
	if value:
		if not run_active or not roster.has(peer) or run_peers.has(peer):
			return
		run_peers[peer] = true
		run_peer_loaded.emit(peer)
	else:
		run_peers.erase(peer)


## Host: send `method` to every peer whose run scene is loaded.
func rpc_to_run(method: Callable, args: Array) -> void:
	for peer in run_peers.keys():
		if _is_peer_open(peer):
			Callable.create(method, "rpc_id").callv([peer] + args)


func _on_peer_disconnected(peer_id: int) -> void:
	run_peers.erase(peer_id)
	peer_rtt_ms.erase(peer_id)
	_ping_sent_ms.erase(peer_id)
	if not is_host():
		return
	roster.erase(peer_id)
	_map_votes.erase(peer_id)
	_broadcast_roster(peer_id)
	roster_changed.emit()


## Host: measure smoothed RTT to each connected client for lag compensation.
func _send_rtt_pings() -> void:
	_ping_seq += 1
	var now := Time.get_ticks_msec()
	for peer in _open_peers():
		_ping_sent_ms[peer] = {"seq": _ping_seq, "ms": now}
		_rtt_ping.rpc_id(peer, _ping_seq, float(peer_rtt_ms.get(peer, 0.0)))


@rpc("authority", "call_remote", "unreliable")
func _rtt_ping(seq: int, measured_rtt: float) -> void:
	local_rtt_ms = measured_rtt
	if mode == Mode.CLIENT and is_online():
		_rtt_pong.rpc_id(1, seq)


@rpc("any_peer", "call_remote", "unreliable")
func _rtt_pong(seq: int) -> void:
	if not is_host():
		return
	var peer := multiplayer.get_remote_sender_id()
	var sent: Variant = _ping_sent_ms.get(peer)
	if not sent is Dictionary or int(sent.seq) != seq:
		return
	var sample := clampf(float(Time.get_ticks_msec() - int(sent.ms)), 0.0, 1000.0)
	if peer_rtt_ms.has(peer):
		peer_rtt_ms[peer] = lerpf(float(peer_rtt_ms[peer]), sample, 0.3)
	else:
		peer_rtt_ms[peer] = sample


func get_peer_rtt_ms(peer_id: int) -> float:
	return float(peer_rtt_ms.get(peer_id, 0.0))


## Authoritative rewind window (ms) for a remote client's hitscan shot:
## half RTT plus ~33 ms (half of one 15 Hz enemy-sync interval), capped at 250 ms.
func get_rewind_ms(peer_id: int) -> int:
	if peer_id <= 1:
		return 0
	var rtt := get_peer_rtt_ms(peer_id)
	if rtt <= 0.0:
		return 50
	return clampi(roundi(rtt * 0.5 + 33.0), 0, LagComp.MAX_REWIND_MS)


func _on_connection_failed() -> void:
	if mode == Mode.OFFLINE:
		return
	leave()
	connection_failed.emit()


func _on_server_disconnected() -> void:
	if mode == Mode.OFFLINE:
		return
	leave()
	server_closed.emit()


@rpc("any_peer", "call_remote", "reliable")
func _hello(hello: String, protocol := 0) -> void:
	if not is_host():
		return
	var peer_id := multiplayer.get_remote_sender_id()
	var refusal := ""
	if protocol != PROTOCOL:
		refusal = "THE SERVER RUNS A DIFFERENT BUILD (v%d, YOU HAVE v%d). UPDATE THE GAME." % [PROTOCOL, protocol]
	elif roster.size() >= MAX_PLAYERS:
		refusal = "THE SERVER IS FULL."
	if refusal != "":
		if _is_peer_open(peer_id):
			_reject.rpc_id(peer_id, refusal)
		# Let the reliable message go out before the peer is dropped.
		get_tree().create_timer(0.5).timeout.connect(func():
			if mode == Mode.HOST and peer_id in multiplayer.get_peers():
				multiplayer.multiplayer_peer.disconnect_peer(peer_id))
		return
	var data: Variant = JSON.parse_string(hello)
	if not data is Dictionary:
		return
	var player_name: Variant = data.get("name")
	var color: Variant = data.get("color")
	var skin: Variant = data.get("skin")
	roster[peer_id] = {"name": player_name.left(32) if player_name is String else "PLAYER", "ready": false}
	_assign_cosmetic(peer_id, int(color) if color is float else 0, int(skin) if skin is float else 0)
	_broadcast_roster()
	roster_changed.emit()
	# A run already in progress: send them in, and let GameManager catch up.
	if run_active and _is_peer_open(peer_id):
		_start_run.rpc_id(peer_id, run_map_id)
	peer_joined.emit(peer_id)


## Host -> one client: you can't join, and why. The join screen shows it.
@rpc("authority", "call_remote", "reliable")
func _reject(reason: String) -> void:
	if mode != Mode.CLIENT:
		return
	leave()
	last_error = reason
	connection_failed.emit()


@rpc("authority", "call_remote", "reliable")
func _push_roster(new_roster: Dictionary, map_id: String, voting: bool, counts: Dictionary, my_vote: String) -> void:
	roster = new_roster
	lobby_map_id = map_id
	lobby_votes_enabled = voting
	lobby_vote_counts = counts
	lobby_my_vote = my_vote
	roster_changed.emit()


@rpc("any_peer", "call_remote", "reliable")
func _request_ready(value: bool) -> void:
	if not is_host():
		return
	var peer_id := multiplayer.get_remote_sender_id()
	if roster.has(peer_id):
		roster[peer_id]["ready"] = value
		_broadcast_roster()
		roster_changed.emit()


@rpc("any_peer", "call_remote", "reliable")
func _request_cosmetic(color: int, skin: int) -> void:
	if not is_host() or run_active:
		return
	var peer_id := multiplayer.get_remote_sender_id()
	if roster.has(peer_id):
		_assign_cosmetic(peer_id, color, skin)
		_broadcast_roster()
		roster_changed.emit()


@rpc("any_peer", "call_remote", "reliable")
func _request_name(new_name: String) -> void:
	if not is_host() or run_active:
		return
	var peer_id := multiplayer.get_remote_sender_id()
	var clean := new_name.strip_edges().left(18)
	if clean != "" and roster.has(peer_id):
		roster[peer_id]["name"] = clean
		_broadcast_roster()
		roster_changed.emit()


@rpc("authority", "call_remote", "reliable")
func _start_run(map_id: String) -> void:
	if not Maps.is_available(map_id):
		_reject("THIS BUILD IS MISSING %s. UPDATE THE GAME." % Maps.display_name(map_id))
		return
	run_map_id = map_id
	run_active = true
	run_started.emit()


# ------------------------------------------------------------------ discovery
func start_beacon() -> void:
	stop_beacon()
	if not can_host():
		return
	_beacon = PacketPeerUDP.new()
	if _beacon.bind(DISCOVERY_PORT) != OK:
		_beacon = null
		push_warning("Net: discovery port %d is busy; the host won't be listed" % DISCOVERY_PORT)
		return
	_beacon.set_broadcast_enabled(true)
	# Also listen on a multicast group on every interface: limited broadcast
	# often leaves Windows through only one adapter (VPNs, virtual NICs).
	for iface in _lan_interfaces():
		_beacon.join_multicast_group(DISCOVERY_GROUP, iface)


func stop_beacon() -> void:
	if _beacon:
		_beacon.close()
		_beacon = null


## Host: answer probes so the join screen can find us without an IP.
func _pump_beacon() -> void:
	while _beacon.get_available_packet_count() > 0:
		var packet := _beacon.get_packet()
		var from_ip := _beacon.get_packet_ip()
		var from_port := _beacon.get_packet_port()
		if packet.get_string_from_utf8() != PROBE:
			continue
		var reply := "%s|%s|%d|%d|%d|%s" % [GAME_ID, local_name, roster.size(), MAX_PLAYERS, _host_port, _instance_id]
		_beacon.set_dest_address(from_ip, from_port)
		_beacon.put_packet(reply.to_utf8_buffer())


func start_scanning() -> void:
	stop_scanning()
	if not can_host():
		return
	_scout = PacketPeerUDP.new()
	if _scout.bind(0) != OK:
		_scout = null
		return
	_scout.set_broadcast_enabled(true)
	_scanning = true
	_scan_timer = 0.0


func stop_scanning() -> void:
	_scanning = false
	if _scout:
		_scout.close()
		_scout = null
	servers.clear()
	_seen.clear()


func _send_probe() -> void:
	var data := PROBE.to_utf8_buffer()
	_scout.set_dest_address("255.255.255.255", DISCOVERY_PORT)
	_scout.put_packet(data)
	# Directed broadcast on every LAN interface (assumes a /24, the norm for
	# home and lab networks) plus the multicast group, so hosts behind a
	# different adapter than the default route still answer.
	var sent := {}
	for ip in _lan_addresses():
		var parts: PackedStringArray = ip.split(".")
		var directed := "%s.%s.%s.255" % [parts[0], parts[1], parts[2]]
		if sent.has(directed):
			continue
		sent[directed] = true
		_scout.set_dest_address(directed, DISCOVERY_PORT)
		_scout.put_packet(data)
	_scout.set_dest_address(DISCOVERY_GROUP, DISCOVERY_PORT)
	_scout.put_packet(data)
	# Loopback as well, so two windows on one machine can find each other.
	_scout.set_dest_address("127.0.0.1", DISCOVERY_PORT)
	_scout.put_packet(data)


const DISCOVERY_GROUP := "239.255.77.77"
## Random per-process id in beacon replies, for de-duplicating hosts.
var _instance_id := "%08x" % randi()


## Lower is better: private LAN, then this machine, then VPN/CGNAT ranges.
func _address_rank(ip: String) -> int:
	if ip.begins_with("10.") or ip.begins_with("192.168.") or ip.begins_with("172."):
		return 0
	if ip.begins_with("127."):
		return 1
	return 2


## Private IPv4 addresses of this machine (no loopback or link-local).
func _lan_addresses() -> Array:
	var out := []
	for ip in IP.get_local_addresses():
		if ip.contains(":") or ip.begins_with("127.") or ip.begins_with("169.254."):
			continue
		out.append(ip)
	return out


## Interface names that carry one of those addresses, for multicast joins.
func _lan_interfaces() -> Array:
	var out := []
	for info in IP.get_local_interfaces():
		for ip in info.addresses:
			if not ip.contains(":") and not ip.begins_with("127.") and not ip.begins_with("169.254."):
				out.append(info.name)
				break
	return out


func _pump_scout() -> void:
	var changed := false
	while _scout.get_available_packet_count() > 0:
		var packet := _scout.get_packet()
		var ip := _scout.get_packet_ip()
		var parts := packet.get_string_from_utf8().split("|")
		if parts.size() < 4 or parts[0] != GAME_ID:
			continue
		# One host answers on every path (LAN, loopback, VPN); keep one entry
		# per host instance, on the most useful address.
		var instance := parts[5] if parts.size() > 5 else ip
		var duplicate := ""
		for other_ip in servers:
			if other_ip != ip and str(servers[other_ip].get("instance", "")) == instance:
				duplicate = other_ip
		if duplicate != "":
			if _address_rank(duplicate) <= _address_rank(ip):
				_seen[duplicate] = Time.get_ticks_msec() / 1000.0
				continue
			servers.erase(duplicate)
			_seen.erase(duplicate)
			changed = true
		var existing: Dictionary = servers.get(ip, {})
		var count := int(parts[2])
		if str(existing.get("name", "")) != parts[1] or int(existing.get("players", -1)) != count:
			changed = true
		servers[ip] = {"name": parts[1], "players": count, "max": int(parts[3]),
			"port": int(parts[4]) if parts.size() > 4 else PORT, "instance": instance}
		_seen[ip] = Time.get_ticks_msec() / 1000.0
	if changed:
		servers_changed.emit()


func _expire_servers() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	var stale: Array = []
	for ip in servers:
		if now - float(_seen.get(ip, 0.0)) > SERVER_TIMEOUT:
			stale.append(ip)
	if stale.is_empty():
		return
	for ip in stale:
		servers.erase(ip)
		_seen.erase(ip)
	servers_changed.emit()
