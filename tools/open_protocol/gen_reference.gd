extends SceneTree
## Generates the engine-neutral game data a non-Godot port needs:
##   docs/open-protocol/game-data.json      items, weapons, enemies, mutations, cosmetics, weather
##   docs/open-protocol/level-markers.json  per-map marker node paths, transforms and shapes
##
## Run from the repository root (after `godot --headless --path . --import`):
##   godot --headless --path . --audio-driver Dummy -s tools/open_protocol/gen_reference.gd
##
## Each level is mounted at /root/Main/Level exactly as main.gd does, so every
## node path printed here is the path the dedicated server uses for RPCs such as
## GameManager._request_interact and WeatherManager._sync_puddles.
## Re-run and commit both files whenever items, enemies, maps or Net.PROTOCOL change.

const DATA_PATH := "res://docs/open-protocol/game-data.json"
const MARKERS_PATH := "res://docs/open-protocol/level-markers.json"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var data := {
		"generated_by": "tools/open_protocol/gen_reference.gd",
		"game_protocol": _autoload("Net").PROTOCOL,
		"maps": _maps(),
		"items": _items(),
		"enemy_kinds": _enemy_kinds(),
		"enemy_mutations": _enemy_mutations(),
		"player_mutations": _player_mutations(),
		"cosmetics": _cosmetics(),
		"weather": _weather(),
		"player": _player_constants(),
	}
	_write(DATA_PATH, data)
	var markers := {"generated_by": "tools/open_protocol/gen_reference.gd", "maps": {}}
	for map: Dictionary in load("res://game/maps.gd").ENTRIES:
		if map.get("dev_only", false):
			continue
		markers.maps[map.id] = await _level_markers(map)
	_write(MARKERS_PATH, markers)
	quit(0)


func _autoload(name: String) -> Node:
	return root.get_node(name)


func _write(path: String, value: Variant) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(value, "  ", true) + "\n")
	print("wrote ", ProjectSettings.globalize_path(path))


static func _v(value: Vector3) -> Array:
	return [snappedf(value.x, 0.001), snappedf(value.y, 0.001), snappedf(value.z, 0.001)]


func _maps() -> Array:
	var out := []
	for map: Dictionary in load("res://game/maps.gd").ENTRIES:
		if not map.get("dev_only", false):
			out.append({"id": map.id, "name": map.name, "blurb": map.blurb, "accent": "#" + (map.accent as Color).to_html(false)})
	return out


func _items() -> Array:
	var catalog: GDScript = load("res://weapons/item_catalog.gd")
	var out := []
	var ids: Array = catalog.GUNS.keys() + catalog.STACKS.keys()
	for id: String in ids:
		var def: Resource = catalog.definition(id)
		var w: Resource = def.weapon
		var kind_names := ["gun", "throwable", "consumable", "deployable"]
		var row := {
			"id": id,
			"name": def.display_name,
			"kind": kind_names[int(def.kind)] if int(def.kind) < kind_names.size() else str(def.kind),
			"ammo_type": def.ammo_type,
			"stack_cap": def.stack_cap,
			"spawn_count": def.spawn_count,
			"pouch_cap": catalog.pouch_cap(id),
			"cursed": def.is_cursed(),
			"legendary": def.legendary,
		}
		if w:
			row["weapon"] = {
				"mechanic": w.mechanic, "fire_kind": ["hitscan", "flare", "grenade", "rocket", "place", "use"][int(w.kind)], "damage": w.damage, "pellets": w.pellets,
				"spread_degrees": w.spread_degrees, "burst_spread": w.burst_spread, "max_range": w.max_range,
				"fire_interval": w.fire_interval, "automatic": w.automatic, "mag_size": w.mag_size,
				"reload_time": w.reload_time, "shell_reload": w.shell_reload, "charge_time": w.charge_time,
				"critical_bonus": w.critical_bonus, "knockback": w.knockback, "jam_chance": w.jam_chance,
				"pierce": w.pierce, "projectile_speed": w.projectile_speed, "projectile_gravity": w.projectile_gravity,
				"fuse": w.fuse, "effect_radius": w.effect_radius, "effect_time": w.effect_time,
				"shot_sound": w.shot_sound, "tracer_color": "#" + (w.tracer_color as Color).to_html(false),
				"muzzle": _v(w.muzzle), "ads_fov": w.ads_fov,
			}
		if def.ammo_type != "":
			row["reserve_cap"] = int(catalog.CAPS.get(def.ammo_type, 0))
		out.append(row)
	return out


