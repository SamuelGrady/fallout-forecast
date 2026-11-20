extends Node3D
## Run entry point.
##
## Load the district before setting up the player or any marker-driven systems.
## In a session every peer builds the same Players/P_<peer id> nodes from
## Net.roster and gives each one to its owner.
##
## Also puts the level's decon showers in play and starts the run on the host.

const DeconShower := preload("res://props/decon_shower.gd")
const PlayerScene := preload("res://player/player.tscn")
const DistrictObjective := preload("res://props/district_objective.gd")

var map_id := ""
var map_scene: PackedScene
var loading_map := true
var _level: Node3D


func _ready() -> void:
	if map_id.is_empty():
		map_id = Net.run_map_id if Net.is_online() else Maps.fallback(Settings.solo_map_id)
	if map_scene == null:
		var path := str(Maps.entry(map_id).get("scene", ""))
		if not path.is_empty():
			map_scene = load(path) as PackedScene
	var level_root := map_scene.instantiate() if map_scene else null
	_level = level_root as Node3D
	if _level == null:
		if level_root:
			level_root.free()
		push_error("Could not instantiate map " + map_id)
		loading_map = false
		if Net.dedicated:
			get_tree().quit(1)
		else:
			_leave_to_title.call_deferred()
		return
	_level.name = "Level"
	add_child(_level)
	GameManager.map_id = map_id
	if map_id == Maps.DEFAULT_ID and not Net.dedicated:
		preload("res://props/building_restyle.gd").apply(_level)
		var signs := Node.new()
		signs.set_script(preload("res://props/map_signs.gd"))
		_level.add_child(signs)
	_setup_decon_showers()
	_setup_objectives()
	_setup_players()

	if OS.has_feature("web"):
		Engine.max_physics_steps_per_frame = 2
	Sound.start_run()
	var pause_menu := CanvasLayer.new()
	pause_menu.set_script(preload("res://ui/pause_menu.gd"))
	add_child(pause_menu)
	# Compile shaders for enemies, guns and FX behind a brief card so the
	# first fight doesn't hitch (most noticeable on web).
	if not Net.dedicated:
		var warm := Node3D.new()
		warm.name = "WarmUp"
		warm.set_script(preload("res://game/warmup.gd"))
		add_child.call_deferred(warm)
	if not Net.dedicated:
		# Screen-level juice: trailing bars, suit breach, downed view, rain
		# drips, wave cards, popup ticker.
		var juice_hud := CanvasLayer.new()
		juice_hud.name = "JuiceHud"
		juice_hud.set_script(preload("res://ui/juice_hud.gd"))
		add_child(juice_hud)
		# Red arcs pointing at whatever just hurt you.
		var hits := CanvasLayer.new()
		hits.name = "HitIndicator"
		hits.set_script(preload("res://ui/hit_indicator.gd"))
		add_child(hits)
		# Follow-cam on a teammate while you're OUT.
		var spectator := Node3D.new()
		spectator.name = "Spectator"
		spectator.set_script(preload("res://ui/spectator.gd"))
		add_child(spectator)
	# Teammate nameplates and off-screen pointers, visible through walls.
	var markers := CanvasLayer.new()
	markers.name = "TeammateMarkers"
	markers.set_script(preload("res://ui/teammate_markers.gd"))
	add_child(markers)
	if OS.is_debug_build():
		var dev_menu := CanvasLayer.new()
		dev_menu.set_script(preload("res://ui/dev_menu.gd"))
		add_child(dev_menu)
	var pings := PingSystem.new()
	pings.name = "Pings"
	add_child(pings)
	if not Net.dedicated:
		var ping_hud := preload("res://ui/ping_hud.gd").new()
		ping_hud.system = pings
		$HUD.add_child(ping_hud)
	Net.roster_changed.connect(_sync_players)
	Net.server_closed.connect(_leave_to_title)
	GameManager.run_finished.connect(_on_run_finished)
	_prepare_navigation.call_deferred()


