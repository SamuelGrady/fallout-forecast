class_name WeaponHolder
extends Node3D
## Host owns slots, shared reserves, reload, fire cadence and curse rolls.
## Copies on clients hold the owner's latest snapshot and public equipment.

signal weapon_changed(data: WeaponData)
signal fired(data: WeaponData)
## Local owner only: a held pouch item was thrown.
signal thrown(id: String)

const HIT_MASK := 1 | 4
const SLOT_COUNT := 5
const SPRINT_RAISE := 0.15
## Quick-throw pouches (Frag Grenade / Shield Dome) live outside the 5 slots.
const THROW_COOLDOWN := 0.35
const STARTING_FRAGS := 2
const STARTING_DOMES := 1
const POUCH_ORDER := ["frag", "shield_dome"]

var slots: Array[ItemInstance] = [null, null, null, null, null]
var reserves: Dictionary = {}
var _seeded_ammo: Dictionary = {"revolver": true}
var current := 0
var active_pouch := ""
var scrap := 0
## Belt pouches: host-authoritative, mirrored to the owner in _private_state.
var grenades := 0
var domes := 0
var _throw_cooldown := 0.0
var _last_throw_at := -1000.0
var revision := 0
var _public_revision := -1
var _private_revision := -1
var equipped_id := ""
var equipped_tier := 0
var _model: Node3D
var _model_serial := -1
var player: Node3D
var camera: Camera3D
var loot: RunLoot

var _cooldown := 0.0
var _reload_left := 0.0
var _reload_total := 1.0
var _reload_serial := 0
var _jam_left := 0.0
var _charge_serial := 0
var _charge_at := 0.0
var _pending_action := 0.0
var _pending_pouch := ""
var _pouch_ack_left := 0.0
var _pouch_fire_latched := false
var _kick := 0.0
var _harpoon_motion_left := 0.0
var _bob := 0.0
var _aim := 0.0
var _equip_left := 0.0
var _fire_buffer := 0.0
var _loadout_fire_blocked := false
var _recoil := 0.0
var _camera_kick := 0.0
var _heat := 0.0
var _visual_heat := 0.0
var _local_charging := false
var _local_charge_at := 0.0
var _effect_cooldowns: Dictionary = {}
var _hip_fov := 75.0
var _raise_left := 0.0
var _sight_point := Vector3.INF
var _shot_counter := 0
var _spread_at := 0.0
var _pose := preload("res://weapons/item_pose.gd").new()
var _gesture_left := 0.0
var _gesture_duration := 0.3
var _remote_equip := 0.0
var _public_reloading := false
var _remote_reload_left := 0.0
var _remote_reload_total := 1.0
var _remote_view: Node3D

func _ready() -> void:
	camera = get_parent() as Camera3D
	_hip_fov = camera.fov
	player = camera.get_parent().get_parent() as Node3D
	loot = RunLoot.find(get_tree())
	if Net.is_host() and loot:
		slots[0] = loot.make_item("service_revolver")
		reserves["revolver"] = 24
		grenades = STARTING_FRAGS
		domes = STARTING_DOMES
		_refresh_equip()
		if loot.run_id > 0:
			send_state()

func selected() -> ItemInstance:
	return slots[current]

func selected_serial() -> int:
	return selected().serial if selected() else 0

func active_count() -> int:
	if not active_pouch.is_empty():
		return pouch_count(active_pouch)
	return selected().count if selected() else 0

func selected_definition() -> ItemDefinition:
	if not active_pouch.is_empty():
		return ItemCatalog.definition(active_pouch)
	return ItemCatalog.definition(selected().id) if selected() else null

func selected_weapon() -> WeaponData:
	var definition := selected_definition()
	return definition.weapon if definition else null

func selected_reserve() -> int:
	if not active_pouch.is_empty():
		return 0
	var definition := selected_definition()
	return int(reserves.get(definition.ammo_type, 0)) if definition and not definition.ammo_type.is_empty() else 0

func reload_remaining() -> float:
	return _reload_left

func jammed() -> bool:
	return _jam_left > 0.0 and active_pouch.is_empty()

func is_charging() -> bool:
	var data := selected_weapon()
	return active_pouch.is_empty() and _local_charging and data != null and data.charge_time > 0.0 and selected() != null and selected().count > 0

func charge_progress() -> float:
	if not is_charging():
		return 0.0
	var data := selected_weapon()
	var elapsed := (Time.get_ticks_msec() / 1000.0) - _local_charge_at
	return clampf(elapsed / maxf(data.charge_time, 0.01), 0.0, 1.0)

## Live angular spread in degrees for Fortnite-style dynamic crosshair projection.
func current_spread_degrees() -> float:
	var data := selected_weapon()
	if data == null or data.kind != WeaponData.Kind.HITSCAN:
		return 0.0
	var ads_scale := 0.25 if GameManager.has_player_mutation("hyper_focus") else 0.45
	var aim_factor := lerpf(1.0, ads_scale, _aim)
	var heat := maxf(_heat, _visual_heat)
	var base := data.spread_degrees + data.burst_spread * heat + _recoil * (1.8 if data.pellets > 1 else 1.1)
	var move_bloom := 0.0
	if player is CharacterBody3D:
		var body := player as CharacterBody3D
		var hspeed := Vector2(body.velocity.x, body.velocity.z).length()
		move_bloom = clampf(hspeed / 7.2, 0.0, 1.0) * (0.55 if data.pellets > 1 else 0.40)
		if not body.is_on_floor():
			move_bloom += 0.85
	if data.mechanic == "gust":
		return 10.5
	if data.mechanic == "wash":
		return maxf(base * aim_factor, 2.2)
	return maxf(0.0, (base + move_bloom * (1.0 - _aim * 0.72)) * aim_factor)

## Local throttled micro-popup beside the reticle when a special weapon effect triggers.
func notify_effect(text: String, color: Color, key := "", cooldown := 0.7) -> void:
	if Net.dedicated or not player.is_multiplayer_authority():
		return
	var now := Time.get_ticks_msec() / 1000.0
	var tag := key if not key.is_empty() else text
	if now < float(_effect_cooldowns.get(tag, 0.0)):
		return
	_effect_cooldowns[tag] = now + cooldown
	Juice.popup(text, color)

func can_act() -> bool:
	return loot != null and loot.run_id > 0 and player.state == "ok" and not GameManager.awaiting_tape_choice \
			and not GameManager.is_voting() and not get_tree().paused