func _enemy_kinds() -> Array:
	var plan: GDScript = load("res://enemies/wave_plan.gd")
	var scenes := {
		"drip": "res://enemies/drip/drip.tscn", "gutter": "res://enemies/gutter/gutter.tscn",
		"mister": "res://enemies/mister/mister.tscn", "sleet": "res://enemies/sleet/sleet.tscn",
		"hailstone": "res://enemies/hailstone/hailstone.tscn", "undertow": "res://enemies/undertow/undertow.tscn",
		"static": "res://enemies/static/static.tscn", "smog": "res://enemies/smog/smog.tscn",
		"thunderhead": "res://enemies/thunderhead/thunderhead.tscn",
	}
	var out := []
	for name: String in plan.Kind.keys():
		var id := name.to_lower()
		var row := {"kind": plan.Kind[name], "id": id}
		var scene := load(scenes[id]) as PackedScene
		var enemy := scene.instantiate()
		var stats: Resource = enemy.get("data")
		if stats:
			row.merge({"name": stats.display_name, "max_health": stats.max_health, "move_speed": stats.move_speed,
				"damage": stats.damage, "attack_range": stats.attack_range, "attack_cooldown": stats.attack_cooldown})
		enemy.free()
		out.append(row)
	return out


func _enemy_mutations() -> Array:
	var out := []
	var table: Resource = load("res://game/mutation_table.tres")
	for e: Resource in table.entries:
		out.append({"id": e.id, "name": e.display_name, "desc": e.description})
	return out


func _player_mutations() -> Array:
	var out := []
	var gm := _autoload("GameManager")
	for id: String in gm.PLAYER_MUTATIONS:
		var m: Dictionary = gm.PLAYER_MUTATIONS[id]
		out.append({"id": id, "name": m.name, "desc": m.desc, "color": "#" + (m.color as Color).to_html(false)})
	return out


func _cosmetics() -> Dictionary:
	var c: GDScript = load("res://player/cosmetics.gd")
	var colors := []
	for i in c.COLORS.size():
		colors.append({"index": i, "name": c.COLOR_NAMES[i], "hex": "#" + (c.COLORS[i] as Color).to_html(false)})
	var skins := []
	for i in c.SKINS.size():
		skins.append({"index": i, "name": c.SKINS[i]})
	return {"colors": colors, "skins": skins}


func _weather() -> Dictionary:
	var wm := _autoload("WeatherManager")
	return {
		"phases": ["calm", "mutation_roll (legacy, never entered)", "drizzle", "downpour", "clearing"],
		"storm_states": ["clear", "drizzle", "downpour", "acid_storm"],
		"storm_intensity": wm.STORM_INTENSITY, "suit_loss_per_second": wm.SUIT_LOSS_PER_SECOND,
		"enemy_buff": wm.ENEMY_BUFF, "final_wave": wm.FINAL_WAVE,
		"first_calm_duration": wm.first_calm_duration, "calm_duration": wm.calm_duration,
		"drizzle_duration": wm.drizzle_duration, "downpour_min_duration": wm.downpour_min_duration,
		"downpour_max_duration": wm.downpour_max_duration, "clearing_duration": wm.clearing_duration,
		"intensity_ramp_per_second": wm.intensity_ramp,
		"wave_modifiers": load("res://enemies/wave_plan.gd").MODIFIERS,
		"endless_modifiers": load("res://enemies/wave_plan.gd").ENDLESS_MODIFIERS,
		"decon_charges_by_player_count": _autoload("GameManager").DECON_CHARGES,
	}


