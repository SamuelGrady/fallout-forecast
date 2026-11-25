extends SceneTree
## Generates docs/open-protocol/open-protocol-schema.json by scanning every GDScript file in
## the repository for @rpc methods and inspecting each script's runtime RPC
## config, argument names/types/defaults, node path pattern, and direction.
##
## Run from the repository root:
##   godot --headless --path . --audio-driver Dummy -s tools/open_protocol/gen_schema.gd
##
## Re-run and commit docs/open-protocol/open-protocol-schema.json on every Net.PROTOCOL bump.

const OUTPUT_PATH := "res://docs/open-protocol/open-protocol-schema.json"

const NODE_METADATA := {
	"res://game/net.gd": {
		"node": "Net",
		"authority": "host",
		"phase": "always",
		"notes": "Autoload. Session handshake, lobby roster, map voting, chat, run start/readiness, RTT pings.",
	},
	"res://game/game_manager.gd": {
		"node": "GameManager",
		"authority": "host",
		"phase": "run",
		"notes": "Autoload. Global pause, Calm/Clearing ready-up, world interacts, decon pool, boss spawn, endless tape choice, results, shared VFX/hazards.",
	},
	"res://game/mutation_roll.gd": {
		"node": "GameManager/MutationRoll",
		"authority": "host",
		"phase": "run",
		"notes": "Child of GameManager. Wave 2+ Calm mutation draft deal, vote tally, resolution, and late-join sync.",
	},
	"res://game/crate_manager.gd": {
		"node": "GameManager/CrateManager",
		"authority": "host",
		"phase": "run",
		"notes": "Child of GameManager. Vending cabinet stock/reveals, between-wave airdrops, and hold-to-buy/open requests.",
	},
	"res://game/feat_tracker.gd": {
		"node": "GameManager/Feats",
		"authority": "host",
		"phase": "run",
		"notes": "Child of GameManager. Per-player achievement progress awards.",
	},
	"res://weather/weather_manager.gd": {
		"node": "WeatherManager",
		"authority": "host",
		"phase": "run",
		"notes": "Autoload. Storm phase/wave transitions, intensity overrides, lightning strikes, and puddle growth.",
	},
	"res://game/ping_system.gd": {
		"node": "Main/Pings",
		"authority": "host",
		"phase": "run",
		"notes": "Created by main.gd. Contextual/wheel squad pings (client request -> host validated relay).",
	},
	"res://weapons/run_loot.gd": {
		"node": "Main/RunLoot",
		"authority": "host",
		"phase": "run",
		"notes": "Created by main.gd. Starter kit selection, world pickups, projectiles/deployables, weapon unlocks.",
	},
	"res://enemies/enemy_spawner.gd": {
		"node": "Main/Enemies",
		"authority": "host",
		"phase": "run",
		"notes": "Child of Main. Enemy spawn/despawn/retire, 20 Hz batched position/yaw stream, wave progress, impact/tell/molt cues.",
	},
	"res://enemies/boss/boss_cumulus.gd": {
		"node": "Main/Enemies/BossCumulus",
		"authority": "host",
		"phase": "run",
		"notes": "Spawned on Wave 5 Downpour under Main/Enemies. Boss position, part HP, sac count, burn timer, death.",
	},
	"res://player/player.gd": {
		"node": "Main/Players/P_<peer_id>",
		"authority": "owner",
		"phase": "run",
		"notes": "One node per peer in Net.roster, authority = owning peer_id. All RPCs use any_peer + explicit sender validation.",
	},
	"res://weapons/weapon_holder.gd": {
		"node": "Main/Players/P_<peer_id>/Head/Camera3D/WeaponHolder",
		"authority": "owner",
		"phase": "run",
		"notes": "Child of each player's camera. Authoritative 5-slot inventory, belt pouches, shot/throw/reload/swap/drop requests and FX relays.",
	},
	"res://props/decon_shower.gd": {
		"node": "Main/Level/DeconShowers/<decon_marker>/Interact",
		"authority": "host",
		"phase": "run",
		"notes": "Attached under each node in group 'decon_shower' by main.gd (exact paths per map in docs/open-protocol/level-markers.json). Spray VFX broadcast when a player repairs their suit.",
	},
}