func _prepare_navigation() -> void:
	# CSG updates its collision on a deferred turn. Parse scene geometry on
	# the main thread and let Godot bake it on a worker where supported.
	await get_tree().physics_frame
	for node in _level.find_children("*", "NavigationRegion3D", true, false):
		var region := node as NavigationRegion3D
		var mesh := region.navigation_mesh
		if mesh and mesh.get_polygon_count() > 0:
			continue
		if mesh == null:
			mesh = NavigationMesh.new()
			mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
			mesh.agent_height = 1.75
		else:
			mesh = mesh.duplicate() as NavigationMesh
		region.navigation_mesh = mesh
		# A region without an authored source group bakes its own subtree by
		# default. Include sibling geometry in the level as well.
		var whole_level := mesh.geometry_source_geometry_mode == NavigationMesh.SOURCE_GEOMETRY_ROOT_NODE_CHILDREN
		var bake_group := "map_bake_%d" % _level.get_instance_id()
		if whole_level:
			_level.add_to_group(bake_group)
			mesh.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_GROUPS_WITH_CHILDREN
			mesh.geometry_source_group_name = bake_group
		region.bake_navigation_mesh(not OS.has_feature("web"))
		if region.is_baking():
			await region.bake_finished
		if whole_level:
			_level.remove_from_group(bake_group)
			mesh.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_ROOT_NODE_CHILDREN
			mesh.geometry_source_group_name = &""
		if region.navigation_mesh.get_polygon_count() == 0:
			push_warning("No walkable navigation geometry for %s in %s" % [region.name, map_id])
	# NavigationServer syncs region changes on a physics tick.
	await get_tree().physics_frame
	await get_tree().process_frame
	if _finishing:
		return
	if OS.has_feature("web") and not Net.dedicated:
		var merged := StaticBatcher.batch(_level)
		Perf.mark("static batch merged %d meshes" % merged)
	loading_map = false
	if GameManager.is_host():
		GameManager.start_run()
	else:
		Net.report_in_run(true)


func _setup_players() -> void:
	if Net.is_online():
		_sync_players()
		return
	var player := PlayerScene.instantiate() as Player
	player.name = "Player"
	_apply_look(player, Settings.suit_color, Settings.suit_skin)
	var spawn := get_tree().get_first_node_in_group("player_spawn") as Node3D
	if spawn:
		player.transform = global_transform.affine_inverse() * spawn.global_transform
	add_child(player)


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
		var info: Dictionary = Net.roster[ids[i]]
		var color := int(info.get("color", peer_id))
		var skin := int(info.get("skin", 0))
		var existing := container.get_node_or_null(node_name) as Player
		if existing:
			existing.display_name = _peer_name(peer_id)
			_apply_look(existing, color, skin)
			continue
		var player := PlayerScene.instantiate() as Player
		player.name = node_name
		# Before add_child, so the body model is built in this look.
		_apply_look(player, color, skin)
		# Authority before add_child: player.gd._ready() checks it to decide
		# whether to take the camera and capture the mouse.
		player.set_multiplayer_authority(peer_id)
		if not spawns.is_empty():
			var spawn := spawns[i % spawns.size()] as Node3D
			player.transform = container.global_transform.affine_inverse() * spawn.global_transform
		container.add_child(player)
		player.display_name = _peer_name(peer_id)
	# Anyone who left.
	for child in container.get_children():
		var peer_id := _peer_of(str(child.name))
		if peer_id < 0 or not Net.roster.has(peer_id):
			child.remove_from_group("players")
			child.remove_from_group("local_player")
			child.queue_free()


## Suit colour and skin onto a player and its body model (rebuilt if changed).
func _apply_look(player: Player, color: int, skin: int) -> void:
	player.suit_color = Cosmetics.color(color)
	player.skin = Cosmetics.wrap_skin(skin)
	var body := player.get_node_or_null("BodyModel")
	if body and body.has_method("set_look"):
		body.set_look(player.suit_color, player.skin)


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


