extends RefCounted
## Version 1 binary data frames. Control messages always use JSON.

const INPUT := 1
const SNAPSHOT := 2
const STATES := ["ok", "downed", "turned", "out"]
const TYPES := ["drip", "gutter", "mister", "hailstone", "sleet", "smog", "static",
	"thunderhead", "undertow", "cloudburst", "cumulus", "turned"]
const ANIMS := ["spawn", "idle", "walk", "attack", "windup", "stagger", "die"]
const KINDS := ["weapon", "ammo", "health", "suit", "scrap", "item", "airdrop", "station"]
const PHASES := ["calm", "drizzle", "downpour", "acid_storm", "clearing"]
const NULL_U16 := 65535
const NO_ACK := 4294967295


static func input(data: PackedByteArray) -> Dictionary:
	if data.size() != 17 or data[0] != INPUT:
		return {}
	return {"t": "in", "seq": data.decode_u32(1),
		"mv": [data.decode_s16(5) / 32767.0, data.decode_s16(7) / 32767.0],
		"yaw": data.decode_s16(9) / 1000.0, "pitch": data.decode_s16(11) / 1000.0,
		"b": data.decode_u16(13), "slot": data[15], "wheel": data.decode_s8(16)}


static func snapshot(frame: Dictionary) -> PackedByteArray:
	var out := StreamPeerBuffer.new()
	out.put_u8(SNAPSHOT)
	out.put_u32(frame.tick)
	out.put_u64(frame.t_ms)
	out.put_u32(NO_ACK if frame.ack < 0 else frame.ack)
	you(out, frame.you)
	out.put_u16(frame.players.size())
	for row: Dictionary in frame.players:
		out.put_u32(row.id)
		pos(out, row.pos)
		angles(out, row.yaw, row.pitch)
		out.put_8(STATES.find(row.state))
		out.put_u8(2 if row.crouch == null else int(row.crouch))
		str_field(out, row.name)
		str_field(out, row.item)
		out.put_u32(Color(row.suit_color).to_rgba32())
		str_field(out, row.skin)
	out.put_u16(frame.enemies.size())
	for row: Dictionary in frame.enemies:
		out.put_32(row.id)
		out.put_8(TYPES.find(row.type))
		pos(out, row.pos)
		out.put_16(roundi(row.yaw * 1000))
		u16_scaled(out, row.hp, 1000)
		out.put_8(ANIMS.find(row.anim))
	out.put_u16(frame.pickups.size())
	for row: Dictionary in frame.pickups:
		out.put_64(row.id)
		out.put_8(KINDS.find(row.kind))
		pos(out, row.pos)
		str_field(out, row.item)
	out.put_u16(frame.projectiles.size())
	for row: Dictionary in frame.projectiles:
		out.put_64(row.id)
		pos(out, row.pos)
		vel(out, row.vel)
		str_field(out, row.kind)
	var weather: Dictionary = frame.weather
	out.put_8(PHASES.find(weather.phase))
	u16_scaled(out, weather.intensity, 1000)
	out.put_u32(weather.wave)
	out.put_u32(roundi(weather.phase_time_left * 100))
	out.put_u8(int(weather.lightning))
	var run: Dictionary = frame.run
	out.put_u16(run.alive_enemies)
	out.put_u8(int(run.endless))
	out.put_u16(run.shared_decon)
	out.put_u32(run.score)
	return out.data_array


static func you(out: StreamPeerBuffer, row: Dictionary) -> void:
	out.put_u32(row.id)
	pos(out, row.pos)
	vel(out, row.vel)
	angles(out, row.yaw, row.pitch)
	out.put_8(STATES.find(row.state))
	for field in ["hp", "hp_max", "suit", "suit_max"]:
		u16_scaled(out, row[field], 100)
	var flags := 0
	var fields := ["exposed", "sheltered", "in_puddle", "crouch", "aiming", "reloading"]
	for i in fields.size():
		if row[fields[i]]:
			flags |= 1 << i
	out.put_u8(flags)
	out.put_u8(row.slot)
	for slot: Variant in row.slots:
		out.put_u8(int(slot != null))
		if slot != null:
			str_field(out, slot.item)
			str_field(out, slot.name)
			for field in ["ammo", "mag", "reserve", "count"]:
				u16_scaled(out, slot[field], 1)
	out.put_u32(row.scrap)
	u16_scaled(out, row.revive, 1000)
	u16_scaled(out, row.interact_progress, 1000)
	str_field(out, row.prompt)
	str_field(out, row.pouch)
	out.put_u16(row.grenades)
	out.put_u16(row.domes)


static func pos(out: StreamPeerBuffer, value: Array) -> void:
	for axis: float in value:
		out.put_32(roundi(axis * 100))


static func vel(out: StreamPeerBuffer, value: Array) -> void:
	for axis: float in value:
		out.put_16(clampi(roundi(axis * 100), -32768, 32767))


static func angles(out: StreamPeerBuffer, yaw: float, pitch: float) -> void:
	out.put_16(roundi(yaw * 1000))
	out.put_16(roundi(pitch * 1000))


static func str_field(out: StreamPeerBuffer, value: String) -> void:
	var bytes := value.to_utf8_buffer()
	out.put_u16(bytes.size())
	out.put_data(bytes)


static func u16_scaled(out: StreamPeerBuffer, value: Variant, scale: int) -> void:
	out.put_u16(NULL_U16 if value == null else clampi(roundi(value * scale), 0, NULL_U16 - 1))