func _process(delta: float) -> void:
	_cooldown = maxf(0.0, _cooldown - delta)
	_gesture_left = maxf(0.0, _gesture_left - delta)
	_throw_cooldown = maxf(0.0, _throw_cooldown - delta)
	_jam_left = maxf(0.0, _jam_left - delta)
	_pending_action = maxf(0.0, _pending_action - delta)
	_pouch_ack_left = maxf(0.0, _pouch_ack_left - delta)
	_harpoon_motion_left = maxf(0.0, _harpoon_motion_left - delta)
	if _reload_left > 0.0:
		_reload_left = maxf(0.0, _reload_left - delta)
		if _reload_left <= 0.0 and Net.is_host():
			_finish_reload()
	if Net.is_host():
		if not can_act():
			if _reload_serial != 0 or _charge_serial != 0:
				_cancel_actions()
				send_state(false)
		elif _cooldown <= 0.0 and _reload_serial == 0 and active_pouch.is_empty():
			var item := selected()
			if item and item.count == 0 and selected_weapon().mag_size == 1 and selected_reserve() > 0:
				_start_reload_host()
	if not player.is_multiplayer_authority() or Net.dedicated:
		if _remote_view:
			_remote_view.visible = player.state == "ok"
			var pulse := _gesture_weight()
			_remote_equip = move_toward(_remote_equip, 0.0, delta * 4)
			_remote_view.position.y = 1.12 - 0.18 * _remote_equip
			var style: String = _pose.PROFILES[equipped_id][0]
			_remote_view.rotation_degrees = _pose.gesture_angles(style) * pulse
			_remote_reload_left = maxf(0.0, _remote_reload_left - delta)
			var left := _reload_left if Net.is_host() else _remote_reload_left
			var total := _reload_total if Net.is_host() else _remote_reload_total
			_remote_view.rotation_degrees.z -= 38 * sin(PI * left / total)
		return
	_fire_buffer = maxf(0.0, _fire_buffer - delta)
	_raise_left = SPRINT_RAISE if player.is_sprinting else maxf(0.0, _raise_left - delta)
	_camera_kick = move_toward(_camera_kick, 0.0, delta * deg_to_rad(8.0))
	camera.rotation.x = _camera_kick
	_roll = move_toward(_roll, 0.0, delta * deg_to_rad(20.0))
	camera.rotation.z = _roll
	_recoil = move_toward(_recoil, 0.0, delta * 2.8)
	_kick = move_toward(_kick, 0.0, delta * 6.0)
	_visual_heat = move_toward(_visual_heat, 0.0, delta * 1.6)
	_handle_input()
	_publish()
	_animate(delta)
	_update_throw_preview(delta)

func _handle_input() -> void:
	var loadout_input := InventoryMenu.blocks_gameplay_actions()
	if loadout_input:
		_loadout_fire_blocked = Input.is_action_pressed("fire") or Input.is_action_just_released("fire")
	if not can_act() or loadout_input:
		_fire_buffer = 0.0
		_local_charging = false
		return
	var wheel := int(Input.is_action_just_pressed("weapon_next")) - int(Input.is_action_just_pressed("weapon_prev"))
	if wheel != 0:
		if not active_pouch.is_empty():
			select_slot(current)
		else:
			select_slot(posmod(current + wheel, SLOT_COUNT))
		return
	if not Input.is_action_pressed("fire"):
		_pouch_fire_latched = false
	var block_fire := _loadout_fire_blocked
	_loadout_fire_blocked = block_fire and Input.is_action_pressed("fire")
	if _pouch_ack_left > 0.0:
		if not block_fire and not _pending_pouch.is_empty() and Input.is_action_just_pressed("fire") and not player.tarp_raised:
			_fire_buffer = _pouch_ack_left
		return
	var data := selected_weapon()
	if data == null or player.tarp_raised:
		_local_charging = false
		return
	if Input.is_action_just_pressed("reload") and active_pouch.is_empty():
		start_reload()
	if block_fire:
		# A trigger pressed in loadout must return to neutral before firing or
		# releasing a charged shot in gameplay.
		return
	if not TouchInput.combat_pointer_active() and not _pad_connected():
		_fire_buffer = 0.0
		_local_charging = false
		return
	if not active_pouch.is_empty():
		_local_charging = false
		if Input.is_action_just_pressed("fire"):
			_fire_buffer = 0.25 + _raise_left
		if _fire_buffer > 0.0 and _cooldown <= 0.0 and _throw_cooldown <= 0.0 and _raise_left <= 0.0:
			_fire_buffer = 0.0
			if pouch_count(active_pouch) > 0:
				_throw_pouch(active_pouch)
			else:
				select_slot(current)
		return
	if data.charge_time > 0.0:
		if Input.is_action_just_pressed("fire"):
			if selected().count > 0 and _cooldown <= 0.0 and _reload_left <= 0.0:
				_local_charging = true
				_local_charge_at = Time.get_ticks_msec() / 1000.0
				_command("charge")
			elif selected_reserve() > 0 and _reload_left <= 0.0:
				start_reload()
		elif _local_charging and not Input.is_action_pressed("fire"):
			_local_charging = false
			fire()
		return
	_local_charging = false
	if Input.is_action_just_pressed("fire"):
		_fire_buffer = 0.15 + _raise_left
	var wants := not _pouch_fire_latched and (Input.is_action_pressed("fire") if data.automatic else _fire_buffer > 0.0)
	if wants:
		player.sprint_lock = 0.35
	if wants and _cooldown <= 0.0 and _pending_action <= 0.0 and _jam_left <= 0.0 and _raise_left <= 0.0:
		if selected().count > 0 and (_reload_left <= 0.0 or data.shell_reload):
			fire()
		elif data.mag_size != 1 and selected_reserve() > 0 and _reload_left <= 0.0:
			start_reload()

func cancel_touch_fire() -> void:
	_fire_buffer = 0.0
	_local_charging = false


func _unhandled_input(event: InputEvent) -> void:
	if Net.dedicated or not player.is_multiplayer_authority() or not can_act() or InventoryMenu.blocks_gameplay_actions():
		return
	for id: String in ItemCatalog.POUCH_ACTIONS:
		if event.is_action_pressed(ItemCatalog.POUCH_ACTIONS[id]):
			select_pouch(id)
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed("drop_item") and active_pouch.is_empty() and selected():
		_command("drop")
		get_viewport().set_input_as_handled()
		return
	for slot in SLOT_COUNT:
		if event.is_action_pressed("weapon_%d" % (slot + 1)):
			select_slot(slot)
			get_viewport().set_input_as_handled()
			return

## Equip a belt pouch item (Frag Grenade / Shield Dome) into hand to aim and throw with LMB.
func select_pouch(id: String) -> void:
	if not ItemCatalog.is_pouch(id) or not can_act() or not Net.can_send_run_rpc():
		return
	if pouch_count(id) <= 0:
		var definition := ItemCatalog.definition(id)
		var title := definition.display_name.to_upper() if definition else id.to_upper()
		notify_effect("NO %s" % title, Color("#ff9f6b"), "empty_pouch_" + id, 0.5)
		return
	var held := _pending_pouch if _pouch_ack_left > 0.0 else active_pouch
	var target := "" if held == id else id
	_fire_buffer = 0.0
	_local_charging = false
	if not Net.is_host():
		_pending_pouch = target
		_pouch_ack_left = 0.75
	_send_action("select_pouch", 0, POUCH_ORDER.find(target))

func find_touch_look_target(base_cone_deg := 6.2) -> Dictionary:
	if camera == null or not is_inside_tree():
		return {}
	return WeaponCombat.find_aim_assist_target(
		self, camera.global_position, -camera.global_basis.z,
		lerpf(base_cone_deg, base_cone_deg * 0.72, _aim), false
	)


func _assist_shot_dir(origin: Vector3, dir: Vector3) -> Vector3:
	var fwd := dir.normalized()
	if not (TouchInput.gameplay_active or TouchInput.enabled):
		return fwd
	var data := selected_weapon()
	if not active_pouch.is_empty() or data == null:
		return fwd
	var max_bend_deg := 3.8
	var item := selected()
	if data.pellets > 1 or data.mechanic in ["wash", "gust"]:
		max_bend_deg = 4.2
	elif (item != null and item.id == "hunting_rifle") or (_aim > 0.5 and not data.automatic and data.pellets == 1):
		max_bend_deg = 3.2
	var assist := WeaponCombat.find_aim_assist_target(self, origin, fwd, max_bend_deg + 1.5, data.mechanic == "reel")
	if assist.is_empty():
		return fwd
	var shot_point: Vector3 = assist["shot_point"]
	var want := (shot_point - origin).normalized()
	var theta := acos(clampf(fwd.dot(want), -1.0, 1.0))
	if theta <= 0.0001:
		return fwd
	var dist: float = float(assist["distance"])
	var weight: float = float(assist["weight"])
	var eff_deg := max_bend_deg * clampf((dist - 0.8) / 1.7, 0.4, 1.0)
	var max_bend := deg_to_rad(eff_deg)
	var limit := max_bend if theta <= max_bend else max_bend * smoothstep(0.0, 1.0, weight)
	var bend := minf(theta * 0.90, limit)
	var axis := fwd.cross(want)
	if axis.length_squared() <= 0.00000001 or bend <= 0.0:
		return fwd
	return fwd.rotated(axis.normalized(), bend).normalized()


