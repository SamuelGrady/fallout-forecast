extends Node
## Headless dedicated server. Net adds this as its child when the game is
## launched with `-- --server` (see server/README.md):
##
##   godot --headless --path . --audio-driver Dummy -- --server [--port=7777] [--heartbeat=/tmp/fallout-heartbeat]
##
## The server is peer 1 but not a player: Net.host(port, false) leaves it out
## of the roster, so players(), player_count() and the lose check only see the
## clients. Between runs there is no current scene at all; clients sit in their
## own lobby screens. The run starts when every connected player is READY, and
## after the results (or when everyone leaves) the server unloads the run and
## waits again.

const RUN_SCENE := "res://main.tscn"
## After run_finished: main.gd shows clients the results 4.5 s later.
const RESULTS_DELAY := 5.0
const HEARTBEAT_EVERY := 15.0
const STATUS_EVERY := 300.0

var _port := 7777
var _heartbeat_path := ""
var _heartbeat_left := 0.0
var _status_left := STATUS_EVERY
var _in_run := false
var _run_serial := 0


func _ready() -> void:
	_port = Net.PORT
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--port="):
			_port = int(arg.get_slice("=", 1))
		elif arg.begins_with("--heartbeat="):
			_heartbeat_path = arg.get_slice("=", 1)
	# Keep simulating with no window focus and no frame-rate cap from vsync.
	Engine.max_fps = 60
	_start.call_deferred()


func _start() -> void:
	var err := Net.host(_port, false)
	if err != OK:
		_log("ERROR could not open WebSocket port %d (error %d)" % [_port, err])
		get_tree().quit(1)
		return
	# The title screen is the project's main scene; the server never shows it.
	if get_tree().current_scene:
		get_tree().unload_current_scene()
	multiplayer.peer_connected.connect(func(id): _log("peer %d connected" % id))
	multiplayer.peer_disconnected.connect(_on_peer_left)
	Net.peer_joined.connect(_on_peer_joined)
	Net.roster_changed.connect(_on_roster_changed)
	GameManager.run_finished.connect(_on_run_finished)
	_log("listening for WebSocket (ws://) on TCP %d (protocol v%d, max %d players)" % [_port, Net.PROTOCOL, Net.MAX_PLAYERS])
	_beat()


func _process(delta: float) -> void:
	_heartbeat_left -= delta
	if _heartbeat_left <= 0.0:
		_beat()
	_status_left -= delta
	if _status_left <= 0.0:
		_status_left = STATUS_EVERY
		_log("status: %d player(s), %s" % [Net.roster.size(), _state_text()])


func _on_peer_joined(peer_id: int) -> void:
	_log("player joined: %d \"%s\" (%d/%d)%s" % [peer_id, _name(peer_id), Net.roster.size(),
		Net.MAX_PLAYERS, ", sent into the run in progress" if _in_run else ""])


func _on_peer_left(peer_id: int) -> void:
	_log("peer %d disconnected (%d player(s) left)" % [peer_id, Net.roster.size()])


func _on_roster_changed() -> void:
	if _in_run:
		if Net.roster.is_empty():
			_log("everyone left: abandoning the run")
			_reset()
		return
	if Net.roster.is_empty():
		return
	for info in Net.roster.values():
		if not bool(info.get("ready", false)):
			return
	_start_run.call_deferred()


func _start_run() -> void:
	if _in_run or Net.roster.is_empty():
		return
	_in_run = true
	_run_serial += 1
	# Everyone is un-READY afterwards, so the next run waits for the lobby.
	for peer_id in Net.roster:
		Net.roster[peer_id]["ready"] = false
	Net._push_roster.rpc(Net.roster)
	_log("run %d starting with %d player(s): %s" % [_run_serial, Net.roster.size(), ", ".join(_names())])
	Net.request_start()
	get_tree().change_scene_to_file(RUN_SCENE)


func _on_run_finished(won: bool, results: Dictionary) -> void:
	if not _in_run:
		return
	# Nobody joins a finished run; they wait in the lobby for the next one.
	Net.end_run()
	_log("run %d finished: %s, %d wave(s)" % [_run_serial, "WON" if won else "LOST", int(results.get("waves", 0))])
	var serial := _run_serial
	get_tree().create_timer(RESULTS_DELAY).timeout.connect(func():
		if _in_run and serial == _run_serial:
			_reset())


## Back to idle: no scene, no weather, no run state. Same cleanup as main._end.
func _reset() -> void:
	_in_run = false
	Net.end_run()
	GameManager.run_active = false
	GameManager.finished = true
	GameManager.mutations.reset_run()
	WeatherManager.stop()
	if get_tree().current_scene:
		get_tree().unload_current_scene()
	_log("idle: waiting for players to ready up (%d connected)" % Net.roster.size())
	# Anyone who readied up during the results screen.
	_on_roster_changed.call_deferred()


## Liveness for Docker: the file's mtime proves the main loop is turning.
func _beat() -> void:
	_heartbeat_left = HEARTBEAT_EVERY
	if _heartbeat_path == "":
		return
	var f := FileAccess.open(_heartbeat_path, FileAccess.WRITE)
	if f:
		f.store_line("%d %d %s" % [Time.get_unix_time_from_system(), Net.roster.size(), _state_text()])


func _state_text() -> String:
	return "in run %d" % _run_serial if _in_run else "idle"


func _name(peer_id: int) -> String:
	return str(Net.roster.get(peer_id, {}).get("name", "?"))


func _names() -> Array:
	var out := []
	for peer_id in Net.roster:
		out.append(_name(peer_id))
	return out


func _log(text: String) -> void:
	print("[%s] [server] %s" % [Time.get_datetime_string_from_system(true), text])
