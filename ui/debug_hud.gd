extends CanvasLayer
## Debug readout (F9): frame timing, exact player transform for map editing,
## vitals, inventory, weather/wave state, world counts and active dev flags.

const REFRESH := 0.1
const KEYS := "F1 phase  F2 wave 5  F3-F5 Drip/Gutter/Mister  Shift+F3-F8 specials  F6 lightning\nF8 retro  F9 this readout  F10 dev tools  F11 fullscreen"

@onready var info: Label = $Info

var _refresh_left := 0.0


func _ready() -> void:
	visible = false
	# Keep reading while the dev menu has the tree paused.
	process_mode = Node.PROCESS_MODE_ALWAYS
	info.add_theme_font_override("font", BroadcastUI.FONT)
	info.add_theme_font_size_override("font_size", 18)
	info.add_theme_color_override("font_color", BroadcastUI.PAPER)
	info.add_theme_constant_override("line_spacing", -2)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F9:
		visible = not visible
		_refresh_left = 0.0


func _process(delta: float) -> void:
	if not visible:
		return
	# Real time, so slow-mo dev scales don't slow the readout down too.
	_refresh_left -= delta / maxf(Engine.time_scale, 0.01)
	if _refresh_left > 0.0:
		return
	_refresh_left = REFRESH
	info.text = "\n".join(_lines())


func _lines() -> PackedStringArray:
	var lines := PackedStringArray()
	var fps := Engine.get_frames_per_second()
	lines.append("FPS %d  %.1f ms  TIME %.2fx  %s" % [fps, 1000.0 / maxf(fps, 1.0), Engine.time_scale, _net_text()])
	var player := get_tree().get_first_node_in_group("local_player") as Player
	if player == null:
		lines.append("NO LOCAL PLAYER")
	else:
		var at := player.global_position
		var yaw := fposmod(player.global_rotation_degrees.y, 360.0)
		lines.append("POS (%.2f, %.2f, %.2f)  YAW %.1f  PITCH %.1f" % [at.x, at.y, at.z, yaw, player.head.rotation_degrees.x])
		var speed := Vector2(player.velocity.x, player.velocity.z).length()
		lines.append("SPEED %.1f m/s  VY %.1f  %s  %s%s" % [speed, player.velocity.y, player.get_move_state().to_upper(),
			"SHELTERED" if player.sheltered else "EXPOSED", "  PUDDLE" if player.in_puddle else ""])
		lines.append("HP %d/%d  SUIT %d%%  STATE %s%s" % [ceili(player.health), roundi(player.max_health), roundi(player.suit_integrity),
			player.state.to_upper(), "  INVULN" if player.invulnerable else ""])
		lines.append_array(_inventory_lines(player))
	lines.append("")
	lines.append("WAVE %d%s  %s  %ds%s" % [WeatherManager.wave, " ENDLESS" if GameManager.endless else "", WeatherManager.phase_name().to_upper(),
		ceili(WeatherManager.phase_time_left), "  HOLD" if WeatherManager.hold else ""])
	var forecast := WeatherManager.wave_modifier()
	lines.append("STORM %s  %.2f -> %.2f%s%s" % [WeatherManager.storm_name().to_upper(), WeatherManager.storm_intensity,
		WeatherManager.intensity_override if WeatherManager.intensity_override >= 0.0 else WeatherManager.target_intensity,
		"  OVERRIDE" if WeatherManager.intensity_override >= 0.0 else "", "  FORECAST " + forecast.to_upper() if not forecast.is_empty() else ""])
	lines.append(_world_text())
	var flags := _dev_flags()
	if not flags.is_empty():
		lines.append("DEV " + "  ".join(flags))
	lines.append("")
	lines.append(KEYS)
	return lines


func _inventory_lines(player: Player) -> PackedStringArray:
	var lines := PackedStringArray()
	var holder := player.get_node_or_null("Head/Camera3D/WeaponHolder") as WeaponHolder
	if holder == null:
		return lines
	var item := holder.selected()
	var definition := holder.selected_definition()
	if item and definition:
		var ammo := ""
		if definition.kind == ItemDefinition.Kind.GUN:
			ammo = "%d/%d" % [item.count, holder.selected_reserve()]
		else:
			ammo = "x%d" % item.count
		lines.append("SLOT %d  %s [%s]  %s%s" % [holder.current + 1, definition.display_name.to_upper(),
			ItemCatalog.tier_name(item.id, item.tier), ammo, "  RELOAD %.1fs" % holder.reload_remaining() if holder.reload_remaining() > 0.0 else ""])
	else:
		lines.append("SLOT %d  EMPTY" % (holder.current + 1))
	var carried := PackedStringArray()
	for i in holder.slots.size():
		var slot := holder.slots[i]
		carried.append("%d:%s" % [i + 1, slot.id if slot else "-"])
	var pouch := _pouch_text(holder)
	lines.append("SCRAP %d  %s%s" % [holder.scrap, " ".join(carried), "  POUCH " + pouch if not pouch.is_empty() else ""])
	return lines


## Grenade/dome pouches, when the holder has them (pouch_count or pouches).
func _pouch_text(holder: WeaponHolder) -> String:
	var parts := PackedStringArray()
	if holder.has_method("pouch_count"):
		var args: Array = []
		for method: Dictionary in holder.get_method_list():
			if method.name == "pouch_count":
				args = method.get("args", [])
				break
		if args.size() >= 1:
			for id: String in ["frag", "shield_dome"]:
				parts.append("%s %s" % [id.to_upper().replace("_", " "), str(holder.call("pouch_count", id))])
			return " ".join(parts)
	var pouches: Variant = holder.get("pouches")
	if pouches is Dictionary:
		for id in pouches:
			parts.append("%s %s" % [str(id).to_upper().replace("_", " "), str(pouches[id])])
	return " ".join(parts)


func _world_text() -> String:
	var scene := get_tree().current_scene
	var spawner := scene.get_node_or_null("Enemies") if scene else null
	var enemies := "ENEMIES %d" % get_tree().get_nodes_in_group("enemies").size()
	if spawner and spawner.has_method("remaining") and spawner.has_method("wave_total"):
		enemies += "  LEFT %d/%d" % [spawner.remaining(), spawner.wave_total()]
	var loot := RunLoot.find(get_tree())
	var pickups := loot.pickups.size() if loot else 0
	return "%s  PICKUPS %d  DECON %d/%d  MAP %s" % [enemies, pickups, GameManager.decon_charges, GameManager.decon_max, GameManager.map_id]


func _dev_flags() -> PackedStringArray:
	var dev := get_tree().get_first_node_in_group("dev_menu")
	if dev and dev.has_method("active_flags"):
		return dev.active_flags()
	return PackedStringArray()


func _net_text() -> String:
	if not Net.is_online():
		return "SOLO"
	return "HOST" if Net.is_host() else "CLIENT %d" % multiplayer.get_unique_id()