func fire() -> void:
	if not Net.can_send_run_rpc() or not can_act() or _pouch_ack_left > 0.0:
		return
	if not active_pouch.is_empty():
		_throw_pouch(active_pouch)
		return
	if selected() == null:
		return
	_fire_buffer = 0.0
	var dir := _assist_shot_dir(camera.global_position, -camera.global_basis.z)
	if Net.is_host():
		_host_shot(loot.run_id, selected_serial(), camera.global_position, dir, _aim > 0.5, 0)
	else:
		_pending_action = 0.14
		var data := selected_weapon()
		var predict: bool = data.kind == WeaponData.Kind.HITSCAN and data.charge_time <= 0.0 \
			and data.jam_chance == 0.0 and not player.is_sprinting and not player.tarp_raised \
			and _cooldown <= 0.0 and _jam_left <= 0.0 and selected().count > 0 \
			and (_reload_left <= 0.0 or data.shell_reload)
		var ads := _aim > 0.5
		if predict:
			_start_gesture(selected().id)
			WeaponCombat.play_fx(loot, selected().id, _muzzle_position(), [], true)
			_local_shot_motion(selected().id, data, ads)
		_request_shot.rpc_id(1, loot.run_id, selected_serial(), camera.global_position, dir, ads, predict)

func _throw_pouch(id: String) -> void:
	if id != active_pouch or not Net.can_send_run_rpc() or not can_act() or player.tarp_raised \
			or _throw_cooldown > 0.0 or pouch_count(id) <= 0 or InventoryMenu.is_open():
		return
	if not TouchInput.combat_pointer_active() and not _pad_connected():
		return
	_pouch_fire_latched = Input.is_action_pressed("fire")
	_throw_cooldown = THROW_COOLDOWN
	var origin := camera.global_position
	var dir := -camera.global_basis.z
	if Net.is_host():
		_host_throw(loot.run_id, id, origin, dir, false)
	else:
		_play_throw(id, origin, dir)
		_request_throw.rpc_id(1, loot.run_id, id, origin, dir)

@rpc("any_peer", "call_remote", "reliable")
func _request_throw(run: int, id: String, origin: Vector3, dir: Vector3) -> void:
	if _valid_sender():
		_host_throw(run, id, origin, dir, true)

func _host_throw(run: int, id: String, origin: Vector3, dir: Vector3, predicted: bool) -> bool:
	if not Net.is_host() or not can_act() or run != loot.run_id or not ItemCatalog.is_pouch(id) \
			or id != active_pouch or player.tarp_raised or pouch_count(id) <= 0:
		return false
	# A little looser than the owner's cooldown so jittered packets still land.
	if loot.clock - _last_throw_at < THROW_COOLDOWN * 0.6:
		return false
	if not origin.is_finite() or not dir.is_finite() or dir.length_squared() < 0.5 \
			or origin.distance_to(camera.global_position) > 3.0 \
			or not WeaponCombat.clear_path(get_world_3d(), camera.global_position, origin):
		return false
	dir = dir.normalized()
	_last_throw_at = loot.clock
	_set_pouch(id, pouch_count(id) - 1)
	loot.launch(id, WeaponCombat.throw_origin(get_world_3d(), origin, dir), dir, ItemCatalog.STANDARD, player)
	_play_throw(id, origin, dir)
	Net.rpc_to_run(_throw_fx, [loot.run_id, id, origin, dir, predicted])
	var emptied := active_pouch == id and pouch_count(id) <= 0
	if emptied:
		active_pouch = ""
	send_state(emptied)
	return true

@rpc("any_peer", "call_remote", "unreliable_ordered")
func _throw_fx(run: int, id: String, origin: Vector3, dir: Vector3, predicted: bool) -> void:
	if multiplayer.get_remote_sender_id() != 1 or run != loot.run_id:
		return
	if predicted and player.is_multiplayer_authority():
		return
	_play_throw(id, origin, dir)

func _play_throw(id: String, origin: Vector3, dir: Vector3) -> void:
	if Net.dedicated or not ItemCatalog.is_pouch(id):
		return
	var local := player.is_multiplayer_authority()
	_start_gesture(id)
	WeaponCombat.play_fx(loot, id, origin + dir * 0.45, [], local)
	if local:
		_kick = maxf(_kick, 0.45)
		_camera_kick = minf(_camera_kick + deg_to_rad(0.8), deg_to_rad(5.0))
		thrown.emit(id)

func pouch_count(id: String) -> int:
	match id:
		"frag":
			return grenades
		"shield_dome":
			return domes
	return 0

func pouch_full(id: String) -> bool:
	return ItemCatalog.is_pouch(id) and pouch_count(id) >= ItemCatalog.pouch_cap(id)

## Adds up to the pouch cap and returns how many did not fit.
func add_pouch(id: String, amount: int) -> int:
	if not ItemCatalog.is_pouch(id) or amount <= 0:
		return maxi(amount, 0)
	var fit := clampi(ItemCatalog.pouch_cap(id) - pouch_count(id), 0, amount)
	_set_pouch(id, pouch_count(id) + fit)
	return amount - fit

func _set_pouch(id: String, value: int) -> void:
	value = clampi(value, 0, ItemCatalog.pouch_cap(id))
	match id:
		"frag":
			grenades = value
		"shield_dome":
			domes = value

## Host: tell the owner a pouch pickup was refused because it is full.
func notify_pouch_full(id: String) -> void:
	if not Net.is_host():
		return
	var peer := player.get_multiplayer_authority()
	if peer == 1:
		if not Net.dedicated:
			_show_pouch_full(id)
	elif Net.run_peers.has(peer):
		_pouch_full_feedback.rpc_id(peer, loot.run_id, id)

@rpc("any_peer", "call_remote", "reliable")
func _pouch_full_feedback(run: int, id: String) -> void:
	if multiplayer.get_remote_sender_id() == 1 and run == loot.run_id:
		_show_pouch_full(id)

func _show_pouch_full(id: String) -> void:
	var definition := ItemCatalog.definition(id)
	if definition:
		Juice.popup("%s POUCH FULL" % definition.display_name.to_upper(), Color("#ff9f6b"))

func start_reload() -> void:
	_command("reload")

func select_slot(slot: int) -> void:
	if _pouch_ack_left > 0.0:
		_pending_pouch = ""
		_fire_buffer = 0.0
	_command("select", slot)

func _command(action: String, slot := -1) -> void:
	_send_action(action, selected_serial(), slot)

## Move or swap two hotbar slots (an empty target is a plain move). Matching
## non-gun stacks of the same tier merge up to the stack cap instead.
func swap_slots(from_slot: int, to_slot: int) -> void:
	if from_slot < 0 or from_slot >= SLOT_COUNT or to_slot < 0 or to_slot >= SLOT_COUNT \
			or from_slot == to_slot or slots[from_slot] == null:
		return
	# Rides the existing _action RPC (slot packs both indices) so the RPC
	# table and Net.PROTOCOL stay unchanged.
	_send_action("swap", slots[from_slot].serial, from_slot * SLOT_COUNT + to_slot)

