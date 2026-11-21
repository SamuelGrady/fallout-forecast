class_name WeaponHolder
extends Node3D
## Host owns slots, shared reserves, reload, fire cadence and curse rolls.
## Copies on clients hold the owner's latest snapshot and public equipment.

signal weapon_changed(data: WeaponData)
signal fired(data: WeaponData)

const HIT_MASK := 1 | 4
const SLOT_COUNT := 5
const SPRINT_RAISE := 0.15

var slots: Array[ItemInstance] = [null, null, null, null, null]
var reserves: Dictionary = {}
var _seeded_ammo: Dictionary = {"revolver": true}
var current := 0
var scrap := 0
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
var _kick := 0.0
var _bob := 0.0
var _aim := 0.0
var _equip_left := 0.0
var _fire_buffer := 0.0
var _recoil := 0.0
var _camera_kick := 0.0
var _heat := 0.0
var _hip_fov := 75.0
var _raise_left := 0.0
var _sight_point := Vector3.INF
var _shot_counter := 0
var _spread_at := 0.0
var _remote_view: Node3D

func _ready() -> void:
	camera = get_parent() as Camera3D
	_hip_fov = camera.fov
	player = camera.get_parent().get_parent() as Node3D
	loot = RunLoot.find(get_tree())
	if Net.is_host() and loot:
		slots[0] = loot.make_item("service_revolver")
		reserves["revolver"] = 24
		_refresh_equip()
		if loot.run_id > 0:
			send_state()

func selected() -> ItemInstance:
	return slots[current]

func selected_serial() -> int:
	return selected().serial if selected() else 0

func selected_definition() -> ItemDefinition:
	return ItemCatalog.definition(selected().id) if selected() else null

func selected_weapon() -> WeaponData:
	var definition := selected_definition()
	return definition.weapon if definition else null

func selected_reserve() -> int:
	var definition := selected_definition()
	return int(reserves.get(definition.ammo_type, 0)) if definition else 0

func reload_remaining() -> float:
	return _reload_left

func jammed() -> bool:
	return _jam_left > 0.0

func can_act() -> bool:
	return loot != null and loot.run_id > 0 and player.state == "ok" and not GameManager.awaiting_tape_choice \
			and not GameManager.is_voting() and not get_tree().paused

func _process(delta: float) -> void:
	_cooldown = maxf(0.0, _cooldown - delta)
	_jam_left = maxf(0.0, _jam_left - delta)
	_pending_action = maxf(0.0, _pending_action - delta)
	if _reload_left > 0.0:
		_reload_left = maxf(0.0, _reload_left - delta)
		if _reload_left <= 0.0 and Net.is_host():
			_finish_reload()
	if Net.is_host() and not can_act() and (_reload_serial != 0 or _charge_serial != 0):
		_cancel_actions()
		send_state(false)
	if not player.is_multiplayer_authority() or Net.dedicated:
		if _remote_view:
			_remote_view.visible = player.state == "ok"
		return
	_fire_buffer = maxf(0.0, _fire_buffer - delta)
	_raise_left = SPRINT_RAISE if player.is_sprinting else maxf(0.0, _raise_left - delta)
	_camera_kick = move_toward(_camera_kick, 0.0, delta * deg_to_rad(8.0))
	camera.rotation.x = _camera_kick
	_roll = move_toward(_roll, 0.0, delta * deg_to_rad(20.0))
	camera.rotation.z = _roll
	_recoil = move_toward(_recoil, 0.0, delta * 2.8)
	_kick = move_toward(_kick, 0.0, delta * 6.0)
	_handle_input()
	_publish()
	_animate(delta)
	_update_throw_preview(delta)

func _handle_input() -> void:
	if not can_act():
		_fire_buffer = 0.0
		return
	var wheel := int(Input.is_action_just_pressed("weapon_next")) - int(Input.is_action_just_pressed("weapon_prev"))
	if wheel != 0:
		select_slot(posmod(current + wheel, SLOT_COUNT))
		return
	var data := selected_weapon()
	if data == null or player.tarp_raised:
		return
	if Input.is_action_just_pressed("reload"):
		start_reload()
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and not _pad_connected():
		_fire_buffer = 0.0
		return
	if data.charge_time > 0.0:
		if Input.is_action_just_pressed("fire"):
			if selected().count > 0:
				_command("charge")
			elif selected_reserve() > 0 and _reload_left <= 0.0:
				start_reload()
		if Input.is_action_just_released("fire"):
			fire()
		return
	if Input.is_action_just_pressed("fire"):
		_fire_buffer = 0.15 + _raise_left
	var wants := Input.is_action_pressed("fire") if data.automatic else _fire_buffer > 0.0
	if wants:
		player.sprint_lock = 0.35
	if wants and _cooldown <= 0.0 and _pending_action <= 0.0 and _jam_left <= 0.0 and _raise_left <= 0.0:
		if selected().count > 0 and (_reload_left <= 0.0 or data.shell_reload):
			fire()
		elif selected_reserve() > 0 and _reload_left <= 0.0:
			start_reload()

