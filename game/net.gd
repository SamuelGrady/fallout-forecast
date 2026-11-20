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
const PROTOCOL := 3
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

enum Mode { OFFLINE, HOST, CLIENT }

var mode: Mode = Mode.OFFLINE
var local_name := ""
## peer id -> {"name": String, "ready": bool, "color": int, "skin": int}
## color / skin index Cosmetics.COLORS / SKINS; the host keeps colours unique.
var roster := {}
## ip -> {"name": String, "players": int, "max": int, "port": int}
var servers := {}
## True between the lobby's START and the results screen.
var run_active := false
## Headless dedicated server (`-- --server`): hosts with no local player, so
## peer 1 is never in the roster. See game/dedicated_server.gd.
var dedicated := false
## Why the last join failed, for the join screen ("" = no answer).
var last_error := ""

var _connect_left := 0.0
var _host_port := PORT

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
func host(port := PORT, as_player := true) -> Error:
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
	local_name = "HOST" if as_player else "CLOUD SERVER"
	roster.clear()
	if as_player:
		roster[1] = {"name": local_name, "ready": false}
		_assign_cosmetic(1, Settings.suit_color, Settings.suit_skin)
	start_beacon()
	roster_changed.emit()
	return OK


## Join the public cloud server (CLOUD_URL). Same path on desktop and web.
func join_cloud() -> Error:
	return join(CLOUD_URL)


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
	stop_beacon()
	stop_scanning()
	mode = Mode.OFFLINE
	run_active = false
	_connect_left = 0.0
	roster.clear()
	# Mode is already OFFLINE, so the disconnects this triggers are ignored.
	# Back to Godot's default offline peer, not null: with no peer at all,
	# every is_multiplayer_authority() and rpc() in solo play errors.
	if not multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	roster_changed.emit()


func set_ready(value: bool) -> void:
	if is_host():
		if roster.has(1):
			roster[1]["ready"] = value
		_push_roster.rpc(roster)
		roster_changed.emit()
	elif is_online():
		_request_ready.rpc_id(1, value)


## Change our suit colour / skin. The host may hand back a different colour
## if someone already wears that one; the roster says what we really got.
func set_cosmetic(color: int, skin: int) -> void:
	if not is_online() or run_active:
		return
	if is_host():
		if roster.has(1):
			_assign_cosmetic(1, color, skin)
			_push_roster.rpc(roster)
			roster_changed.emit()
	else:
		_request_cosmetic.rpc_id(1, color, skin)


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
	if not is_host():
		return
	run_active = true
	_start_run.rpc()
	run_started.emit()


## The run is over (results screen): late joiners should go to the lobby.
func end_run() -> void:
	run_active = false


# ------------------------------------------------------------------ roster
func _on_connected() -> void:
	if mode != Mode.CLIENT:
		return
	if local_name == "":
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


## Every peer: call when the run scene is ready (true) or being left (false).
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
		run_peers[peer] = true
	else:
		run_peers.erase(peer)


## Host: send `method` to every peer whose run scene is loaded.
func rpc_to_run(method: Callable, args: Array) -> void:
	for peer in run_peers:
		Callable.create(method, "rpc_id").callv([peer] + args)


func _on_peer_disconnected(peer_id: int) -> void:
	run_peers.erase(peer_id)
	if not is_host():
		return
	roster.erase(peer_id)
	_push_roster.rpc(roster)
	roster_changed.emit()


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
		_reject.rpc_id(peer_id, refusal)
		# Let the reliable message go out before the peer is dropped.
		get_tree().create_timer(0.5).timeout.connect(func():
			if mode == Mode.HOST:
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
	_push_roster.rpc(roster)
	roster_changed.emit()
	# A run already in progress: send them in, and let GameManager catch up.
	if run_active:
		_start_run.rpc_id(peer_id)
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
func _push_roster(new_roster: Dictionary) -> void:
	roster = new_roster
	roster_changed.emit()


@rpc("any_peer", "call_remote", "reliable")
func _request_ready(value: bool) -> void:
	if not is_host():
		return
	var peer_id := multiplayer.get_remote_sender_id()
	if roster.has(peer_id):
		roster[peer_id]["ready"] = value
		_push_roster.rpc(roster)
		roster_changed.emit()


@rpc("any_peer", "call_remote", "reliable")
func _request_cosmetic(color: int, skin: int) -> void:
	if not is_host() or run_active:
		return
	var peer_id := multiplayer.get_remote_sender_id()
	if roster.has(peer_id):
		_assign_cosmetic(peer_id, color, skin)
		_push_roster.rpc(roster)
		roster_changed.emit()


@rpc("authority", "call_remote", "reliable")
func _start_run() -> void:
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