const RELAYED_METHODS := {
	"res://game/net.gd:_chat_rpc": true,
	"res://game/game_manager.gd:_sync_pause": true,
	"res://game/ping_system.gd:_show_ping": true,
	"res://player/player.gd:_relay_transform": true,
	"res://player/player.gd:_apply_tarp": true,
	"res://weapons/weapon_holder.gd:_shot_fx": true,
	"res://weapons/weapon_holder.gd:_throw_fx": true,
	"res://weapons/weapon_holder.gd:_equip_state": true,
}

const OWNER_ONLY_HOST_TO_CLIENT := {
	"res://game/net.gd:_reject": true,
	"res://game/net.gd:_confirm_run_ready": true,
	"res://game/net.gd:_rtt_ping": true,
	"res://game/feat_tracker.gd:_feat_event": true,
	"res://player/player.gd:_receive_hurt_from": true,
	"res://player/player.gd:_receive_enemy_pull": true,
	"res://player/player.gd:_teleport": true,
	"res://player/player.gd:_grant_tarp": true,
	"res://player/player.gd:_receive_hits": true,
	"res://weapons/run_loot.gd:_starter_accepted": true,
	"res://weapons/run_loot.gd:_snapshot": true,
	"res://weapons/weapon_holder.gd:_pouch_full_feedback": true,
	"res://weapons/weapon_holder.gd:_play_charge": true,
	"res://weapons/weapon_holder.gd:_jam": true,
	"res://weapons/weapon_holder.gd:_scrap_feedback": true,
	"res://weapons/weapon_holder.gd:_private_state": true,
}

const TYPE_NAMES := {
	TYPE_NIL: "Variant",
	TYPE_BOOL: "bool",
	TYPE_INT: "int",
	TYPE_FLOAT: "float",
	TYPE_STRING: "String",
	TYPE_VECTOR2: "Vector2",
	TYPE_VECTOR2I: "Vector2i",
	TYPE_RECT2: "Rect2",
	TYPE_RECT2I: "Rect2i",
	TYPE_VECTOR3: "Vector3",
	TYPE_VECTOR3I: "Vector3i",
	TYPE_TRANSFORM2D: "Transform2D",
	TYPE_VECTOR4: "Vector4",
	TYPE_VECTOR4I: "Vector4i",
	TYPE_PLANE: "Plane",
	TYPE_QUATERNION: "Quaternion",
	TYPE_AABB: "AABB",
	TYPE_BASIS: "Basis",
	TYPE_TRANSFORM3D: "Transform3D",
	TYPE_PROJECTION: "Projection",
	TYPE_COLOR: "Color",
	TYPE_STRING_NAME: "StringName",
	TYPE_NODE_PATH: "NodePath",
	TYPE_RID: "RID",
	TYPE_OBJECT: "Object",
	TYPE_CALLABLE: "Callable",
	TYPE_SIGNAL: "Signal",
	TYPE_DICTIONARY: "Dictionary",
	TYPE_ARRAY: "Array",
	TYPE_PACKED_BYTE_ARRAY: "PackedByteArray",
	TYPE_PACKED_INT32_ARRAY: "PackedInt32Array",
	TYPE_PACKED_INT64_ARRAY: "PackedInt64Array",
	TYPE_PACKED_FLOAT32_ARRAY: "PackedFloat32Array",
	TYPE_PACKED_FLOAT64_ARRAY: "PackedFloat64Array",
	TYPE_PACKED_STRING_ARRAY: "PackedStringArray",
	TYPE_PACKED_VECTOR2_ARRAY: "PackedVector2Array",
	TYPE_PACKED_VECTOR3_ARRAY: "PackedVector3Array",
	TYPE_PACKED_COLOR_ARRAY: "PackedColorArray",
	TYPE_PACKED_VECTOR4_ARRAY: "PackedVector4Array",
}