## Drop whatever is in `slot` (not just the held one) in front of the player.
func drop_slot(slot: int) -> void:
	if slot < 0 or slot >= SLOT_COUNT or slots[slot] == null:
		return
	_send_action("drop_slot", slots[slot].serial, slot)

func _send_action(action: String, expected: int, slot: int) -> void:
	if not can_act():
		return
	if Net.is_host():
		_host_action(loot.run_id, action, expected, slot)
	else:
		_action.rpc_id(1, loot.run_id, action, expected, slot)

func _valid_sender() -> bool:
	var sender := multiplayer.get_remote_sender_id()
	return Net.is_host() and sender == player.get_multiplayer_authority() and Net.run_peers.has(sender)

@rpc("any_peer", "call_remote", "reliable")
func _action(run: int, action: String, expected: int, slot: int) -> void:
	if _valid_sender():
		_host_action(run, action, expected, slot)

func _host_action(run: int, action: String, expected: int, slot: int) -> void:
	if not can_act() or run != loot.run_id:
		return
	if action == "select" and slot >= 0 and slot < SLOT_COUNT and (slot != current or not active_pouch.is_empty()):
		_cancel_actions()
		active_pouch = ""
		current = slot
		_cooldown = maxf(_cooldown, 0.22)
		_heat = 0.0
		send_state()
		return
	if action == "select_pouch":
		if slot < -1 or slot >= POUCH_ORDER.size():
			return
		var id: String = POUCH_ORDER[slot] if slot >= 0 else ""
		if active_pouch == id or (not id.is_empty() and pouch_count(id) <= 0):
			return
		_cancel_actions()
		active_pouch = id
		_cooldown = maxf(_cooldown, 0.18)
		_heat = 0.0
		send_state()
		return
	if action == "swap":
		_host_swap(expected, slot)
		return
	if action == "drop_slot":
		_host_drop_slot(expected, slot)
		return
	if not active_pouch.is_empty():
		return
	if expected == 0 or expected != selected_serial():
		return
	match action:
		"reload":
			_start_reload_host()
		"drop":
			var forward := -player.global_basis.z
			var at := loot.ground_at(player, forward * 1.1)
			if at == Vector3.INF:
				at = loot.ground_at(player, Vector3.ZERO)
			if at.is_finite() and loot.spawn_pickup(selected(), at) != 0:
				slots[current] = null
				_cancel_actions()
				send_state()
		"charge":
			if selected_weapon().charge_time > 0.0 and _cooldown <= 0.0 and _reload_serial == 0 \
					and selected().count > 0 and not player.tarp_raised and _charge_serial == 0:
				_charge_serial = expected
				_charge_at = loot.clock
				_play_charge(loot.run_id, expected)
				if not player.is_multiplayer_authority():
					_play_charge.rpc_id(player.get_multiplayer_authority(), loot.run_id, expected)

## Host: `packed` is from * SLOT_COUNT + to; `expected` is the moved item's serial.
func _host_swap(expected: int, packed: int) -> void:
	if packed < 0 or packed >= SLOT_COUNT * SLOT_COUNT:
		return
	@warning_ignore("integer_division")
	var from_slot := packed / SLOT_COUNT
	var to_slot := packed % SLOT_COUNT
	var moving := slots[from_slot]
	if from_slot == to_slot or moving == null or expected == 0 or moving.serial != expected:
		return
	var held := selected_serial()
	var target := slots[to_slot]
	var definition := ItemCatalog.definition(moving.id)
	var merged := false
	if target and definition and definition.kind != ItemDefinition.Kind.GUN \
			and target.id == moving.id and target.tier == moving.tier:
		var room := mini(moving.count, definition.stack_cap - target.count)
		if room > 0:
			target.count += room
			moving.count -= room
			if moving.count <= 0:
				slots[from_slot] = null
			merged = true
	if not merged:
		slots[from_slot] = target
		slots[to_slot] = moving
		# The held item stays in hand wherever it went.
		if current == from_slot:
			current = to_slot
		elif current == to_slot:
			current = from_slot
	elif slots[from_slot] == null and current == from_slot:
		current = to_slot
	if selected_serial() != held:
		_cancel_actions()
		_cooldown = maxf(_cooldown, 0.25)
		_heat = 0.0
	send_state(true)

## Host: drop the item in `slot` if it is still the one the owner saw.
func _host_drop_slot(expected: int, slot: int) -> void:
	if slot < 0 or slot >= SLOT_COUNT:
		return
	var item := slots[slot]
	if item == null or expected == 0 or item.serial != expected:
		return
	var forward := -player.global_basis.z
	var at := loot.ground_at(player, forward * 1.1)
	if at == Vector3.INF:
		at = loot.ground_at(player, Vector3.ZERO)
	if at.is_finite() and loot.spawn_pickup(item, at) != 0:
		slots[slot] = null
		if slot == current:
			_cancel_actions()
		send_state(true)

@rpc("any_peer", "call_remote", "reliable")
func _play_charge(run: int, serial: int) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if (sender == 1 or (sender == 0 and Net.is_host())) and run == loot.run_id \
			and selected_serial() == serial and player.is_multiplayer_authority():
		Sound.play("gun_disruptor_charge", -8.0)

func _cancel_actions() -> void:
	_reload_left = 0.0
	_reload_serial = 0
	_charge_serial = 0
	_local_charging = false
	_fire_buffer = 0.0

func _start_reload_host() -> void:
	var definition := selected_definition()
	if definition == null or definition.kind != ItemDefinition.Kind.GUN or _reload_serial != 0 \
			or selected().count >= definition.weapon.mag_size or selected_reserve() <= 0 or player.tarp_raised:
		return
	_charge_serial = 0
	_reload_serial = selected_serial()
	_reload_total = definition.weapon.reload_time * GameManager.reload_scale()
	_reload_left = _reload_total
	send_state(false)
	if player.is_multiplayer_authority():
		_reload_sound(definition.weapon)

func _finish_reload() -> void:
	var item := selected()
	if not can_act() or item == null or _reload_serial != item.serial:
		_cancel_actions()
		send_state(false)
		return
	var definition := selected_definition()
	var data := definition.weapon
	var take := mini(1 if data.shell_reload else data.mag_size - item.count, selected_reserve())
	item.count += take
	reserves[definition.ammo_type] = selected_reserve() - take
	_reload_serial = 0
	if data.shell_reload and item.count < data.mag_size and selected_reserve() > 0:
		_start_reload_host()
	else:
		send_state(false)
		if data.shell_reload and player.is_multiplayer_authority():
			Sound.play("shotgun_pump", -8.0)
			_kick = 0.6

func _reload_sound(data: WeaponData) -> void:
	if data.mechanic == "reel":
		Sound.play("lever", -11.0, 0.83)
		return
	var cue := "reel_tick" if data.shell_reload else ("rifle_reload" if data.automatic else "reload")
	Sound.play(cue, -12.0 if data.shell_reload else -8.0)

@rpc("any_peer", "call_remote", "reliable")
func _request_shot(run: int, serial: int, origin: Vector3, dir: Vector3, is_aiming: bool, predicted: bool) -> void:
	if _valid_sender():
		_host_shot(run, serial, origin, dir, is_aiming, Net.get_rewind_ms(multiplayer.get_remote_sender_id()), predicted)