func _player_constants() -> Dictionary:
	var scene := load("res://player/player.tscn") as PackedScene
	var p := scene.instantiate()
	var out := {}
	for key in ["walk_speed", "sprint_speed", "crouch_speed", "crawl_speed", "turned_speed", "ground_accel",
			"air_accel", "jump_velocity", "coyote_time", "jump_buffer", "stand_height", "crouch_height",
			"downed_height", "crouch_transition_speed", "max_health", "revive_health", "bleed_out_time",
			"turned_health", "melee_damage", "melee_range", "melee_cooldown", "max_pitch_degrees"]:
		out[key] = p.get(key)
	out["gravity"] = ProjectSettings.get_setting("physics/3d/default_gravity")
	out["capsule_radius"] = 0.4
	out["eye_height_below_top"] = 0.15
	out["roof_ray"] = {"from_feet": 1.0, "length": 40.0, "mask": 1}
	p.free()
	return out


func _level_markers(map: Dictionary) -> Dictionary:
	var main := Node3D.new()
	main.name = "Main"
	root.add_child(main)
	var level := (load(map.scene) as PackedScene).instantiate() as Node3D
	level.name = "Level"
	main.add_child(level)
	load("res://props/tree_shelter.gd").install(level)
	await process_frame
	await physics_frame
	var out := {"name": map.name}
	for group in ["player_spawn", "enemy_spawn", "drain_spawn", "crate_spawn", "boss_anchor"]:
		var rows := []
		for node: Node3D in get_nodes_in_group(group):
			rows.append({"name": str(node.name), "path": _rel(node), "pos": _v(node.global_position),
				"yaw": snappedf(node.global_rotation.y, 0.001)})
		out[group] = rows
	var decon := []
	for node: Node3D in get_nodes_in_group("decon_shower"):
		decon.append({"name": str(node.name), "marker_path": _rel(node),
			"interact_path": _rel(node) + "/Interact", "pos": _v(node.global_position),
			"interact_pos": _v(node.global_position + node.global_basis * Vector3(0, 1, 0)),
			"radius": 2.2, "hold_time": 1.0})
	out["decon_showers"] = decon
	var stations := []
	for node: Node3D in get_nodes_in_group("crate_station"):
		stations.append({"key": str(node.name), "server_path": "Main/RunLoot/" + str(node.name),
			"pos": _v(node.global_position), "yaw": snappedf(node.global_rotation.y, 0.001)})
	out["vending_stations"] = stations
	var puddles := []
	for node: Node3D in get_nodes_in_group("puddles"):
		if node.get("max_radius") == null:
			continue
		puddles.append({"name": str(node.name), "path": _rel(node), "sync_key": "/root/" + _rel(node),
			"pos": _v(node.global_position), "max_radius": node.max_radius, "grow_time": node.grow_time,
			"dry_time": node.dry_time})
	out["puddles"] = puddles
	var shelters := []
	for node: Node in get_nodes_in_group("shelter"):
		var area := node as Area3D
		if area == null:
			continue
		for shape_node: CollisionShape3D in area.find_children("*", "CollisionShape3D", true, false):
			var row := {"name": str(area.name), "path": _rel(area), "pos": _v(shape_node.global_position),
				"yaw": snappedf(shape_node.global_rotation.y, 0.001)}
			var shape := shape_node.shape
			if shape is BoxShape3D:
				row.merge({"shape": "box", "size": _v((shape as BoxShape3D).size * shape_node.global_basis.get_scale().abs())})
			elif shape is CylinderShape3D:
				row.merge({"shape": "cylinder", "radius": snappedf((shape as CylinderShape3D).radius, 0.001),
					"height": snappedf((shape as CylinderShape3D).height, 0.001)})
			elif shape is SphereShape3D:
				row.merge({"shape": "sphere", "radius": snappedf((shape as SphereShape3D).radius, 0.001)})
			else:
				row.merge({"shape": shape.get_class() if shape else "none"})
			shelters.append(row)
	out["shelter_areas"] = shelters
	main.queue_free()
	await process_frame
	return out


func _rel(node: Node) -> String:
	return str(node.get_path()).trim_prefix("/root/")