func _unhandled_input(event: InputEvent) -> void:
	if Net.dedicated or not player.is_multiplayer_authority() or not can_act():
		return
	if event.is_action_pressed("drop_item") and selected():
		_command("drop")
		get_viewport().set_input_as_handled()
		return
	for slot in SLOT_COUNT:
		if event.is_action_pressed("weapon_%d" % (slot + 1)):
			select_slot(slot)
			get_viewport().set_input_as_handled()
			return

func fire() -> void:
	if not Net.can_send_run_rpc() or not can_act() or selected() == null:
		return
	_fire_buffer = 0.0
	var dir := -camera.global_basis.z
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
			WeaponCombat.play_fx(loot, selected().id, _muzzle_position(), [], true)
			_local_shot_motion(selected().id, data, ads)
		_request_shot.rpc_id(1, loot.run_id, selected_serial(), camera.global_position, dir, ads, predict)

func start_reload() -> void:
	_command("reload")

func select_slot(slot: int) -> void:
	_command("select", slot)

func _command(action: String, slot := -1) -> void:
	if not can_act():
		return
	if Net.is_host():
		_host_action(loot.run_id, action, selected_serial(), slot)
	else:
		_action.rpc_id(1, loot.run_id, action, selected_serial(), slot)

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
	if action == "select" and slot >= 0 and slot < SLOT_COUNT and slot != current:
		_cancel_actions()
		current = slot
		_cooldown = maxf(_cooldown, 0.25)
		_heat = 0.0
		send_state()
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
	var cue := "reel_tick" if data.shell_reload else ("rifle_reload" if data.automatic else "reload")
	Sound.play(cue, -12.0 if data.shell_reload else -8.0)

@rpc("any_peer", "call_remote", "reliable")
func _request_shot(run: int, serial: int, origin: Vector3, dir: Vector3, is_aiming: bool, predicted: bool) -> void:
	if _valid_sender():
		_host_shot(run, serial, origin, dir, is_aiming, Net.get_rewind_ms(multiplayer.get_remote_sender_id()), predicted)

func _host_shot(run: int, serial: int, origin: Vector3, dir: Vector3, is_aiming: bool, rewind_ms: int, predicted := false) -> bool:
	if not Net.is_host() or not can_act() or run != loot.run_id or serial == 0 or selected_serial() != serial \
			or player.tarp_raised or player.is_sprinting or _cooldown > 0.0:
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
	var emptied := item.count == 0 and definition.kind != ItemDefinition.Kind.GUN
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
	WeaponCombat.play_fx(loot, id, muzzle, traces, local, not (local and predicted))
	if not local:
		return
	_pending_action = 0.0
	if not predicted:
		_local_shot_motion(id, data, ads)


func _local_shot_motion(id: String, data: WeaponData, ads: bool) -> void:
	_cooldown = data.fire_interval * GameManager.fire_rate_scale()
	_kick = 1.0
	_recoil = minf(_recoil + (0.28 if data.pellets > 1 else 0.10), 0.55)
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
	return not slots.has(null) and _stack_slot(item) == -1

## Returns the displaced item, null on placement/stack, or the original on rejection.
func accept_pickup(item: ItemInstance) -> ItemInstance:
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
		Net.rpc_to_run(_equip_state, [loot.run_id, revision, equipped_id, equipped_tier])
	var item := selected()
	_jam_left = maxf(0.0, item.jam_until - loot.clock) if item else 0.0
	var peer := player.get_multiplayer_authority()
	if peer != 1 and Net.run_peers.has(peer):
		sync_private_to(peer)

func sync_private_to(peer: int) -> void:
	var rows: Array = []
	for item in slots:
		rows.append(item.encode() if item else [])
	_private_state.rpc_id(peer, loot.run_id, revision, rows, reserves, current, scrap, _reload_left, _reload_total, _jam_left, _cooldown)

func sync_equip_to(peer: int) -> void:
	_equip_state.rpc_id(peer, loot.run_id, revision, equipped_id, equipped_tier)

