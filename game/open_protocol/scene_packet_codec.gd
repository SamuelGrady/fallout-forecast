extends RefCounted
## Godot 4.7.2 SceneMultiplayer packet codec + Full-tier binary frame codec.
##
## Matches modules/multiplayer/scene_multiplayer.cpp, scene_rpc_interface.cpp,
## scene_cache_interface.cpp, and scene/main/multiplayer_api.cpp byte for byte.
##
## Full-tier binary frames (used when hello.enc == "bin"):
##   Tag 0x03 (FULL_BIN_RPC):
##     [0]      u8      0x03
##     [1]      u8      flags: bits 0..1 = transfer_mode (0=unreliable, 1=unreliable_ordered, 2=reliable)
##     [2]      u8      channel (0..255)
##     [3..4]   u16 LE  node_path_len (N)
##     [5..5+N) utf8    node_path relative to /root (no NUL)
##     [5+N]    u8      method_len (M)
##     [6+N..)  utf8    method_name (no NUL)
##     [6+N+M]  u8      argc (0..255)
##     [7+N+M..)        argc Godot var_to_bytes (allow_objects=false) values
##
##   Tag 0x04 (FULL_BIN_RAW):
##     [0]      u8      0x04
##     [1]      u8      flags (bits 0..1 = transfer_mode)
##     [2]      u8      channel (0..255)
##     [3..)    bytes   raw payload

const VariantJson := preload("res://game/open_protocol/variant_json.gd")

# SceneMultiplayer::NetworkCommands (bits 0..2 of byte 0)
const CMD_REMOTE_CALL := 0
const CMD_SIMPLIFY_PATH := 1
const CMD_CONFIRM_PATH := 2
const CMD_RAW := 3
const CMD_SPAWN := 4
const CMD_DESPAWN := 5
const CMD_SYNC := 6
const CMD_SYS := 7
const CMD_MASK := 0x07

# SceneRPCInterface flags in byte 0
const NODE_ID_COMPRESSION_SHIFT := 4
const NAME_ID_COMPRESSION_SHIFT := 6
const BYTE_ONLY_OR_NO_ARGS_SHIFT := 7
const NODE_ID_COMPRESSION_FLAG := 0x30
const NAME_ID_COMPRESSION_FLAG := 0x40
const BYTE_ONLY_OR_NO_ARGS_FLAG := 0x80

const NODE_ID_COMP_8 := 0
const NODE_ID_COMP_16 := 1
const NODE_ID_COMP_32 := 2

const NAME_ID_COMP_8 := 0
const NAME_ID_COMP_16 := 1

# MultiplayerAPI compressed variant meta
const VARIANT_META_TYPE_MASK := 0x3F
const VARIANT_META_EMODE_MASK := 0xC0
const VARIANT_META_BOOL_MASK := 0x80
const ENCODE_8 := 0x00
const ENCODE_16 := 0x40
const ENCODE_32 := 0x80
const ENCODE_64 := 0xC0

# Open Protocol Full-tier binary frame tags (< 0x09 so raw TCP auto-detects binary;
# Thin tier uses 0x01 input and 0x02 snapshot).
const FULL_BIN_RPC := 0x03
const FULL_BIN_RAW := 0x04

# Script -> {"names": Array[String], "ids": Dictionary[String, int], "configs": Dictionary[String, Dictionary], "arg_types": Dictionary[String, Array]}
static var _script_cache: Dictionary = {}


static func normalize_rel_path(path: String) -> String:
	var clean := path.strip_edges()
	if clean.begins_with("/root/"):
		clean = clean.substr(6)
	elif clean.begins_with("/"):
		clean = clean.substr(1)
	return clean


static func _get_script_info(script: Script) -> Dictionary:
	if script == null:
		return {"names": [], "ids": {}, "configs": {}, "arg_types": {}}
	var sid := script.get_instance_id()
	if _script_cache.has(sid):
		return _script_cache[sid]
	var cfg: Variant = script.get_rpc_config()
	var names: Array[String] = []
	var ids: Dictionary = {}
	var configs: Dictionary = {}
	if cfg is Dictionary:
		for k: Variant in cfg.keys():
			names.append(String(k))
		# Matches SceneRPCInterface::_parse_rpc_config (StringLikeVariantOrder::compare).
		names.sort()
		for i in names.size():
			var name_str: String = names[i]
			ids[name_str] = i
			var entry: Variant = cfg.get(StringName(name_str), cfg.get(name_str))
			if entry is Dictionary:
				configs[name_str] = {
					"rpc_mode": int(entry.get("rpc_mode", MultiplayerAPI.RPC_MODE_AUTHORITY)),
					"transfer_mode": int(entry.get("transfer_mode", MultiplayerPeer.TRANSFER_MODE_RELIABLE)),
					"call_local": bool(entry.get("call_local", false)),
					"channel": int(entry.get("channel", 0)),
				}
	var arg_types: Dictionary = {}
	for m: Dictionary in script.get_script_method_list():
		var mname: String = str(m.get("name", ""))
		if ids.has(mname):
			var types: Array[int] = []
			for a: Dictionary in m.get("args", []):
				types.append(int(a.get("type", TYPE_NIL)))
			arg_types[mname] = types
	var info := {"names": names, "ids": ids, "configs": configs, "arg_types": arg_types}
	_script_cache[sid] = info
	return info


