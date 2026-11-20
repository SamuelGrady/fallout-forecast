class_name Player
extends CharacterBody3D
## First-person hazmat exterminator.
##
## Movement and look run on the owning client (multiplayer authority).
## Exposure: the owning client works out `sheltered` (roof raycast, or head in a
## layer-4 Shelter area such as a teammate's raised Tarp) and `in_puddle` (feet in
## a layer-5 puddle) and reports them to the host. exposed = not sheltered or in
## a puddle.
##
## The host owns health, suit integrity and state:
## - suit drains at WeatherManager.suit_loss_per_second() while exposed (the
##   Leaky Nailgun drains it even in shelter); at 0 the drain hits health.
## - at 0 health the player is DOWNED: teammates hold E for 3 s to revive them.
##   They bleed out in 20 s, twice as fast when exposed in rain.
## - bleeding out TURNS them: they become a Drip (melee only, hittable by their
##   old team) until Clearing, when they respawn. Killed while Turned = OUT
##   until Clearing.
## - solo: one self-revive per wave (hold E); bleeding out ends the run.

signal sheltered_changed(is_sheltered: bool)
signal exposed_changed(is_exposed: bool)
signal damaged(amount: float)
signal state_changed(new_state: String)

const WORLD_LAYER := 1 << 0
const PLAYER_LAYER := 1 << 1
const ENEMY_LAYER := 1 << 2
const SHELTER_LAYER := 1 << 3
const PUDDLE_LAYER := 1 << 4
const ReviveSpot := preload("res://player/revive_spot.gd")
const ModelStyle := preload("res://props/model_style.gd")

@export_group("Movement")
@export var walk_speed := 5.0
@export var sprint_speed := 8.0
@export var crouch_speed := 2.5
@export var crawl_speed := 1.0
@export var turned_speed := 5.5
@export var ground_accel := 60.0
@export var air_accel := 12.0
@export var jump_velocity := 4.8
@export var coyote_time := 0.12
@export var jump_buffer := 0.12

@export_group("Crouch")
@export var stand_height := 1.8
@export var crouch_height := 1.1
@export var downed_height := 0.7
@export var crouch_transition_speed := 8.0

@export_group("Survival")
@export var max_health := 100.0
@export var revive_health := 50.0
@export var bleed_out_time := 20.0
@export var turned_health := 60.0
@export var melee_damage := 15.0
@export var melee_range := 2.2
@export var melee_cooldown := 0.9
## Suit drain while holding a weapon with held_suit_drain (Leaky Nailgun).
@export var leaky_drain := 2.0

@export_group("Look")
@export var mouse_sensitivity := 0.0025
@export var pad_look_speed := 3.0
@export var max_pitch_degrees := 88.0

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var is_crouching := false
var is_sprinting := false
var sheltered := false
var in_puddle := false
## What the host reads for suit integrity and Drip targeting.
var exposed := true

# Host-owned (synced to clients).
var health := 100.0
var suit_integrity := 100.0
## "ok", "downed", "turned" or "out".
var _step_distance := 0.0
var state := "ok"
var bleed_left := 0.0
var self_revives := 1

# Owner-set (synced to others).
var display_name := "You"
var suit_color := Color(1.0, 0.85, 0.2)
var has_tarp := false
var tarp_raised := false
## Set by WeaponHolder: the held weapon drains the suit even in shelter.
var holding_leaky := false

# Local UI.
var weapon_name = null
var ammo = null
var max_ammo = null
var interact_prompt := ""
var interact_progress := 0.0

var _height := 1.8
var _coyote_timer := 0.0
var _jump_buffer_timer := 0.0
var _pitch := 0.0
var _shelter_query := PhysicsPointQueryParameters3D.new()
var _puddle_query := PhysicsPointQueryParameters3D.new()
var _hold := 0.0
var _hold_done := false
var _melee_left := 0.0
var _shown_state := ""
var _tarp_area: Area3D
var _tarp_shape: CollisionShape3D
var _tarp_mesh: MeshInstance3D
var _turned_model: Node3D

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var collider: CollisionShape3D = $CollisionShape3D
@onready var roof_check: RayCast3D = $RoofCheck