func _host_shot(run: int, serial: int, origin: Vector3, dir: Vector3, is_aiming: bool, rewind_ms: int, predicted := false) -> bool:
	if not Net.is_host() or not can_act() or run != loot.run_id or serial == 0 or selected_serial() != serial \
			or not active_pouch.is_empty() or player.tarp_raised or player.is_sprinting or _cooldown > 0.0:
		return false
	if not origin.is_finite() or not dir.is_finite() or dir.length_squared() < 0.5 \
			or origin.distance_to(camera.global_position) > 3.0 \
			or not WeaponCombat.clear_path(get_world_3d(), camera.global_position, origin):
		return false
	var item := selected()
	var definition := selected_definition()
	var data := definition.weapon
	if item.count <= 0 or loot.clock < item.jam_until or (_reload_serial != 0 and not data.shell_reload):
		return false
	if data.charge_time > 0.0:
		var charged := _charge_serial == serial and loot.clock - _charge_at >= data.charge_time
		_charge_serial = 0
		if not charged:
			return false
	dir = dir.normalized()
	if not WeaponCombat.can_use(self, item.id, dir):
		return false
	_cancel_actions()
	item.count -= 1
	_cooldown = data.fire_interval * GameManager.fire_rate_scale()
	if data.jam_chance > 0.0 and RNG.chance(data.jam_chance):
		item.jam_until = loot.clock + data.jam_time
		_apply_jam()
		if not player.is_multiplayer_authority():
			_jam.rpc_id(player.get_multiplayer_authority(), loot.run_id)
		send_state(false)
		return true
	_heat = move_toward(_heat, 0.0, maxf(0.0, loot.clock - _spread_at) * 1.6)
	_spread_at = loot.clock
	var ads_scale := 0.25 if GameManager.has_player_mutation("hyper_focus") else 0.45
	var spread := (data.spread_degrees + data.burst_spread * _heat) * (ads_scale if is_aiming else 1.0)
	_heat = minf(1.0, _heat + 0.22)
	var seed := RNG.rng.randi()
	var lucky := data.lucky_kill_chance > 0.0 and RNG.chance(data.lucky_kill_chance)
	_shot_counter += 1
	player.begin_hit_batch()
	var traces := WeaponCombat.resolve(self, item, origin, dir, seed, spread, is_aiming, lucky, rewind_ms)
	player.end_hit_batch()
	_play_shot(item.id, origin, dir, traces, is_aiming)
	Net.rpc_to_run(_shot_fx, [loot.run_id, item.id, origin, dir, traces, is_aiming, predicted])
	var emptied := item.count == 0 and definition.ammo_type.is_empty()
	if emptied:
		slots[current] = null
	send_state(emptied)
	return true

@rpc("any_peer", "call_remote", "reliable")
func _jam(run: int) -> void:
	if multiplayer.get_remote_sender_id() == 1 and run == loot.run_id:
		_apply_jam()

func _apply_jam() -> void:
	if player.is_multiplayer_authority() and not Net.dedicated:
		Sound.play("jam")
		notify_effect("JAMMED! (2S)", BroadcastUI.PINK, "jam", 0.4)

@rpc("any_peer", "call_remote", "unreliable_ordered")
func _shot_fx(run: int, id: String, origin: Vector3, dir: Vector3, traces: Array, ads: bool, predicted: bool) -> void:
	if multiplayer.get_remote_sender_id() == 1 and run == loot.run_id:
		_play_shot(id, origin, dir, traces, ads, predicted)

func _play_shot(id: String, origin: Vector3, dir: Vector3, traces: Array, ads: bool, predicted := false) -> void:
	if Net.dedicated:
		return
	var local := player.is_multiplayer_authority()
	var data := ItemCatalog.definition(id).weapon
	var muzzle := _muzzle_position() if local and equipped_id == id else origin + dir * 0.55
	var muzzle_model: Node3D
	if data.mechanic == "reel" and equipped_id == id:
		muzzle_model = _model if local else _remote_view
		if is_instance_valid(muzzle_model) and muzzle_model.is_inside_tree():
			muzzle = muzzle_model.to_global(ItemModels.muzzle(id))
	if not (local and predicted):
		_start_gesture(id)
	WeaponCombat.play_fx(loot, id, muzzle, traces, local, not (local and predicted), muzzle_model)
	if not local:
		return
	_pending_action = 0.0
	if not predicted:
		_local_shot_motion(id, data, ads)
	elif data.mechanic == "reel" and equipped_id == id:
		# Retraction follows the confirmed bolt even when prediction ran earlier.
		_harpoon_motion_left = ShotFX.HARPOON_DURATION


func _local_shot_motion(id: String, data: WeaponData, ads: bool) -> void:
	_cooldown = data.fire_interval * GameManager.fire_rate_scale()
	_kick = 1.0
	_local_charging = false
	_visual_heat = minf(1.0, _visual_heat + 0.24)
	var heavy := data.pellets > 1 or data.mechanic == "reel"
	_recoil = minf(_recoil + (0.28 if heavy else 0.10), 0.55)
	if data.mechanic == "reel" and equipped_id == id:
		_harpoon_motion_left = ShotFX.HARPOON_DURATION
	var recoil_scale := (0.50 if GameManager.has_player_mutation("hyper_focus") else 0.65) if ads else 1.0
	_camera_kick = minf(_camera_kick + deg_to_rad(data.recoil_degrees) * recoil_scale, deg_to_rad(5.0))
	_shot_juice(data)
	fired.emit(data)
	if id == "pump_shotgun":
		get_tree().create_timer(_cooldown * 0.2).timeout.connect(func():
			if equipped_id == id:
				Sound.play("shotgun_pump", -11.0))

func _stack_slot(item: ItemInstance) -> int:
	var definition := ItemCatalog.definition(item.id)
	if definition.kind != ItemDefinition.Kind.GUN:
		for index in SLOT_COUNT:
			var other := slots[index]
			if other and other.id == item.id and other.tier == item.tier and other.count + item.count <= definition.stack_cap:
				return index
	return -1

func needs_swap(item: ItemInstance) -> bool:
	if ItemCatalog.is_pouch(item.id):
		return false
	return not slots.has(null) and _stack_slot(item) == -1

## Returns the displaced item, null on placement/stack, or the original on rejection.
## Pouch items (frag / shield_dome) never touch the slots: they fill the pouch
## up to its cap. With return_overflow, whatever did not fit comes back (the
## same instance with a reduced count, or unchanged when nothing fit). Without
## it, the overflow is dropped at the player's feet and null is returned, so
## callers that only expect displaced slot items (vending) never lose it.
func accept_pickup(item: ItemInstance, return_overflow := false) -> ItemInstance:
	if ItemCatalog.is_pouch(item.id):
		var left := add_pouch(item.id, item.count)
		if left <= 0:
			return null
		item.count = left
		if return_overflow:
			return item
		_drop_near(item)
		return null
	var stack := _stack_slot(item)
	if stack >= 0:
		slots[stack].count += item.count
		return null
	var index := slots.find(null)
	if index < 0:
		index = current
	var replaced := slots[index]
	slots[index] = item
	var definition := ItemCatalog.definition(item.id)
	if definition and definition.kind == ItemDefinition.Kind.GUN and not definition.ammo_type.is_empty() and not _seeded_ammo.has(definition.ammo_type):
		_seeded_ammo[definition.ammo_type] = true
		var cap: int = int(ItemCatalog.CAPS[definition.ammo_type])
		var starter: int = mini(cap, maxi(definition.weapon.mag_size * 2, int(cap * 0.5)))
		reserves[definition.ammo_type] = mini(cap, maxi(int(reserves.get(definition.ammo_type, 0)), starter))
	if index == current:
		_cancel_actions()
	return replaced