const RPC_MODE_NAMES := {
	MultiplayerAPI.RPC_MODE_DISABLED: "disabled",
	MultiplayerAPI.RPC_MODE_ANY_PEER: "any_peer",
	MultiplayerAPI.RPC_MODE_AUTHORITY: "authority",
}

const TRANSFER_MODE_NAMES := {
	MultiplayerPeer.TRANSFER_MODE_UNRELIABLE: "unreliable",
	MultiplayerPeer.TRANSFER_MODE_UNRELIABLE_ORDERED: "unreliable_ordered",
	MultiplayerPeer.TRANSFER_MODE_RELIABLE: "reliable",
}


func _initialize() -> void:
	var net := root.get_node("Net")
	var variant_json: Variant = load("res://game/open_protocol/variant_json.gd")
	var files := _collect_gd_files("res://")
	files.sort()

	var nodes_out: Array = []
	var rpcs_out: Array = []

	for path: String in files:
		if path.begins_with("res://tools/") or path.begins_with("res://game/open_protocol/"):
			continue
		var source := FileAccess.get_file_as_string(path)
		if not source.contains("@rpc"):
			continue
		var script := load(path) as Script
		if script == null:
			push_error("gen_schema: failed to load %s" % path)
			quit(1)
			return
		var cfg: Variant = script.get_rpc_config()
		if not cfg is Dictionary or (cfg as Dictionary).is_empty():
			continue
		var cfg_dict: Dictionary = cfg
		var names: Array[String] = []
		for k: Variant in cfg_dict.keys():
			names.append(String(k))
		names.sort()

		var methods_by_name := {}
		for m: Dictionary in script.get_script_method_list():
			methods_by_name[str(m.get("name", ""))] = m

		var meta: Dictionary = NODE_METADATA.get(path, {
			"node": "<unknown:%s>" % path,
			"authority": "host",
			"phase": "run",
			"notes": "",
		})
		var md5_concat := ""
		for n: String in names:
			md5_concat += n
		nodes_out.append({
			"node": meta.node,
			"script": path,
			"authority": meta.authority,
			"phase": meta.phase,
			"rpc_count": names.size(),
			"rpc_md5": md5_concat.md5_text(),
			"notes": meta.notes,
		})

		for idx in names.size():
			var method_name: String = names[idx]
			var entry: Dictionary = cfg_dict.get(StringName(method_name), cfg_dict.get(method_name, {}))
			var rpc_mode_id := int(entry.get("rpc_mode", MultiplayerAPI.RPC_MODE_AUTHORITY))
			var transfer_mode_id := int(entry.get("transfer_mode", MultiplayerPeer.TRANSFER_MODE_RELIABLE))
			var call_local := bool(entry.get("call_local", false))
			var channel := int(entry.get("channel", 0))

			var m_info: Dictionary = methods_by_name.get(method_name, {})
			var raw_args: Array = m_info.get("args", [])
			var default_args: Array = m_info.get("default_args", [])
			var first_default := raw_args.size() - default_args.size()
			var args_out: Array = []
			for i in raw_args.size():
				var a: Dictionary = raw_args[i]
				var t_id := int(a.get("type", TYPE_NIL))
				var arg_row := {
					"name": str(a.get("name", "arg%d" % i)),
					"type": TYPE_NAMES.get(t_id, "Variant"),
					"type_id": t_id,
					"optional": i >= first_default,
				}
				if i >= first_default:
					arg_row["default"] = variant_json.to_json(default_args[i - first_default])
				args_out.append(arg_row)

			var direction := _infer_direction(path, method_name, rpc_mode_id, source)
			var scope := _infer_scope(path, method_name, direction, source)
			rpcs_out.append({
				"node": meta.node,
				"script": path,
				"method": method_name,
				"rpc_id": idx,
				"direction": direction,
				"scope": scope,
				"rpc_mode": RPC_MODE_NAMES.get(rpc_mode_id, "authority"),
				"sync": "call_local" if call_local else "call_remote",
				"transfer_mode": TRANSFER_MODE_NAMES.get(transfer_mode_id, "reliable"),
				"reliable": transfer_mode_id == MultiplayerPeer.TRANSFER_MODE_RELIABLE,
				"channel": channel,
				"args": args_out,
			})

	var schema := {
		"schema_version": 1,
		"open_protocol_version": 1,
		"game_protocol": int(net.get("PROTOCOL")),
		"generated_by": "tools/open_protocol/gen_schema.gd",
		"node_count": nodes_out.size(),
		"rpc_count": rpcs_out.size(),
		"nodes": nodes_out,
		"rpcs": rpcs_out,
	}

	var f := FileAccess.open(OUTPUT_PATH, FileAccess.WRITE)
	if f == null:
		push_error("gen_schema: could not open %s for writing" % OUTPUT_PATH)
		quit(1)
		return
	f.store_string(JSON.stringify(schema, "  ", false) + "\n")
	f.close()
	print("gen_schema: wrote %d RPCs across %d scripts (Net.PROTOCOL=%d) to %s" % [
		rpcs_out.size(), nodes_out.size(), int(net.get("PROTOCOL")), OUTPUT_PATH])
	quit(0)