static func get_method_arg_types(node: Node, method_name: String) -> Array:
	if node == null:
		return []
	var script := node.get_script() as Script
	if script == null:
		return []
	var info := _get_script_info(script)
	return info.arg_types.get(method_name, [])


static func compute_rpc_md5(node: Node) -> String:
	if node == null:
		return ""
	var script := node.get_script() as Script
	var info := _get_script_info(script)
	var concat := ""
	for n: String in info.names:
		concat += n
	return concat.md5_text()


## Decode a Godot SceneMultiplayer packet (server -> peer).
static func decode_packet(packet: PackedByteArray, tree: SceneTree, peer_cache: Dictionary) -> Dictionary:
	if packet.is_empty():
		return {"ok": false, "error": "Empty packet"}
	var cmd := packet[0] & CMD_MASK
	match cmd:
		CMD_SIMPLIFY_PATH:
			return _decode_simplify_path(packet)
		CMD_CONFIRM_PATH:
			if packet.size() != 6:
				return {"ok": false, "error": "Invalid CONFIRM_PATH size"}
			return {"ok": true, "cmd": CMD_CONFIRM_PATH, "valid": packet[1] != 0, "cache_id": packet.decode_u32(2)}
		CMD_REMOTE_CALL:
			return _decode_rpc(packet, tree, peer_cache)
		CMD_RAW:
			if packet.size() < 2:
				return {"ok": false, "error": "Invalid RAW packet size"}
			return {"ok": true, "cmd": CMD_RAW, "data": packet.slice(1)}
		_:
			return {"ok": true, "cmd": cmd, "data": packet}


static func _decode_simplify_path(packet: PackedByteArray) -> Dictionary:
	if packet.size() < 38:
		return {"ok": false, "error": "SIMPLIFY_PATH packet too small"}
	var md5 := packet.slice(1, 33).get_string_from_utf8()
	var cache_id := packet.decode_u32(34)
	var path := _decode_cstring(packet, 38, packet.size())
	return {"ok": true, "cmd": CMD_SIMPLIFY_PATH, "md5": md5, "cache_id": cache_id, "path": path}


static func _decode_cstring(packet: PackedByteArray, start: int, end: int) -> String:
	var stop := end
	while stop > start and packet[stop - 1] == 0:
		stop -= 1
	return packet.slice(start, stop).get_string_from_utf8()


