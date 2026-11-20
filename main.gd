extends Node3D
## Run entry point.
##
## Solo (and when main.tscn is run straight from the editor) the Player baked
## into the scene is the player. In a session the roster owns the players
## instead: every peer builds the same set of nodes from Net.roster, names them
## P_<peer id> so the paths match for RPCs, and hands each one its owner's
## authority. The baked-in Player is dropped in that case.
##
## Also puts the level's decon showers in play and starts the run on the host.

const DeconShower := preload("res://props/decon_shower.gd")
const PlayerScene := preload("res://player/player.tscn")


func _ready() -> void:
	Sound.start_run()
	# Tell the host this client can now take per-frame player relays.
	Net.report_in_run.call_deferred(true)
	var pause_menu := CanvasLayer.new()
	pause_menu.set_script(preload("res://ui/pause_menu.gd"))
	add_child(pause_menu)
	if OS.is_debug_build():
		var dev_menu := CanvasLayer.new()
		dev_menu.set_script(preload("res://ui/dev_menu.gd"))
		add_child(dev_menu)
	_setup_decon_showers()
	_setup_objectives()
	preload("res://props/building_restyle.gd").apply($Level)
	var signs := Node.new()
	signs.set_script(preload("res://props/map_signs.gd"))
	$Level.add_child(signs)
	_setup_players()
	Net.roster_changed.connect(_sync_players)
	Net.server_closed.connect(_leave_to_title)
	if GameManager.is_host():
		GameManager.start_run.call_deferred()
	GameManager.run_finished.connect(_on_run_finished)


## Solo: place the scene's Player. Session: replace it with the roster's set.
func _setup_players() -> void:
	if not Net.is_online():
		var spawns := get_tree().get_nodes_in_group("player_spawn")
		if has_node("Player") and not spawns.is_empty():
			$Player.global_transform = (spawns[0] as Node3D).global_transform
		return
	_sync_players()
	if has_node("Player"):
		var baked := $Player as Player
		# Groups outlive queue_free for a frame, so drop it from both by hand.
		baked.remove_from_group("players")
		baked.remove_from_group("local_player")
		baked.queue_free()


## Every peer runs this on join and on every roster change, building the same
## nodes at the same paths. Adding is index-by-sorted-roster, so a newcomer
## never moves an existing player.
func _sync_players() -> void:
	if not Net.is_online() or not is_inside_tree():
		return
	var container := _players_container()
	var spawns := get_tree().get_nodes_in_group("player_spawn")
	var ids := Net.roster.keys()
	ids.sort()
	for i in ids.size():
		var peer_id := int(ids[i])
		var node_name := "P_%d" % peer_id
		if container.has_node(node_name):
			container.get_node(node_name).set("display_name", _peer_name(peer_id))
			continue
		var player := PlayerScene.instantiate() as Player
		player.name = node_name
		# Authority before add_child: player.gd._ready() checks it to decide
		# whether to take the camera and capture the mouse.
		player.set_multiplayer_authority(peer_id)
		container.add_child(player)
		player.display_name = _peer_name(peer_id)
		if not spawns.is_empty():
			player.global_position = (spawns[i % spawns.size()] as Node3D).global_position
	# Anyone who left.
	for child in container.get_children():
		var peer_id := _peer_of(str(child.name))
		if peer_id < 0 or not Net.roster.has(peer_id):
			child.remove_from_group("players")
			child.remove_from_group("local_player")
			child.queue_free()


func _players_container() -> Node3D:
	var container := get_node_or_null("Players") as Node3D
	if container == null:
		container = Node3D.new()
		container.name = "Players"
		add_child(container)
	return container


func _peer_name(peer_id: int) -> String:
	var info: Dictionary = Net.roster.get(peer_id, {})
	return str(info.get("name", "PLAYER %d" % peer_id))


## "P_7" -> 7, or -1 if the node isn't a roster player.
func _peer_of(node_name: String) -> int:
	if not node_name.begins_with("P_"):
		return -1
	return int(node_name.substr(2))


## Same three district objectives on every peer; the host picks the live one.
func _setup_objectives() -> void:
	var root := Node3D.new()
	root.name = "DistrictObjectives"
	$Level.add_child(root)
	for site in preload("res://props/district_objective.gd").SITES:
		var objective := Node3D.new()
		objective.set_script(preload("res://props/district_objective.gd"))
		objective.name = site
		objective.site = site
		root.add_child(objective)
		# Lift the use point off the ground so the interact ray reaches it.
		objective.global_position = objective.SITES[site].at + Vector3.UP


func _exit_tree() -> void:
	Sound.stop_run()
	Net.report_in_run(false)


func _on_run_finished(_won: bool, _results: Dictionary) -> void:
	# The dedicated server has no results screen; game/dedicated_server.gd
	# unloads the run itself.
	if Net.dedicated:
		return
	get_tree().create_timer(4.5).timeout.connect(func():
		_end()
		get_tree().change_scene_to_file("res://ui/results.tscn"))


## The host left (or dropped us): there is no run to be in any more.
func _leave_to_title() -> void:
	_end()
	Net.leave()
	get_tree().change_scene_to_file("res://ui/title.tscn")


## Run bookkeeping, but leave the session up: after a finished run everyone
## goes back to the lobby to play again.
func _end() -> void:
	Net.end_run()
	GameManager.mutations.clear()
	WeatherManager.stop()


## Each decon_shower marker gets an "Interact" child (same path on every peer).
func _setup_decon_showers() -> void:
	for marker in get_tree().get_nodes_in_group("decon_shower"):
		if marker.has_node("Interact"):
			continue
		var it := DeconShower.new()
		it.name = "Interact"
		marker.add_child(it)
		it.position = Vector3(0, 1.0, 0)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F11:
		var fullscreen := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if fullscreen else DisplayServer.WINDOW_MODE_FULLSCREEN)