func spill() -> void:
	if not Net.is_host() or loot == null:
		return
	_cancel_actions()
	for i in SLOT_COUNT:
		var item := slots[i]
		if item == null:
			continue
		slots[i] = null
		var at := loot.ground_at(player, Vector3.FORWARD.rotated(Vector3.UP, i * TAU / SLOT_COUNT) * 0.9)
		if at == Vector3.INF:
			at = loot.ground_at(player, Vector3.ZERO)
		if at == Vector3.INF:
			at = player.global_position
		loot.spawn_pickup(item, at)
	var spot := 0
	for id: String in ItemCatalog.POUCH_CAPS:
		var count := pouch_count(id)
		if count <= 0:
			continue
		_set_pouch(id, 0)
		var pouch := loot.make_item(id)
		if pouch == null:
			continue
		pouch.count = count
		var at := loot.ground_at(player, Vector3.BACK.rotated(Vector3.UP, (spot + 0.5) * TAU / SLOT_COUNT) * 0.6)
		spot += 1
		if at == Vector3.INF:
			at = loot.ground_at(player, Vector3.ZERO)
		if at == Vector3.INF:
			at = player.global_position
		loot.spawn_pickup(pouch, at)

## Host: put an item on the ground just in front of the player.
func _drop_near(item: ItemInstance) -> void:
	if not Net.is_host() or loot == null:
		return
	var at := loot.ground_at(player, -player.global_basis.z * 1.1)
	if at == Vector3.INF:
		at = loot.ground_at(player, Vector3.ZERO)
	if at == Vector3.INF:
		at = player.global_position
	loot.spawn_pickup(item, at)

func can_collect_ammo() -> bool:
	for type: String in _carried_types():
		if int(reserves.get(type, 0)) < int(ItemCatalog.CAPS[type]):
			return true
	return false

func _carried_types() -> Dictionary:
	var types: Dictionary = {}
	for item in slots:
		if item:
			var definition := ItemCatalog.definition(item.id)
			if not definition.ammo_type.is_empty():
				types[definition.ammo_type] = maxi(int(types.get(definition.ammo_type, 0)), definition.weapon.mag_size)
	return types

func collect_ammo(full := false) -> bool:
	if not Net.is_host():
		return false
	var collected := false
	var types := _carried_types()
	for type: String in types:
		var old := int(reserves.get(type, 0))
		var amount := maxi(1, roundi(types[type] * GameManager.ammo_pickup_fraction()))
		var cap: int = ItemCatalog.CAPS[type]
		var total := cap if full else mini(old + amount, cap)
		if total > old:
			reserves[type] = total
			collected = true
	if collected:
		send_state(false)
	return collected

func earn_scrap(amount: int) -> void:
	if not Net.is_host():
		return
	scrap += amount
	send_state(false)
	var peer := player.get_multiplayer_authority()
	if peer == 1:
		if not Net.dedicated:
			_show_scrap(amount)
	elif Net.run_peers.has(peer):
		_scrap_feedback.rpc_id(peer, loot.run_id, amount)

@rpc("any_peer", "call_remote", "reliable")
func _scrap_feedback(run: int, amount: int) -> void:
	if multiplayer.get_remote_sender_id() == 1 and run == loot.run_id:
		_show_scrap(amount)

func _show_scrap(amount: int) -> void:
	Juice.popup("+%d SCRAP" % amount, Color("#ffc365"))

func spend_scrap(amount: int) -> bool:
	if not Net.is_host() or amount < 0 or scrap < amount:
		return false
	scrap -= amount
	send_state(false)
	return true

func send_state(update_public := true) -> void:
	if not Net.is_host() or loot == null:
		return
	revision += 1
	if update_public:
		_refresh_equip()
	if update_public or _reload_left > 0 or _public_reloading:
		_public_reloading = _reload_left > 0
		Net.rpc_to_run(_equip_state, [loot.run_id, revision, equipped_id, equipped_tier, _reload_left, _reload_total])
	var item := selected()
	_jam_left = maxf(0.0, item.jam_until - loot.clock) if item else 0.0
	var peer := player.get_multiplayer_authority()
	if peer != 1 and Net.run_peers.has(peer):
		sync_private_to(peer)

func sync_private_to(peer: int) -> void:
	var rows: Array = []
	for item in slots:
		rows.append(item.encode() if item else [])
	_private_state.rpc_id(peer, loot.run_id, revision, rows, reserves, current, active_pouch, scrap, grenades, domes, _reload_left, _reload_total, _jam_left, _cooldown)

func sync_equip_to(peer: int) -> void:
	_equip_state.rpc_id(peer, loot.run_id, revision, equipped_id, equipped_tier, _reload_left, _reload_total)

@rpc("any_peer", "call_remote", "reliable")
func _private_state(run: int, rev: int, rows: Array, stash: Dictionary, slot: int, pouch: String, new_scrap: int, frags: int, shield_domes: int, reload_left: float, reload_total: float, jam_left: float, cooldown: float) -> void:
	if multiplayer.get_remote_sender_id() != 1 or run != loot.run_id or rev <= _private_revision or not player.is_multiplayer_authority():
		return
	_private_revision = rev
	var old_serial := selected_serial()
	var old_reload := _reload_left
	for i in SLOT_COUNT:
		slots[i] = ItemInstance.decode(rows[i])
	reserves = stash
	current = slot
	active_pouch = pouch
	if _pouch_ack_left > 0.0 and active_pouch == _pending_pouch:
		_pouch_ack_left = 0.0
		if _fire_buffer > 0.0:
			_fire_buffer = 0.25 + _raise_left
	scrap = new_scrap
	grenades = frags
	domes = shield_domes
	_reload_left = reload_left
	_reload_total = reload_total
	_jam_left = jam_left
	_cooldown = cooldown
	_refresh_equip()
	if reload_left > 0.0 and (old_reload < reload_left or old_serial != selected_serial()):
		_reload_sound(selected_weapon())

@rpc("any_peer", "call_remote", "reliable")
func _equip_state(run: int, rev: int, id: String, tier: int, left: float, total: float) -> void:
	if multiplayer.get_remote_sender_id() != 1 or run != loot.run_id or rev <= _public_revision:
		return
	_public_revision = rev
	_remote_reload_left = left
	_remote_reload_total = total
	if not player.is_multiplayer_authority():
		_apply_equip(id, tier)

func _refresh_equip() -> void:
	if not active_pouch.is_empty() and pouch_count(active_pouch) <= 0:
		active_pouch = ""
	if not active_pouch.is_empty():
		_apply_equip(active_pouch, 0)
		var pouch_serial := -(POUCH_ORDER.find(active_pouch) + 10)
		if player.is_multiplayer_authority() and _model_serial != pouch_serial:
			_model_serial = pouch_serial
			_harpoon_motion_left = 0.0
			_equip_left = 1.0
			_aim = 0.0
		return
	var item := selected()
	_apply_equip(item.id if item else "", item.tier if item else 0)
	if player.is_multiplayer_authority() and _model_serial != selected_serial():
		_model_serial = selected_serial()
		_harpoon_motion_left = 0.0
		_equip_left = 1.0
		_aim = 0.0