static func _decode_rpc(packet: PackedByteArray, tree: SceneTree, peer_cache: Dictionary) -> Dictionary:
	var meta := packet[0]
	var node_comp := (meta & NODE_ID_COMPRESSION_FLAG) >> NODE_ID_COMPRESSION_SHIFT
	var name_comp := (meta & NAME_ID_COMPRESSION_FLAG) >> NAME_ID_COMPRESSION_SHIFT
	var byte_only_or_no_args := (meta & BYTE_ONLY_OR_NO_ARGS_FLAG) != 0

	var ofs := 1
	var node_target := 0
	match node_comp:
		NODE_ID_COMP_8:
			if packet.size() < ofs + 1:
				return {"ok": false, "error": "Truncated node_id (8)"}
			node_target = packet[ofs]
			ofs += 1
		NODE_ID_COMP_16:
			if packet.size() < ofs + 2:
				return {"ok": false, "error": "Truncated node_id (16)"}
			node_target = packet.decode_u16(ofs)
			ofs += 2
		NODE_ID_COMP_32:
			if packet.size() < ofs + 4:
				return {"ok": false, "error": "Truncated node_id (32)"}
			node_target = packet.decode_u32(ofs)
			ofs += 4
		_:
			return {"ok": false, "error": "Invalid node_id_compression %d" % node_comp}

	var name_id := 0
	match name_comp:
		NAME_ID_COMP_8:
			if packet.size() < ofs + 1:
				return {"ok": false, "error": "Truncated name_id (8)"}
			name_id = packet[ofs]
			ofs += 1
		NAME_ID_COMP_16:
			if packet.size() < ofs + 2:
				return {"ok": false, "error": "Truncated name_id (16)"}
			name_id = packet.decode_u16(ofs)
			ofs += 2
		_:
			return {"ok": false, "error": "Invalid name_id_compression %d" % name_comp}

	var rel_path := ""
	var args_end := packet.size()
	var cache_id := -1
	if (node_target & 0x80000000) != 0:
		var path_ofs := node_target & 0x7FFFFFFF
		if path_ofs < ofs or path_ofs >= packet.size():
			return {"ok": false, "error": "Invalid inline path offset %d" % path_ofs}
		rel_path = _decode_cstring(packet, path_ofs, packet.size())
		args_end = path_ofs
	else:
		cache_id = node_target
		rel_path = str(peer_cache.get(cache_id, ""))
		if rel_path.is_empty():
			return {"ok": false, "error": "Unknown node cache_id %d" % cache_id}

	var node := tree.root.get_node_or_null(rel_path) if tree and tree.root else null
	if node == null:
		return {"ok": false, "error": "Node not found: %s" % rel_path}

	var script := node.get_script() as Script
	var info := _get_script_info(script)
	if (name_id & 0x8000) != 0:
		return {"ok": false, "error": "Node-level RPC id 0x%x unsupported on %s" % [name_id, rel_path]}
	if name_id < 0 or name_id >= info.names.size():
		return {"ok": false, "error": "RPC method id %d out of range on %s" % [name_id, rel_path]}
	var method_name: String = info.names[name_id]

	var args := []
	if byte_only_or_no_args:
		if ofs < args_end:
			args.append(packet.slice(ofs, args_end))
	else:
		if ofs >= args_end:
			return {"ok": false, "error": "Missing argc byte"}
		var argc := packet[ofs]
		ofs += 1
		for i in argc:
			var dec := decode_compressed_variant(packet, ofs, args_end)
			if not dec.ok:
				return dec
			args.append(dec.value)
			ofs = dec.next_offset

	return {
		"ok": true,
		"cmd": CMD_REMOTE_CALL,
		"node": rel_path,
		"method": method_name,
		"args": args,
		"cache_id": cache_id,
		"name_id": name_id,
		"node_comp": node_comp,
		"name_comp": name_comp,
	}


## Encode a Godot SceneMultiplayer CONFIRM_PATH packet (6 bytes).
static func encode_confirm_path(cache_id: int, valid := true) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(6)
	out[0] = CMD_CONFIRM_PATH
	out[1] = 1 if valid else 0
	out.encode_u32(2, cache_id)
	return out


## Encode a Godot SceneMultiplayer SIMPLIFY_PATH packet.
static func encode_simplify_path(methods_md5: String, cache_id: int, rel_path: String) -> PackedByteArray:
	var md5_bytes := methods_md5.to_utf8_buffer()
	var path_bytes := normalize_rel_path(rel_path).to_utf8_buffer()
	var out := PackedByteArray()
	out.resize(1 + 33 + 4 + path_bytes.size() + 1)
	out[0] = CMD_SIMPLIFY_PATH
	for i in mini(32, md5_bytes.size()):
		out[1 + i] = md5_bytes[i]
	out[33] = 0
	out.encode_u32(34, cache_id)
	for i in path_bytes.size():
		out[38 + i] = path_bytes[i]
	out[38 + path_bytes.size()] = 0
	return out


## Encode a Godot SceneMultiplayer RAW packet.
static func encode_raw(data: PackedByteArray) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(1 + data.size())
	out[0] = CMD_RAW
	for i in data.size():
		out[1 + i] = data[i]
	return out