@rpc("any_peer", "call_remote", "reliable")
func _private_state(run: int, rev: int, rows: Array, stash: Dictionary, slot: int, new_scrap: int, reload_left: float, reload_total: float, jam_left: float, cooldown: float) -> void:
	if multiplayer.get_remote_sender_id() != 1 or run != loot.run_id or rev <= _private_revision or not player.is_multiplayer_authority():
		return
	_private_revision = rev
	var old_serial := selected_serial()
	var old_reload := _reload_left
	for i in SLOT_COUNT:
		slots[i] = ItemInstance.decode(rows[i])
	reserves = stash
	current = slot
	scrap = new_scrap
	_reload_left = reload_left
	_reload_total = reload_total
	_jam_left = jam_left
	_cooldown = cooldown
	_refresh_equip()
	if reload_left > 0.0 and (old_reload < reload_left or old_serial != selected_serial()):
		_reload_sound(selected_weapon())

@rpc("any_peer", "call_remote", "reliable")
func _equip_state(run: int, rev: int, id: String, tier: int) -> void:
	if multiplayer.get_remote_sender_id() != 1 or run != loot.run_id or rev <= _public_revision:
		return
	_public_revision = rev
	if not player.is_multiplayer_authority():
		_apply_equip(id, tier)

func _refresh_equip() -> void:
	var item := selected()
	_apply_equip(item.id if item else "", item.tier if item else 0)
	if player.is_multiplayer_authority() and _model_serial != selected_serial():
		_model_serial = selected_serial()
		_equip_left = 1.0
		_aim = 0.0

func _apply_equip(id: String, tier: int) -> void:
	var changed := equipped_id != id or equipped_tier != tier
	equipped_id = id
	equipped_tier = tier
	var definition := ItemCatalog.definition(id)
	player.holding_leaky = definition != null and definition.weapon.held_suit_drain > 0.0
	if player.holding_leaky:
		player.leaky_drain = definition.weapon.held_suit_drain
	if not changed or Net.dedicated:
		return
	if _model:
		_model.hide()
		_model.queue_free()
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
			_model.set_meta("base_scale", _model.scale)
			if _model is GeometryInstance3D:
				_model.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			for mesh: MeshInstance3D in _model.find_children("*", "MeshInstance3D", true, false):
				mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_sight_point = _model.get_meta("sight", Vector3.INF)
		else:
			_remote_view = ItemCatalog.model(id, true)
			player.add_child.call_deferred(_remote_view)
			_remote_view.position = Vector3(0.34, 1.12, -0.47)
	weapon_changed.emit(definition.weapon if definition else null)

func _publish() -> void:
	var data := selected_weapon()
	player.weapon_name = data.display_name + (" (JAMMED)" if jammed() else (" (reloading)" if _reload_left > 0.0 else "")) if data else null
	player.ammo = selected().count if data else null
	player.max_ammo = selected_reserve() if data else null

func _pad_connected() -> bool:
	return not Input.get_connected_joypads().is_empty()

var _roll := 0.0
var _sprint_fov := 0.0
static var _casing_mesh: BoxMesh
static var _casing_mat: StandardMaterial3D
var _casings: Array[Node3D] = []


## Local feel for every shot: ejected brass, muzzle smoke, a camera roll and
## shake on heavy guns.
func _shot_juice(data: WeaponData) -> void:
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
			and _reload_left <= 0.0 \
			and (Input.mouse_mode == Input.MOUSE_MODE_CAPTURED or _pad_connected()) and Input.is_action_pressed("aim")
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
	if _reload_left > 0.0:
		var t := 1.0 - _reload_left / maxf(_reload_total, 0.01)
		if data.shell_reload:
			# Shell by shell: rolled to the side, a thumb-push bump per shell.
			reload_dip = 0.35
			reload_roll = 28.0
			reload_push = sin(t * PI) * 0.05
		elif data.kind == WeaponData.Kind.FLARE:
			# Break action: barrel tips down, then snaps shut at the end.
			reload_dip = 1.25 * sin(minf(t / 0.8, 1.0) * PI * 0.5) * (1.0 if t < 0.85 else (1.0 - t) / 0.15)
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
	if barrel:
		# Break action: the barrel tips open for the reload.
		barrel.rotation.x = -deg_to_rad(42.0) * clampf(reload_dip / 1.25, 0.0, 1.0)


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
	var wanted: bool = data != null and can_act() and not player.tarp_raised and selected().count > 0 \
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