func _apply_equip(id: String, tier: int) -> void:
	var changed := equipped_id != id or equipped_tier != tier
	var previous := equipped_id
	equipped_id = id
	equipped_tier = tier
	var definition := ItemCatalog.definition(id)
	player.holding_leaky = definition != null and definition.weapon.held_suit_drain > 0.0
	if player.holding_leaky:
		player.leaky_drain = definition.weapon.held_suit_drain
	if not changed or Net.dedicated:
		return
	if _model:
		if _gesture_left > 0 and (ItemCatalog.STACKS.has(previous) or previous == "flare_launcher"):
			var outgoing := _model
			if previous == "flare_launcher":
				_pose.show_rounds(0)
			var retire := outgoing.create_tween()
			retire.tween_property(outgoing, "rotation:x", outgoing.rotation.x + 0.30, 0.07)
			retire.tween_property(outgoing, "position:y", outgoing.position.y - 0.22, 0.14)
			retire.tween_callback(outgoing.queue_free)
		else:
			_model.hide()
			_model.queue_free()
		_gesture_left = 0.0
		_model = null
	if _remote_view:
		_remote_view.hide()
		_remote_view.queue_free()
		_remote_view = null
	_sight_point = Vector3.INF
	if definition != null:
		if player.is_multiplayer_authority():
			_model = ItemCatalog.model(id)
			add_child(_model)
			_pose.bind(_model, id)
			var spear := _model.get_node_or_null("Harpoon") as Node3D
			if spear:
				spear.set_meta("loaded_z", spear.position.z)
			_model.set_meta("base_scale", _model.scale)
			if _model is GeometryInstance3D:
				_model.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			for mesh: MeshInstance3D in _model.find_children("*", "MeshInstance3D", true, false):
				mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_sight_point = _model.get_meta("sight", Vector3.INF)
		else:
			_remote_equip = 1.0
			_remote_view = ItemCatalog.model(id, true)
			player.add_child.call_deferred(_remote_view)
			_remote_view.position = Vector3(0.34, 1.12, -0.47)
	weapon_changed.emit(definition.weapon if definition else null)

func _publish() -> void:
	var data := selected_weapon()
	player.weapon_name = data.display_name + (" (JAMMED)" if jammed() else (" (reloading)" if _reload_left > 0.0 else "")) if data else null
	player.ammo = active_count() if data else null
	player.max_ammo = selected_reserve() if data else null

func _pad_connected() -> bool:
	return not Input.get_connected_joypads().is_empty()

var _roll := 0.0
var _sprint_fov := 0.0
static var _casing_mesh: BoxMesh
static var _casing_mat: StandardMaterial3D
var _casings: Array[Node3D] = []


## Local shot feel: camera roll and shake, with smoke and brass on firearms.
func _shot_juice(data: WeaponData) -> void:
	if data.mechanic == "reel":
		_roll += deg_to_rad(1.65)
		Juice.shake(0.36)
		return
	if data.kind != WeaponData.Kind.HITSCAN or _model == null or OS.has_feature("web") or not data.mechanic in ["", "pin", "hunt", "salt"]:
		return
	var heavy := data.pellets > 1
	_roll += deg_to_rad(randf_range(1.2, 2.2) if heavy else randf_range(0.2, 0.5)) * (1 if randf() < 0.5 else -1)
	Juice.shake(0.28 if heavy else 0.05)
	var muzzle := _muzzle_position()
	# The view-model muzzle is ~0.5 m from the eye: keep the wisp small, faint
	# and a little ahead of it or it fills a third of the screen.
	ShotFX.puff(player.get_parent(), muzzle + (-camera.global_basis.z) * 0.35 + Vector3.UP * 0.03, Color(0.75, 0.75, 0.72, 0.16), 0.022 if not heavy else 0.04, 0.45)
	_eject_casing(heavy)


func _eject_casing(heavy: bool) -> void:
	if _casing_mesh == null:
		_casing_mesh = BoxMesh.new()
		_casing_mesh.size = Vector3(0.012, 0.012, 0.03)
		_casing_mat = StandardMaterial3D.new()
		_casing_mat.albedo_color = Color("#c9a24a") if not heavy else Color("#b8322a")
		_casing_mat.metallic = 0.8
		_casing_mat.roughness = 0.3
	var casing := MeshInstance3D.new()
	casing.mesh = _casing_mesh
	casing.material_override = _casing_mat
	casing.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var world := loot
	world.add_child(casing)
	var start := _model.global_transform * Vector3(0.03, 0.03, -0.05)
	casing.global_position = start
	var side := camera.global_basis.x
	var land := player.global_position + side * randf_range(0.5, 0.9) + (-camera.global_basis.z) * randf_range(-0.1, 0.3) + Vector3.UP * 0.02
	var peak := start + side * 0.25 + Vector3.UP * 0.25
	var tween := casing.create_tween()
	tween.set_parallel(true)
	tween.tween_property(casing, "global_position", peak, 0.12).set_ease(Tween.EASE_OUT)
	tween.tween_property(casing, "rotation", Vector3(randf() * 9, randf() * 9, randf() * 9), 0.5)
	tween.chain().tween_property(casing, "global_position", land, 0.3).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tween.chain().tween_callback(func(): Sound.play_at("casing_%d" % randi_range(0, 2), land, -20.0, randf_range(0.9, 1.15)))
	tween.chain().tween_interval(4.0)
	tween.chain().tween_callback(casing.queue_free)
	_casings.append(casing)
	_casings = _casings.filter(func(c): return is_instance_valid(c))
	while _casings.size() > 20:
		_casings.pop_front().queue_free()


func _animate(delta: float) -> void:
	var data := selected_weapon()
	if _model == null or data == null:
		return
	# Only the owning player aims down sights; Input on this machine says
	# nothing about anyone else's.
	var aiming: bool = can_act() and not player.get("tarp_raised") \
			and _reload_left <= 0.0 and not InventoryMenu.is_open() \
			and (TouchInput.combat_pointer_active() or _pad_connected()) and Input.is_action_pressed("aim")
	if player.is_multiplayer_authority():
		player.set("aiming", aiming)
	_aim = lerpf(_aim, 1.0 if aiming else 0.0, 1.0 - exp(-14.0 * delta))
	# Sprinting widens the view a little for a sense of speed.
	_sprint_fov = lerpf(_sprint_fov, 6.0 if player.get("is_sprinting") else 0.0, 1.0 - exp(-6.0 * delta))
	camera.fov = lerpf(_hip_fov + _sprint_fov, data.ads_fov, _aim)
	var speed := 0.0
	if player is CharacterBody3D:
		speed = Vector2(player.velocity.x, player.velocity.z).length()
	_bob += delta * speed * 1.6
	var bob := Vector3(sin(_bob) * 0.012, absf(cos(_bob)) * 0.014, 0.0) * minf(speed, 6.0) / 6.0
	_equip_left = move_toward(_equip_left, 0.0, delta * 4.0)
	var reload_dip := 0.0
	var reload_roll := 0.0
	var reload_push := 0.0
	var reload_progress := 0.0
	if _reload_left > 0.0:
		var t := clampf(1.0 - _reload_left / maxf(_reload_total, 0.01), 0.0, 1.0)
		reload_progress = t
		if data.shell_reload:
			# Shell by shell: rolled to the side, a thumb-push bump per shell.
			reload_dip = 0.35
			reload_roll = 28.0
			reload_push = sin(t * PI) * 0.05
		elif data.kind == WeaponData.Kind.FLARE:
			# Break action: barrel tips down, then snaps shut at the end.
			reload_dip = 1.25 * sin(minf(t / 0.8, 1.0) * PI * 0.5) * (1.0 if t < 0.85 else (1.0 - t) / 0.15)
		elif data.mechanic == "reel":
			reload_dip = 0.42 * sin(PI * t)
			reload_roll = 15.0 * sin(PI * t)
		else:
			# Mag swap: tilt and drop, then a sharp bolt rack near the end.
			reload_dip = sin(minf(t / 0.75, 1.0) * PI) * 0.8
			reload_roll = -32.0 * sin(minf(t / 0.75, 1.0) * PI)
			if t > 0.8:
				reload_push = sin((t - 0.8) / 0.2 * PI) * 0.07
	var lowered := _raise_left / SPRINT_RAISE
	_model.position = data.view_position.lerp(_ads_position(data), _aim) + bob * (1.0 - _aim * 0.85) + Vector3(0, -0.12 * reload_dip - .35 * _equip_left - 0.06 * lowered, 0.08 * _kick + reload_push)
	_model.rotation_degrees = data.view_rotation_degrees + Vector3(6.0 * _kick + _recoil * 8.0 - 35.0 * reload_dip - 14.0 * lowered, 12.0 * lowered, sin(_bob) * _kick * 1.5 + reload_roll)
	_model.scale = (_model.get_meta("base_scale", Vector3.ONE) as Vector3) * data.view_scale
	# Moving parts on the custom models.
	var pump := _model.get_node_or_null("Pump") as Node3D
	if pump:
		# Rack the forend back and forward in the middle of the pump delay.
		var since := 1.0 - clampf(_cooldown / maxf(data.fire_interval, 0.01), 0.0, 1.0)
		pump.position.z = 0.055 * sin(clampf((since - 0.15) / 0.6, 0.0, 1.0) * PI)
	var barrel := _model.get_node_or_null("Barrel") as Node3D
	if barrel and data.kind == WeaponData.Kind.FLARE:
		# Break action: the barrel tips open for the reload.
		barrel.rotation.x = -deg_to_rad(42.0) * clampf(reload_dip / 1.25, 0.0, 1.0)
	if data.mechanic == "reel":
		var spool := _model.get_node("Spool") as Node3D
		var spear := _model.get_node("Harpoon") as Node3D
		var seating := smoothstep(0.65, 1.0, reload_progress)
		var loaded := selected().count > 0 and _harpoon_motion_left <= 0.0
		spear.visible = loaded or reload_progress > 0.65
		spear.position.z = float(spear.get_meta("loaded_z")) + (0.24 * (1.0 - seating) if not loaded else 0.0)
		if _harpoon_motion_left > ShotFX.HARPOON_HOLD + ShotFX.HARPOON_REEL:
			spool.rotate_x(-38.0 * delta)
		elif _harpoon_motion_left > 0.0 and _harpoon_motion_left <= ShotFX.HARPOON_REEL:
			spool.rotate_x(31.0 * delta)
		elif _reload_left > 0.0:
			spool.rotate_x(8.0 * delta)
	if equipped_id == "flare_launcher":
		_pose.show_rounds(active_count())
	_model.rotation_degrees += _pose.equip_angles() * _equip_left
	_pose.pose(_model, reload_progress, _gesture_weight(), charge_progress(), delta)