## Encode an RPC into a Godot SceneMultiplayer packet (exact SceneRPCInterface format).
## Pass cache_id < 0 to embed the inline node path (safe across scene reloads, no
## SIMPLIFY_PATH handshake needed). Pass cache_id >= 0 (and optional force_node_comp)
## to produce the exact compressed cached form for round-trip parity.
static func encode_rpc(tree: SceneTree, rel_path: String, method_name: String, args: Array,
		cache_id := -1, force_node_comp := -1) -> Dictionary:
	var norm_path := normalize_rel_path(rel_path)
	if norm_path.is_empty():
		return {"ok": false, "error": "Empty node path", "node_missing": false}
	var node := tree.root.get_node_or_null(norm_path) if tree and tree.root else null
	if node == null:
		return {"ok": false, "error": "Node not found: %s" % norm_path, "node_missing": true}
	var script := node.get_script() as Script
	var info := _get_script_info(script)
	if not info.ids.has(method_name):
		return {"ok": false, "error": "Unknown RPC method '%s' on %s" % [method_name, norm_path], "node_missing": false}
	var name_id: int = info.ids[method_name]
	var cfg: Dictionary = info.configs.get(method_name, {})
	if args.size() > 255:
		return {"ok": false, "error": "Too many RPC arguments", "node_missing": false}

	var node_comp := NODE_ID_COMP_32
	if cache_id >= 0:
		if force_node_comp >= 0:
			node_comp = force_node_comp
		elif cache_id <= 255:
			node_comp = NODE_ID_COMP_8
		elif cache_id <= 65535:
			node_comp = NODE_ID_COMP_16
		else:
			node_comp = NODE_ID_COMP_32

	var name_comp := NAME_ID_COMP_8 if name_id <= 255 else NAME_ID_COMP_16

	# Encode args using MultiplayerAPI::encode_and_compress_variants rules.
	var byte_only_or_no_args := false
	var arg_bytes := PackedByteArray()
	if args.is_empty():
		byte_only_or_no_args = true
	elif args.size() == 1 and typeof(args[0]) == TYPE_PACKED_BYTE_ARRAY:
		byte_only_or_no_args = true
		arg_bytes = args[0]
	else:
		arg_bytes.append(args.size())
		for arg: Variant in args:
			arg_bytes.append_array(encode_compressed_variant(arg))

	var meta := CMD_REMOTE_CALL | (node_comp << NODE_ID_COMPRESSION_SHIFT) | (name_comp << NAME_ID_COMPRESSION_SHIFT) | (BYTE_ONLY_OR_NO_ARGS_FLAG if byte_only_or_no_args else 0)

	var out := PackedByteArray()
	out.append(meta)
	var node_id_ofs := out.size()
	match node_comp:
		NODE_ID_COMP_8:
			out.append(cache_id & 0xFF)
		NODE_ID_COMP_16:
			out.resize(node_id_ofs + 2)
			out.encode_u16(node_id_ofs, cache_id)
		NODE_ID_COMP_32:
			out.resize(node_id_ofs + 4)
			out.encode_u32(node_id_ofs, cache_id if cache_id >= 0 else 0)
	var name_ofs := out.size()
	if name_comp == NAME_ID_COMP_8:
		out.append(name_id & 0xFF)
	else:
		out.resize(name_ofs + 2)
		out.encode_u16(name_ofs, name_id)

	out.append_array(arg_bytes)

	if cache_id < 0:
		var path_ofs := out.size()
		out.encode_u32(node_id_ofs, 0x80000000 | path_ofs)
		out.append_array(norm_path.to_utf8_buffer())
		out.append(0)

	return {
		"ok": true,
		"packet": out,
		"channel": int(cfg.get("channel", 0)),
		"transfer_mode": int(cfg.get("transfer_mode", MultiplayerPeer.TRANSFER_MODE_RELIABLE)),
	}


## MultiplayerAPI::encode_and_compress_variant (exact Godot 4.7.2 layout).
static func encode_compressed_variant(val: Variant) -> PackedByteArray:
	var out := PackedByteArray()
	match typeof(val):
		TYPE_BOOL:
			out.append((VARIANT_META_BOOL_MASK if val else 0) | TYPE_BOOL)
			return out
		TYPE_INT:
			var n: int = val
			if n >= -128 and n <= 127:
				out.resize(2)
				out[0] = ENCODE_8 | TYPE_INT
				out.encode_s8(1, n)
			elif n >= -32768 and n <= 32767:
				out.resize(3)
				out[0] = ENCODE_16 | TYPE_INT
				out.encode_s16(1, n)
			elif n >= -2147483648 and n <= 2147483647:
				out.resize(5)
				out[0] = ENCODE_32 | TYPE_INT
				out.encode_s32(1, n)
			else:
				out.resize(9)
				out[0] = ENCODE_64 | TYPE_INT
				out.encode_s64(1, n)
			return out
		_:
			var safe: Variant = null if typeof(val) in [TYPE_OBJECT, TYPE_RID, TYPE_CALLABLE, TYPE_SIGNAL] else val
			var encoded := var_to_bytes(safe)
			if not encoded.is_empty():
				encoded[0] = typeof(safe)
			return encoded