func _ready() -> void:
	add_to_group("players")
	# Each player crouches on its own, so it needs its own capsule.
	collider.shape = collider.shape.duplicate()
	_height = stand_height
	_apply_height()

	_shelter_query.collide_with_areas = true
	_shelter_query.collide_with_bodies = false
	_shelter_query.collision_mask = SHELTER_LAYER
	_puddle_query.collide_with_areas = true
	_puddle_query.collide_with_bodies = false
	_puddle_query.collision_mask = PUDDLE_LAYER

	_build_children()

	if is_multiplayer_authority():
		add_to_group("local_player")
		camera.current = true
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	else:
		camera.current = false


## Children every peer builds the same way, so their node paths match for RPCs.
func _build_children() -> void:
	var spot := ReviveSpot.new()
	spot.name = "ReviveSpot"
	add_child(spot)

	_tarp_area = Area3D.new()
	_tarp_area.name = "TarpShelter"
	_tarp_area.collision_layer = SHELTER_LAYER
	_tarp_area.collision_mask = 0
	_tarp_area.monitoring = false
	_tarp_area.monitorable = false
	var shape := CollisionShape3D.new()
	_tarp_shape = shape
	shape.disabled = true
	var cyl := CylinderShape3D.new()
	cyl.radius = 2.0
	cyl.height = 2.6
	shape.shape = cyl
	shape.position.y = 1.3
	_tarp_area.add_child(shape)
	add_child(_tarp_area)
	_tarp_mesh = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(3.4, 0.05, 3.4)
	var tm := StandardMaterial3D.new()
	tm.albedo_color = Color(0.2, 0.45, 0.9)
	box.material = tm
	_tarp_mesh.mesh = box
	_tarp_mesh.position.y = 2.3
	_tarp_mesh.visible = false
	add_child(_tarp_mesh)

	_turned_model = (load("res://assets/kenney/characters/character-zombie.glb") as PackedScene).instantiate()
	_turned_model.name = "TurnedModel"
	_turned_model.set_script(ModelStyle)
	_turned_model.set("tint", Color(0.6, 1.0, 0.5))
	_turned_model.set("texture", load("res://assets/kenney/characters/Textures/colormap.png"))
	_turned_model.set("render_layers", 1 << 1)
	_turned_model.transform = Transform3D(Basis(Vector3.UP, PI).scaled(Vector3.ONE * 2.4), Vector3.ZERO)
	_turned_model.visible = false
	add_child(_turned_model)