func _collect_gd_files(dir_path: String) -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if not entry.begins_with("."):
			var full := dir_path.path_join(entry) if dir_path != "res://" else "res://" + entry
			if dir.current_is_dir():
				if entry not in ["addons", ".godot"]:
					out.append_array(_collect_gd_files(full))
			elif entry.ends_with(".gd"):
				out.append(full)
		entry = dir.get_next()
	dir.list_dir_end()
	return out


func _extract_func_body(source: String, method_name: String) -> String:
	var needle := "func %s(" % method_name
	var start := source.find(needle)
	if start < 0:
		return ""
	var next_func := source.find("\nfunc ", start + needle.length())
	var next_rpc := source.find("\n@rpc", start + needle.length())
	var stop := source.length()
	if next_func >= 0:
		stop = mini(stop, next_func)
	if next_rpc >= 0:
		stop = mini(stop, next_rpc)
	return source.substr(start, stop - start)


func _infer_direction(path: String, method_name: String, rpc_mode_id: int, source: String) -> String:
	var key := "%s:%s" % [path, method_name]
	if RELAYED_METHODS.has(key):
		return "relayed"
	if rpc_mode_id == MultiplayerAPI.RPC_MODE_AUTHORITY:
		return "host->client"
	var body := _extract_func_body(source, method_name)
	if body.contains("get_remote_sender_id() == 1") \
			or body.contains("get_remote_sender_id() != 1") \
			or body.contains("get_remote_sender_id() in [0, 1]") \
			or body.contains("sender == 1"):
		return "host->client"
	if body.contains("is_host()") or body.contains("_valid_sender()"):
		return "client->host"
	return "host->client"


func _infer_scope(path: String, method_name: String, direction: String, source: String) -> String:
	if direction == "client->host":
		return "host"
	var key := "%s:%s" % [path, method_name]
	if OWNER_ONLY_HOST_TO_CLIENT.has(key):
		return "single_peer"
	if source.contains("rpc_to_run(%s" % method_name):
		return "run_peers"
	if source.contains("rpc_to_all(%s" % method_name) or source.contains("%s.rpc(" % method_name):
		return "all_peers"
	if source.contains("%s.rpc_id(" % method_name):
		return "single_peer"
	return "all_peers"