func _gesture_weight() -> float:
	return sin(PI * _gesture_left / _gesture_duration)

func _start_gesture(id: String) -> void:
	if equipped_id == id:
		_gesture_duration = clampf(ItemCatalog.definition(id).weapon.fire_interval, 0.12, 0.5)
		_gesture_left = _gesture_duration

func _build_preview() -> void:
	_arc_material = StandardMaterial3D.new()
	_arc_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_arc_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_arc_material.disable_fog = true
	_arc_material.no_depth_test = false
	var dot := SphereMesh.new()
	dot.radius = 0.045
	dot.height = 0.09
	dot.radial_segments = 6
	dot.rings = 3
	dot.material = _arc_material
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = dot
	multimesh.instance_count = PREVIEW_DOTS
	_arc = MultiMeshInstance3D.new()
	_arc.multimesh = multimesh
	_arc.top_level = true
	_arc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_arc)
	_arc.global_transform = Transform3D.IDENTITY
	_arc_ring = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.96
	torus.outer_radius = 1.0
	torus.rings = 32
	_arc_ring.mesh = torus
	_arc_ring.top_level = true
	_arc_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_arc_ring)


## Where the model sits while aiming: the sight point lands on the camera's
## center line at the weapon's eye relief.
func _ads_position(data: WeaponData) -> Vector3:
	if _sight_point == Vector3.INF:
		return Vector3(0.0, -0.12, data.view_position.z - 0.08)
	var basis := Basis.from_euler(data.view_rotation_degrees * PI / 180.0).scaled(Vector3.ONE * data.view_scale)
	return Vector3(0.0, 0.0, -data.ads_eye_relief) - basis * _sight_point


## True while the sight picture is up (HUD hides the crosshair).
func sighted() -> bool:
	return _sight_point != Vector3.INF and _aim > 0.85





const PREVIEW_DOTS := 40
var _arc: MultiMeshInstance3D
var _arc_ring: MeshInstance3D
var _arc_material: StandardMaterial3D
var _preview_check := 0.0
var _preview_age := 0.0
var _previous_origin := Vector3.INF
var _previous_direction := Vector3.ZERO
var _previous_id := ""

func _update_throw_preview(delta: float) -> void:
	var data := selected_weapon()
	var wanted: bool = data != null and can_act() and not player.tarp_raised and active_count() > 0 \
		and data.kind in [WeaponData.Kind.GRENADE, WeaponData.Kind.FLARE]
	if not wanted:
		if _arc:
			_arc.hide()
			_arc_ring.hide()
		_previous_id = ""
		return
	_preview_check -= delta
	_preview_age += delta
	if _preview_check > 0.0:
		return
	_preview_check = 0.075
	var dir := -camera.global_basis.z
	var origin := WeaponCombat.throw_origin(get_world_3d(), camera.global_position, dir)
	if _previous_id == equipped_id and _preview_age < 0.3 and _previous_origin.distance_squared_to(origin) < 0.0144 \
			and _previous_direction.dot(dir) > 0.9995:
		return
	_preview_age = 0.0
	_previous_id = equipped_id
	_previous_origin = origin
	_previous_direction = dir
	if _arc == null:
		_build_preview()
	var color := data.tracer_color
	_arc_material.albedo_color = Color(color, lerpf(0.4, 0.9, _aim))
	var pos := origin
	var vel := WeaponProjectile.launch_velocity(data, dir)
	var exclude: Array[RID] = [player.get_rid()]
	var dt := 0.10
	var dots := 0
	var elapsed := 0.0
	var travelled := 0.0
	var total := 0.0
	var touched := false
	var life := WeaponProjectile.flight_time(data)
	var acceleration := WeaponProjectile.gravity(data)
	while elapsed < life and dots < PREVIEW_DOTS:
		var step := minf(dt, life - elapsed)
		elapsed += step
		vel.y -= acceleration * step
		var next := pos + vel * step
		var hit := WeaponProjectile.motion_hit(get_world_3d(), pos, next, exclude)
		if not hit.is_empty():
			touched = true
			var normal: Vector3 = hit.normal
			next = (hit.position as Vector3) + normal * 0.07
			vel = WeaponProjectile.bounce(data, hit, vel, elapsed)
		travelled += pos.distance_to(next)
		total += pos.distance_to(next)
		if total >= 1.1 and travelled >= 0.45:
			travelled = 0.0
			_arc.multimesh.set_instance_transform(dots, Transform3D(Basis(), next))
			dots += 1
		pos = next
		if touched and vel == Vector3.ZERO:
			break
	_arc.multimesh.visible_instance_count = dots
	_arc.show()
	_arc_ring.visible = touched or data.kind == WeaponData.Kind.GRENADE
	_arc_ring.global_position = pos + Vector3.UP * 0.045
	var radius := data.effect_radius * (GameManager.explosive_radius_scale() if equipped_id == "frag" else 1.0)
	_arc_ring.scale = Vector3(radius, 1.0, radius)
	_arc_ring.material_override = _arc_material

func _muzzle_position() -> Vector3:
	if _model:
		return _model.global_transform * (_model.get_meta("muzzle", selected_weapon().muzzle) as Vector3)
	return camera.global_position

static func is_damageable(target: Object) -> bool:
	return WeaponCombat.is_damageable(target)