## MultiplayerAPI::decode_and_decompress_variant (exact Godot 4.7.2 layout).
static func decode_compressed_variant(buf: PackedByteArray, offset: int, limit: int) -> Dictionary:
	if offset >= limit:
		return {"ok": false, "error": "Truncated compressed variant"}
	var header := buf[offset]
	var vtype := header & VARIANT_META_TYPE_MASK
	var emode := header & VARIANT_META_EMODE_MASK
	match vtype:
		TYPE_BOOL:
			return {"ok": true, "value": (header & VARIANT_META_BOOL_MASK) != 0, "next_offset": offset + 1}
		TYPE_INT:
			match emode:
				ENCODE_8:
					if offset + 2 > limit:
						return {"ok": false, "error": "Truncated int8 variant"}
					return {"ok": true, "value": buf.decode_s8(offset + 1), "next_offset": offset + 2}
				ENCODE_16:
					if offset + 3 > limit:
						return {"ok": false, "error": "Truncated int16 variant"}
					return {"ok": true, "value": buf.decode_s16(offset + 1), "next_offset": offset + 3}
				ENCODE_32:
					if offset + 5 > limit:
						return {"ok": false, "error": "Truncated int32 variant"}
					return {"ok": true, "value": buf.decode_s32(offset + 1), "next_offset": offset + 5}
				_:
					if offset + 9 > limit:
						return {"ok": false, "error": "Truncated int64 variant"}
					return {"ok": true, "value": buf.decode_s64(offset + 1), "next_offset": offset + 9}
		_:
			if offset + 4 > limit:
				return {"ok": false, "error": "Truncated variant header"}
			var vlen := buf.decode_var_size(offset, false)
			if vlen <= 0 or offset + vlen > limit:
				return {"ok": false, "error": "Invalid variant length %d" % vlen}
			return {"ok": true, "value": buf.decode_var(offset, false), "next_offset": offset + vlen}


## Encode a Full-tier binary RPC frame (tag 0x03).
static func encode_full_bin_rpc(node_path: String, method_name: String, args: Array,
		channel: int, transfer_mode: int) -> PackedByteArray:
	var path_bytes := node_path.to_utf8_buffer()
	var method_bytes := method_name.to_utf8_buffer()
	var arg_bytes := VariantJson.encode_args_bin(args)
	var out := PackedByteArray()
	out.resize(5)
	out[0] = FULL_BIN_RPC
	out[1] = transfer_mode & 0x03
	out[2] = channel & 0xFF
	out.encode_u16(3, path_bytes.size())
	out.append_array(path_bytes)
	out.append(method_bytes.size() & 0xFF)
	out.append_array(method_bytes)
	out.append(args.size() & 0xFF)
	out.append_array(arg_bytes)
	return out


## Decode a Full-tier binary RPC (0x03) or RAW (0x04) frame from a client.
static func decode_full_bin(data: PackedByteArray, tree: SceneTree) -> Dictionary:
	if data.is_empty():
		return {"ok": false, "error": "Empty binary frame"}
	match data[0]:
		FULL_BIN_RPC:
			if data.size() < 7:
				return {"ok": false, "error": "Binary RPC frame too short"}
			var transfer_mode := data[1] & 0x03
			var channel := data[2]
			var path_len := data.decode_u16(3)
			var ofs := 5
			if ofs + path_len + 2 > data.size():
				return {"ok": false, "error": "Truncated binary RPC node path"}
			var node_path := normalize_rel_path(data.slice(ofs, ofs + path_len).get_string_from_utf8())
			ofs += path_len
			var method_len := data[ofs]
			ofs += 1
			if ofs + method_len + 1 > data.size():
				return {"ok": false, "error": "Truncated binary RPC method"}
			var method_name := data.slice(ofs, ofs + method_len).get_string_from_utf8()
			ofs += method_len
			var argc := data[ofs]
			ofs += 1
			var node := tree.root.get_node_or_null(node_path) if tree and tree.root else null
			var hints := get_method_arg_types(node, method_name) if node else []
			var dec := VariantJson.decode_args_bin(data, ofs, argc, hints)
			if not dec.ok:
				return dec
			return {
				"ok": true,
				"t": "rpc",
				"node": node_path,
				"method": method_name,
				"args": dec.args,
				"ch": channel,
				"mode": transfer_mode,
			}
		FULL_BIN_RAW:
			if data.size() < 4:
				return {"ok": false, "error": "Binary RAW frame too short"}
			return {
				"ok": true,
				"t": "raw",
				"mode": data[1] & 0x03,
				"ch": data[2],
				"data": data.slice(3),
			}
		_:
			return {"ok": false, "error": "Unknown binary frame tag 0x%02x" % data[0]}


## Encode a Full-tier binary RAW frame (tag 0x04).
static func encode_full_bin_raw(payload: PackedByteArray, channel: int, transfer_mode: int) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(3)
	out[0] = FULL_BIN_RAW
	out[1] = transfer_mode & 0x03
	out[2] = channel & 0xFF
	out.append_array(payload)
	return out