## Same objective paths on every peer. New districts use their drain markers.
func _setup_objectives() -> void:
	var root := Node3D.new()
	root.name = "DistrictObjectives"
	_level.add_child(root)
	if map_id == Maps.DEFAULT_ID:
		for site: String in DistrictObjective.PINECREST_SITES:
			var data: Dictionary = DistrictObjective.PINECREST_SITES[site]
			_add_objective(root, site, data.label, _level.to_global(data.at))
	else:
		var markers := get_tree().get_nodes_in_group("drain_spawn")
		for i in mini(3, markers.size()):
			var marker := markers[i] as Node3D
			_add_objective(root, "drain_%d" % (i + 1), "SEAL DRAIN %d" % (i + 1), marker.global_position)


func _add_objective(root: Node3D, site: String, label: String, at: Vector3) -> void:
	var objective := DistrictObjective.new()
	objective.name = site
	objective.site = site
	objective.site_label = label
	root.add_child(objective)
	# Lift the use point off the ground so the interact ray reaches it.
	objective.global_position = at + Vector3.UP


var _finishing := false


func _exit_tree() -> void:
	Sound.stop_run()
	Net.report_in_run(false)


func _on_run_finished(_won: bool, _results: Dictionary) -> void:
	# The dedicated server has no results screen; game/dedicated_server.gd
	# unloads the run itself.
	if Net.dedicated or _finishing:
		return
	_finishing = true
	_play_ending(_won)
	get_tree().create_timer(4.5, true).timeout.connect(func():
		if not is_inside_tree():
			return
		var tree := get_tree()
		MenuState.reset()
		_end()
		tree.change_scene_to_file.call_deferred("res://ui/results.tscn"))


## Local, cosmetic ending beat while the run winds down (every peer):
## victory = sparks bursting over the street; defeat = the tape loses signal.
func _play_ending(won: bool) -> void:
	var me := get_tree().get_first_node_in_group("local_player") as Node3D
	if won:
		Sound.play("reel_land", -4.0, 1.4)
		if me:
			for i in 9:
				get_tree().create_timer(0.35 * i).timeout.connect(func():
					if not is_inside_tree():
						return
					var at := me.global_position + Vector3(randf_range(-14, 14), randf_range(12, 20), randf_range(-14, 14))
					var color: Color = [Color("#ff5689"), Color("#66dfda"), Color("#ffd56a")][i % 3]
					ShotFX.sparks(self, at, Vector3.UP, 12)
					ShotFX.puff(self, at, Color(color, 0.85), 0.9, 0.6)
					Sound.play_at("explosion", at, -18.0, 1.6))
		return
	# Defeat: tracking collapses, then a card.
	Sound.play("vhs_glitch", -6.0)
	var layer := CanvasLayer.new()
	layer.layer = 60
	add_child(layer)
	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.02, 0.05, 0.0)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(shade)
	var label := Label.new()
	label.text = "SIGNAL LOST
TRACKING..."
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 54)
	label.add_theme_color_override("font_color", BroadcastUI.PINK)
	label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	label.offset_left = -300
	label.offset_right = 300
	label.offset_top = -60
	label.modulate.a = 0.0
	layer.add_child(label)
	var tween := create_tween()
	tween.tween_interval(1.2)
	tween.tween_property(shade, "color:a", 0.85, 1.4)
	tween.parallel().tween_property(label, "modulate:a", 1.0, 0.6)


## The host left (or dropped us): there is no run to be in any more.
func _leave_to_title() -> void:
	if _finishing or not is_inside_tree():
		return
	_finishing = true
	MenuState.reset()
	_end()
	Net.leave()
	get_tree().change_scene_to_file.call_deferred("res://ui/title.tscn")


## Run bookkeeping, but leave the session up: after a finished run everyone
## goes back to the lobby to play again.
func _end() -> void:
	Net.end_run()
	GameManager.run_active = false
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