func _unhandled_input(event: InputEvent) -> void:
	if not is_multiplayer_authority():
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_look(event.relative * Settings.mouse_sensitivity)
	elif event.is_action_pressed("pause"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _process(delta: float) -> void:
	_net_step(delta)
	if Net.is_host():
		_host_tick(delta)
	if state != _shown_state:
		_apply_state_visuals()
	var up := tarp_raised and state == "ok"
	if _tarp_shape.disabled == up:
		_tarp_shape.disabled = not up
	_tarp_mesh.visible = up


func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority():
		return
	if state == "out":
		velocity = Vector3.ZERO
		interact_prompt = ""
		return

	var pad_look := Input.get_vector("look_left", "look_right", "look_up", "look_down")
	if pad_look != Vector2.ZERO:
		_look(pad_look * pad_look_speed * delta)

	if is_on_floor():
		_coyote_timer = coyote_time
	else:
		velocity.y -= gravity * delta
		_coyote_timer -= delta

	if Input.is_action_just_pressed("jump"):
		_jump_buffer_timer = jump_buffer
	else:
		_jump_buffer_timer -= delta

	# Crouch: hold to crouch, stay down while something is overhead. Downed = flat.
	if Input.is_action_pressed("crouch"):
		is_crouching = true
	elif is_crouching and _can_stand():
		is_crouching = false
	var target_height := crouch_height if is_crouching else stand_height
	if state == "downed":
		target_height = downed_height
	if not is_equal_approx(_height, target_height):
		_height = move_toward(_height, target_height, crouch_transition_speed * delta)
		_apply_height()

	if _jump_buffer_timer > 0.0 and _coyote_timer > 0.0 and not is_crouching and state != "downed":
		velocity.y = jump_velocity
		_jump_buffer_timer = 0.0
		_coyote_timer = 0.0

	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := transform.basis * Vector3(input.x, 0.0, input.y)
	is_sprinting = Input.is_action_pressed("sprint") and not is_crouching and input.y < -0.1 and state == "ok"
	var speed := walk_speed
	match state:
		"downed":
			speed = crawl_speed
		"turned":
			speed = turned_speed
		_:
			if is_crouching:
				speed = crouch_speed
			elif is_sprinting:
				speed = sprint_speed
			if tarp_raised:
				speed = minf(speed, walk_speed * 0.7)

	var accel := ground_accel if is_on_floor() else air_accel
	var horizontal := Vector2(velocity.x, velocity.z).move_toward(
		Vector2(direction.x, direction.z) * speed, accel * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.y
	move_and_slide()
	if is_on_floor() and state in ["ok", "turned"]:
		var travel := get_position_delta()
		_step_distance += Vector2(travel.x, travel.z).length()
		if _step_distance >= 1.9:
			_step_distance = 0.0
			Sound.play("step_%d" % (randi() % 4), -20.0)
	_update_shelter()

	_handle_interact(delta)
	if state == "turned":
		_melee_left -= delta
		if Input.is_action_just_pressed("fire") and _melee_left <= 0.0:
			_melee_left = melee_cooldown
			if Net.is_host():
				_melee()
			else:
				_request_melee.rpc_id(1)
	if has_tarp and state == "ok" and Input.is_action_just_pressed("use_item"):
		_set_tarp(not tarp_raised)


# ------------------------------------------------------------------ host rules
func _host_tick(delta: float) -> void:
	match state:
		"ok":
			var drain := WeatherManager.suit_loss_per_second() if exposed else 0.0
			if holding_leaky:
				drain = maxf(drain, leaky_drain)
			if drain > 0.0:
				if suit_integrity > 0.0:
					suit_integrity = maxf(suit_integrity - drain * delta, 0.0)
				else:
					take_damage(drain * delta)
		"downed":
			var rate := 2.0 if exposed and WeatherManager.is_raining() else 1.0
			bleed_left -= delta * rate
			if bleed_left <= 0.0:
				_bleed_out()


## Enemies, spore clouds, suit drain and (for Turned players) teammates' guns.
func take_damage(amount: float, _source: Node = null) -> void:
	if not Net.is_host():
		return
	match state:
		"ok":
			health = maxf(health - amount, 0.0)
			damaged.emit(amount)
			if health <= 0.0:
				_go_down()
		"turned":
			health = maxf(health - amount, 0.0)
			damaged.emit(amount)
			if health <= 0.0:
				_set_state("out")


func heal(amount: float) -> void:
	if Net.is_host() and state == "ok":
		health = minf(health + amount, max_health)


func can_self_revive() -> bool:
	return state == "downed" and GameManager.is_solo() and self_revives > 0


## Host: called by a teammate's (or the solo player's own) revive hold.
func revive(by: Node) -> void:
	if state != "downed":
		return
	health = revive_health
	if by == self:
		self_revives -= 1
	else:
		GameManager.record_revive(by)
	_set_state("ok")


## Host: Clearing brings Turned and out players back.
func on_clearing() -> void:
	self_revives = 1
	if state == "turned" or state == "out":
		health = max_health
		suit_integrity = 50.0 if GameManager.is_solo() else 100.0
		_set_state("ok")
		var spawns := get_tree().get_nodes_in_group("player_spawn")
		if not spawns.is_empty():
			teleport((spawns.pick_random() as Node3D).global_transform)


func _go_down() -> void:
	bleed_left = bleed_out_time
	_set_state("downed")


func _bleed_out() -> void:
	if GameManager.is_solo():
		_set_state("out")
	else:
		health = turned_health
		GameManager.record_turned(self)
		_set_state("turned")


func _set_state(new_state: String) -> void:
	state = new_state
	state_changed.emit(state)
	match state:
		"downed", "turned": Sound.play_at(state, global_position)
		"ok": Sound.play_at("revive", global_position)


func _melee() -> void:
	var forward := -global_basis.z
	for p in GameManager.players():
		if p == self or p.state != "ok":
			continue
		var to: Vector3 = p.global_position - global_position
		if to.length() <= melee_range and forward.dot(to.normalized()) > 0.2:
			p.take_damage(melee_damage, self)


@rpc("any_peer", "call_remote", "reliable")
func _request_melee() -> void:
	if Net.is_host() and multiplayer.get_remote_sender_id() == get_multiplayer_authority() and state == "turned":
		_melee()


## Host: move this player (respawn). The owner moves itself.
func teleport(xf: Transform3D) -> void:
	if is_multiplayer_authority():
		_teleport(xf)
	else:
		_teleport.rpc_id(get_multiplayer_authority(), xf)


@rpc("any_peer", "call_remote", "reliable")
func _teleport(xf: Transform3D) -> void:
	if multiplayer.get_remote_sender_id() in [0, 1]:
		global_transform = xf
		velocity = Vector3.ZERO


## Host: give this player an item. Health and suit items apply on the host;
## ammo, weapons and the Tarp apply on the owning client.
func grant(item: String) -> void:
	match item:
		"medkit":
			heal(50.0)
		"suit_patch":
			suit_integrity = minf(suit_integrity + 50.0, 100.0)
		_:
			if is_multiplayer_authority():
				_apply_grant(item)
			else:
				_grant.rpc_id(get_multiplayer_authority(), item)


@rpc("any_peer", "call_remote", "reliable")
func _grant(item: String) -> void:
	if multiplayer.get_remote_sender_id() == 1:
		_apply_grant(item)


func _apply_grant(item: String) -> void:
	if item == "tarp":
		has_tarp = true
		return
	var holder := get_node_or_null("Head/Camera3D/WeaponHolder")
	if holder and holder.has_method("grant"):
		holder.grant(item)


# ------------------------------------------------------------------ interact
func _handle_interact(delta: float) -> void:
	var best: Interactable = null
	var best_score := INF
	if state != "turned":
		var forward := -camera.global_basis.z
		for node in get_tree().get_nodes_in_group("interactables"):
			var it := node as Interactable
			if it == null or not it.is_visible_in_tree():
				continue
			var to := it.global_position - global_position
			var d := to.length()
			if d > it.radius or not it.can_interact(self):
				continue
			var score := d - forward.dot(to.normalized() if d > 0.01 else forward)
			if score < best_score:
				best_score = score
				best = it
	if best == null and GameManager.has_method("lever_prompt"):
		var lever: String = GameManager.lever_prompt(self)
		if lever != "":
			interact_prompt = "[E] " + lever
			interact_progress = 0.0
			if Input.is_action_just_pressed("interact"):
				GameManager.pull_lever()
			return
	if best == null:
		interact_prompt = ""
		interact_progress = 0.0
		_hold = 0.0
		_hold_done = false
		return
	interact_prompt = "[E] " + best.get_prompt(self)
	var need := best.get_hold_time(self)
	if Input.is_action_pressed("interact"):
		_hold += delta
		interact_progress = clampf(_hold / maxf(need, 0.001), 0.0, 1.0)
		if _hold >= need and not _hold_done:
			_hold_done = true
			GameManager.interact(best, self)
	else:
		_hold = 0.0
		_hold_done = false
		interact_progress = 0.0


# ------------------------------------------------------------------ visuals
func _apply_state_visuals() -> void:
	_shown_state = state
	var body := get_node_or_null("BodyModel") as Node3D
	if body:
		body.visible = state == "ok" or state == "downed"
	_turned_model.visible = state == "turned"
	var holder := get_node_or_null("Head/Camera3D/WeaponHolder") as Node3D
	if holder:
		holder.visible = state == "ok"
	match state:
		"turned":
			collision_layer = ENEMY_LAYER
		"out":
			collision_layer = 0
		_:
			collision_layer = PLAYER_LAYER
	if state != "ok":
		tarp_raised = false


func get_move_state() -> String:
	if state != "ok":
		return state
	if not is_on_floor():
		return "air"
	if is_crouching:
		return "crouch"
	if Vector2(velocity.x, velocity.z).length() < 0.1:
		return "idle"
	return "sprint" if is_sprinting else "walk"


func _look(amount: Vector2) -> void:
	rotate_y(-amount.x)
	var limit := deg_to_rad(max_pitch_degrees)
	_pitch = clampf(_pitch - amount.y, -limit, limit)
	head.rotation.x = _pitch


func _apply_height() -> void:
	var capsule := collider.shape as CapsuleShape3D
	capsule.height = maxf(_height, capsule.radius * 2.0)
	collider.position.y = capsule.height * 0.5
	head.position.y = _height - 0.15


func _can_stand() -> bool:
	return not test_move(global_transform, Vector3.UP * (stand_height - _height + 0.05))


func is_exposed() -> bool:
	return exposed


func _update_shelter() -> void:
	var space := get_world_3d().direct_space_state
	_shelter_query.position = head.global_position
	var in_shelter_area := not space.intersect_point(_shelter_query, 1).is_empty()
	_puddle_query.position = global_position + Vector3.UP * 0.05
	var now_in_puddle := not space.intersect_point(_puddle_query, 1).is_empty()
	var now_sheltered := roof_check.is_colliding() or in_shelter_area
	if now_sheltered != sheltered or now_in_puddle != in_puddle:
		_set_exposure(now_sheltered, now_in_puddle)
		# Clients tell the host; the host is the only one who acts on it.
		if not Net.is_host():
			_report_exposure.rpc_id(1, sheltered, in_puddle)


## Client -> host: this player's shelter and puddle state changed.
@rpc("any_peer", "call_remote", "reliable")
func _report_exposure(is_sheltered: bool, is_in_puddle: bool) -> void:
	if Net.is_host() and multiplayer.get_remote_sender_id() == get_multiplayer_authority():
		_set_exposure(is_sheltered, is_in_puddle)


func _set_exposure(is_sheltered: bool, is_in_puddle: bool) -> void:
	in_puddle = is_in_puddle
	if is_sheltered != sheltered:
		sheltered = is_sheltered
		sheltered_changed.emit(sheltered)
	var now_exposed := not sheltered or in_puddle
	if now_exposed != exposed:
		exposed = now_exposed
		exposed_changed.emit(exposed)


# ------------------------------------------------------------------ network
## Owner -> host -> everyone else. ENet clients can only address the host, so
## the host relays; that is why each value has a _push_ and an _apply_ half.
##
## These RPCs are "any_peer" rather than "authority" on purpose: the node's
## authority is its owner, so a host relaying on behalf of a client would be
## rejected by an "authority" check. Each handler validates the sender instead.
const NET_RATE := 20.0
## How often the host resends health, suit, state and the tarp.
const VITALS_RATE := 0.2

var _net_left := 0.0
var _vitals_left := 0.0


func _net_step(delta: float) -> void:
	if not Net.is_online():
		return
	_net_left -= delta
	if _net_left <= 0.0:
		_net_left = 1.0 / NET_RATE
		if is_multiplayer_authority():
			if Net.is_host():
				_relay_transform.rpc(global_position, rotation.y, head.rotation.x, velocity)
			else:
				_push_transform.rpc_id(1, global_position, rotation.y, head.rotation.x, velocity)
	if not Net.is_host():
		return
	_vitals_left -= delta
	if _vitals_left <= 0.0:
		_vitals_left = VITALS_RATE
		_apply_vitals.rpc(health, suit_integrity, state, bleed_left, tarp_raised)


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _push_transform(pos: Vector3, yaw: float, pitch: float, vel: Vector3) -> void:
	if not Net.is_host() or multiplayer.get_remote_sender_id() != get_multiplayer_authority():
		return
	_apply_transform(pos, yaw, pitch, vel)
	_relay_transform.rpc(pos, yaw, pitch, vel)


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _relay_transform(pos: Vector3, yaw: float, pitch: float, vel: Vector3) -> void:
	if multiplayer.get_remote_sender_id() != 1:
		return
	_apply_transform(pos, yaw, pitch, vel)


## Remote copies are driven straight from the network; only the owner moves
## itself with move_and_slide (its _physics_process returns early otherwise).
func _apply_transform(pos: Vector3, yaw: float, pitch: float, vel: Vector3) -> void:
	if is_multiplayer_authority():
		return
	global_position = pos
	rotation.y = yaw
	head.rotation.x = pitch
	velocity = vel


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _apply_vitals(hp: float, suit: float, new_state: String, bleed: float, tarp: bool) -> void:
	if Net.is_host() or multiplayer.get_remote_sender_id() != 1:
		return
	health = hp
	suit_integrity = suit
	bleed_left = bleed
	tarp_raised = tarp and new_state == "ok"
	# Assigned, not _set_state(): a remote player's change must not replay the
	# downed/revive stingers on this machine.
	state = new_state


func _set_tarp(value: bool) -> void:
	tarp_raised = value
	if not Net.is_online() or not is_multiplayer_authority():
		return
	if Net.is_host():
		_apply_tarp.rpc(value)
	else:
		_push_tarp.rpc_id(1, value)


@rpc("any_peer", "call_remote", "reliable")
func _push_tarp(value: bool) -> void:
	if not Net.is_host() or multiplayer.get_remote_sender_id() != get_multiplayer_authority():
		return
	tarp_raised = value
	_apply_tarp.rpc(value)


@rpc("any_peer", "call_remote", "reliable")
func _apply_tarp(value: bool) -> void:
	if multiplayer.get_remote_sender_id() != 1:
		return
	tarp_raised = value


## Host: tell whoever fired that the shot landed. The host's own player shows
## it straight away; a client's is sent to that client.
func notify_hit(killed: bool, critical: bool, point: Vector3, amount: int) -> void:
	if not Net.is_host():
		return
	if get_multiplayer_authority() == 1 or not Net.is_online():
		local_hit(killed, critical, point, amount)
	else:
		_receive_hit.rpc_id(get_multiplayer_authority(), killed, critical, point, amount)


@rpc("any_peer", "call_remote", "reliable")
func _receive_hit(killed: bool, critical: bool, point: Vector3, amount: int) -> void:
	if multiplayer.get_remote_sender_id() != 1:
		return
	local_hit(killed, critical, point, amount)


## Owner of the shot: hit marker, floating number and the headshot sting.
func local_hit(killed: bool, critical: bool, point: Vector3, amount: int) -> void:
	GameManager.combat_hit.emit(killed, critical)
	if amount > 0:
		show_damage(point, amount, critical)
	if critical:
		Sound.play("headshot", -10.0)


## A damage number that every peer could see, at the point the shot landed.
func show_damage(point: Vector3, amount: int, critical: bool) -> void:
	var parent := get_parent()
	if parent == null:
		return
	var number := Label3D.new()
	number.set_script(preload("res://weapons/damage_number.gd"))
	# Set before add_child: damage_number's _ready() reads both.
	number.set("amount", amount)
	number.set("critical", critical)
	parent.add_child(number)
	number.global_position = point + Vector3.UP * 0.25
