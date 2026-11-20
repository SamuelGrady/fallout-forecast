extends Node
## Autoload "Net": the session, the lobby roster and LAN discovery.
##
## One place answers "am I the host?". Every script used to carry its own copy
## of that check; now they all ask Net. Offline counts as host, exactly as
## before, so solo play runs the same code path as a hosted game.
##
## Topology is ENet client/server. Clients can only talk to the host, never to
## each other, so every client-to-client message goes client -> host -> clients:
## see the "_push_* / _apply_*" pairs on Player and MutationRoll.
##
## Discovery: the host answers UDP probes on DISCOVERY_PORT; the join screen
## broadcasts a probe to 255.255.255.255 (and 127.0.0.1, so a second window on
## the same machine shows up) and lists whatever answers.

signal roster_changed
signal servers_changed
signal peer_joined(peer_id: int)
signal run_started
signal connection_failed
signal server_closed
signal joined_server

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
## peer id -> {"name": String, "ready": bool}
var roster := {}
## ip -> {"name": String, "players": int, "max": int}
var servers := {}
## True between the lobby's START and the results screen.
var run_active := false

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


func _process(delta: float) -> void:
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


func local_id() -> int:
	return multiplayer.get_unique_id()


func peer_count() -> int:
	return maxi(roster.size(), 1)


## Open a session. Returns OK, or an ENet error the lobby can show.
func host(port := PORT) -> Error:
	leave()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_PLAYERS)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	mode = Mode.HOST
	local_name = "HOST"
	roster.clear()
	roster[1] = {"name": local_name, "ready": false}
	start_beacon()
	roster_changed.emit()
	return OK


## Join a session. connection_failed / joined_server arrive later, by signal.
func join(address: String, port := PORT) -> Error:
	leave()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address.strip_edges(), port)
	if err != OK:
		return err
	# Set the mode before the peer, so the handshake's callbacks see CLIENT.
	mode = Mode.CLIENT
	roster.clear()
	multiplayer.multiplayer_peer = peer
	return OK


## Drop the session. Safe to call when there isn't one.
func leave() -> void:
	stop_beacon()
	stop_scanning()
	mode = Mode.OFFLINE
	run_active = false
	roster.clear()
	# Mode is already OFFLINE, so the disconnects this triggers are ignored.
	if multiplayer.has_multiplayer_peer():
		multiplayer.multiplayer_peer = null
	roster_changed.emit()


func set_ready(value: bool) -> void:
	if is_host():
		if roster.has(1):
			roster[1]["ready"] = value
		_push_roster.rpc(roster)
		roster_changed.emit()
	elif is_online():
		_request_ready.rpc_id(1, value)


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
	_hello.rpc_id(1, local_name)
	joined_server.emit()


func _on_peer_disconnected(peer_id: int) -> void:
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
func _hello(name: String) -> void:
	if not is_host():
		return
	var peer_id := multiplayer.get_remote_sender_id()
	roster[peer_id] = {"name": name, "ready": false}
	_push_roster.rpc(roster)
	roster_changed.emit()
	# A run already in progress: send them in, and let GameManager catch up.
	if run_active:
		_start_run.rpc_id(peer_id)
	peer_joined.emit(peer_id)


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


@rpc("authority", "call_remote", "reliable")
func _start_run() -> void:
	run_started.emit()


# ------------------------------------------------------------------ discovery
func start_beacon() -> void:
	stop_beacon()
	_beacon = PacketPeerUDP.new()
	if _beacon.bind(DISCOVERY_PORT) != OK:
		_beacon = null
		push_warning("Net: discovery port %d is busy; the host won't be listed" % DISCOVERY_PORT)
		return
	_beacon.set_broadcast_enabled(true)


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
		var reply := "%s|%s|%d|%d" % [GAME_ID, local_name, roster.size(), MAX_PLAYERS]
		_beacon.set_dest_address(from_ip, from_port)
		_beacon.put_packet(reply.to_utf8_buffer())


func start_scanning() -> void:
	stop_scanning()
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
	# Loopback as well, so two windows on one machine can find each other.
	_scout.set_dest_address("127.0.0.1", DISCOVERY_PORT)
	_scout.put_packet(data)


func _pump_scout() -> void:
	var changed := false
	while _scout.get_available_packet_count() > 0:
		var packet := _scout.get_packet()
		var ip := _scout.get_packet_ip()
		var parts := packet.get_string_from_utf8().split("|")
		if parts.size() < 4 or parts[0] != GAME_ID:
			continue
		var existing: Dictionary = servers.get(ip, {})
		var count := int(parts[2])
		if str(existing.get("name", "")) != parts[1] or int(existing.get("players", -1)) != count:
			changed = true
		servers[ip] = {"name": parts[1], "players": count, "max": int(parts[3])}
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
