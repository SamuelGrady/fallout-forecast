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
## Owner only: a hit landed from this world position (HUD hit-direction arc).
signal hurt_from(position: Vector3)
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
## One warning window per wet stretch, even if the player ducks briefly into cover.
var _first_rain_contact := false
var _rain_warning_left := 0.0

# Host-owned (synced to clients).
var health := 100.0
var suit_integrity := 100.0
## Static Charge mutation: 0..1 charge built by sprinting, discharged on melee hit.
var static_charge := 0.0
## "ok", "downed", "turned" or "out".
var _step_distance := 0.0
var state := "ok"
var bleed_left := 0.0
var self_revives := 1

# Owner-set (synced to others).
var display_name := "You"
var suit_color := Color(1.0, 0.85, 0.2)
## Cosmetics.SKINS index; main.gd sets both from the roster (or Settings solo).
var skin := 0
var has_tarp := false
var tarp_raised := false
## Set by WeaponHolder: the held weapon drains the suit even in shelter.
var holding_leaky := false
## Set by WeaponHolder: aiming down sights slows movement and blocks sprint.
var aiming := false
## Set by WeaponHolder when firing: suppresses sprint briefly.
var sprint_lock := 0.0
## Host: post-hit / post-revive i-frames. No damage (and on revive, no suit drain) until it runs out.
var _grace_left := 0.0
var _revive_grace_left := 0.0
var invulnerable := false
var _enemy_pull := Vector3.ZERO
var _applied_pull := Vector3.ZERO
var _acid_blood_cooldown := 0.0
var _last_headshot_ms := 0
const HIT_IFRAMES := 0.65
const REVIVE_GRACE := 3.0
const SELF_REVIVE_SUIT := 30.0
const POS_HISTORY_LIMIT := 24
var _pos_history: Array[Dictionary] = []

# Local UI.
var weapon_name = null
var ammo = null
var max_ammo = null
var interact_prompt := ""
var interact_progress := 0.0
## The radial ping wheel uses mouse motion and the right stick while open.
var look_locked := false

var _height := 1.8
var _coyote_timer := 0.0
var _jump_buffer_timer := 0.0
var _pitch := 0.0
var _shelter_query := PhysicsPointQueryParameters3D.new()
var _puddle_query := PhysicsPointQueryParameters3D.new()
var _hold_target: Interactable
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
	if GameManager.bonus_max_health() > 0.0:
		max_health = 100.0 + GameManager.bonus_max_health()
		health = max_health

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
		if OS.has_feature("web"):
			# Fog hides everything past ~80 m; culling far geometry cuts WebGL draw calls.
			camera.far = 95.0
		else:
			TouchInput.capture_pointer()
	else:
		camera.current = false


## Children every peer builds the same way, so their node paths match for RPCs.
func _build_children() -> void:
	# Custom animated hazmat model replaces the static Kenney worker.
	var old_body := get_node_or_null("BodyModel")
	if old_body:
		remove_child(old_body)
		old_body.queue_free()
	var body := Node3D.new()
	body.name = "BodyModel"
	body.set_script(preload("res://player/player_model.gd"))
	add_child(body)
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
	_turned_model.set("render_layers", (1 << 1) if is_multiplayer_authority() else 1)
	_turned_model.transform = Transform3D(Basis(Vector3.UP, PI).scaled(Vector3.ONE * 2.4), Vector3.ZERO)
	_turned_model.visible = false
	add_child(_turned_model)


func _unhandled_input(event: InputEvent) -> void:
	if not is_multiplayer_authority() or GameManager.awaiting_tape_choice:
		return
	# The loadout screen owns the cursor: no look, no click-to-recapture.
	if InventoryMenu.is_open():
		return
	if event is InputEventMouse and event.device == InputEvent.DEVICE_ID_EMULATION:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_look(event.relative * Settings.mouse_sensitivity)
	elif event.is_action_pressed("pause"):
		TouchInput.release_pointer()
	elif event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		TouchInput.capture_pointer()


func touch_look(screen_relative: Vector2) -> void:
	_look(TouchInput.look_delta(screen_relative))


func _process(delta: float) -> void:
	_net_step(delta)
	_smooth_remote(delta)
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
	if GameManager.awaiting_tape_choice or not Net.can_send_run_rpc():
		return
	if state == "out":
		velocity = Vector3.ZERO
		interact_prompt = ""
		return

	var pad_look := Input.get_vector("look_left", "look_right", "look_up", "look_down")
	if pad_look != Vector2.ZERO and not InventoryMenu.is_open():
		_look(pad_look * pad_look_speed * delta)

	if is_on_floor():
		_coyote_timer = coyote_time
	else:
		velocity.y -= gravity * delta
		_coyote_timer -= delta

	var loadout_input := InventoryMenu.blocks_gameplay_actions()
	if not loadout_input and Input.is_action_just_pressed("jump"):
		_jump_buffer_timer = jump_buffer
	else:
		_jump_buffer_timer -= delta

	# Crouch: hold to crouch, stay down while something is overhead. Downed = flat.
	if not loadout_input and Input.is_action_pressed("crouch"):
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
		velocity.y = jump_velocity * GameManager.jump_scale()
		_jump_buffer_timer = 0.0
		_coyote_timer = 0.0

	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	input = (input + TouchInput.movement).limit_length()
	var direction := transform.basis * Vector3(input.x, 0.0, input.y)
	sprint_lock = maxf(0.0, sprint_lock - delta)
	is_sprinting = Input.is_action_pressed("sprint") and not is_crouching and input.y < -0.1 and state == "ok" \
			and not aiming and sprint_lock <= 0.0
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
			speed *= GameManager.player_speed_scale()
			if tarp_raised or aiming:
				speed = minf(speed, walk_speed * 0.7)

	var accel := ground_accel if is_on_floor() else air_accel
	var own_velocity := velocity - _applied_pull
	var horizontal := Vector2(own_velocity.x, own_velocity.z).move_toward(
		Vector2(direction.x, direction.z) * speed, accel * delta)
	# Undertow mutation: active puddles tug nearby players inward (Hydro-Skin resists 70%).
	if state == "ok" and GameManager.has_mutation("undertow"):
		var pull_scale := 0.3 if GameManager.has_player_mutation("hydro_skin") else 1.0
		for puddle in get_tree().get_nodes_in_group("puddles"):
			var r: float = puddle.radius()
			if r <= 0.25:
				continue
			var to_puddle: Vector3 = (puddle as Node3D).global_position - global_position
			to_puddle.y = 0.0
			var d := to_puddle.length()
			if d > 0.25 and d < r + 1.8:
				var falloff := 1.0 - clampf(d / (r + 1.8), 0.0, 1.0)
				horizontal += Vector2(to_puddle.x, to_puddle.z).normalized() * (22.0 * falloff * pull_scale * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.y
	_enemy_pull = _enemy_pull.move_toward(Vector3.ZERO, 22.0 * delta)
	_applied_pull = _enemy_pull if state == "ok" else Vector3.ZERO
	velocity += _applied_pull
	var requested_velocity := velocity
	move_and_slide()
	# Remove only the portion of the impulse that survived sliding along cover.
	if not velocity.is_equal_approx(requested_velocity):
		for index in get_slide_collision_count():
			_applied_pull = _applied_pull.slide(get_slide_collision(index).get_normal())
	if is_on_floor() and state in ["ok", "turned"]:
		var travel := get_position_delta()
		_step_distance += Vector2(travel.x, travel.z).length()
		if _step_distance >= 1.9:
			_step_distance = 0.0
			_footstep()
	_landing_check()
	_update_shelter()

	_handle_interact(delta, loadout_input)
	if not loadout_input and Input.is_action_just_pressed("ready_up") and state == "ok" and not GameManager.is_voting():
		GameManager.ready_up()
	if state == "turned":
		_melee_left -= delta
		if Input.is_action_just_pressed("fire") and _melee_left <= 0.0:
			_melee_left = melee_cooldown
			if Net.is_host():
				_melee()
			else:
				_request_melee.rpc_id(1)
	if not loadout_input and has_tarp and state == "ok" and not GameManager.is_voting() and Input.is_action_just_pressed("use_item"):
		_set_tarp(not tarp_raised)


# ------------------------------------------------------------------ host rules
func _host_tick(delta: float) -> void:
	_grace_left = maxf(0.0, _grace_left - delta)
	_revive_grace_left = maxf(0.0, _revive_grace_left - delta)
	invulnerable = _grace_left > 0.0 or _revive_grace_left > 0.0
	_acid_blood_cooldown = maxf(0.0, _acid_blood_cooldown - delta)
	if state == "turned":
		_record_position()
	if GameManager.has_mutation("static_charge") and state == "ok":
		var hspeed := Vector2(velocity.x, velocity.z).length()
		if hspeed > 5.8:
			static_charge = minf(1.0, static_charge + delta * 0.26)
		else:
			static_charge = maxf(0.0, static_charge - delta * 0.14)
	else:
		static_charge = 0.0
	var hazard := acid_hazard()
	if not WeatherManager.is_storm_active():
		_first_rain_contact = false
		_rain_warning_left = 0.0
	elif hazard == "rain" and not _first_rain_contact:
		_first_rain_contact = true
		_rain_warning_left = 0.8
	_rain_warning_left = maxf(0.0, _rain_warning_left - delta)
	match state:
		"ok":
			if _revive_grace_left > 0.0:
				return
			if GameManager.has_player_mutation("hydro_skin") and hazard == "rain" and suit_integrity > 0.0:
				heal(2.5 * delta)
			var drain := 0.0
			if hazard == "puddle" or (hazard == "rain" and _rain_warning_left <= 0.0):
				drain = WeatherManager.suit_loss_per_second() * GameManager.suit_drain_scale()
			if drain > 0.0 and WeaponProjectile.dries(global_position + Vector3.UP, get_tree()):
				drain *= 0.25
			if holding_leaky:
				drain = maxf(drain, leaky_drain)
			if drain > 0.0:
				if suit_integrity > 0.0:
					suit_integrity = maxf(suit_integrity - drain * delta, 0.0)
				else:
					take_damage(drain * delta)
		"downed":
			var rate := 2.0 if hazard in ["rain", "puddle"] else 1.0
			bleed_left -= delta * rate
			if bleed_left <= 0.0:
				_bleed_out()


## Host: raise max_health when a bio-mutation (Chitin Suit) is granted mid-run.
func apply_max_health_bonus(bonus: float) -> void:
	if not Net.is_host() or bonus <= 0.0:
		return
	max_health += bonus
	if state == "ok":
		health = minf(max_health, health + bonus)


func _record_position() -> void:
	_pos_history.append({"ms": Time.get_ticks_msec(), "pos": global_position})
	if _pos_history.size() > POS_HISTORY_LIMIT:
		_pos_history.remove_at(0)


## Host lag compensation for shooting Turned players.
func sample_position(target_ms: int) -> Vector3:
	if _pos_history.is_empty():
		return global_position
	var last := _pos_history[_pos_history.size() - 1]
	if target_ms >= int(last.ms):
		return last.pos
	var first := _pos_history[0]
	if target_ms <= int(first.ms):
		return first.pos
	for i in range(_pos_history.size() - 1, 0, -1):
		var a := _pos_history[i - 1]
		var b := _pos_history[i]
		if target_ms >= int(a.ms) and target_ms <= int(b.ms):
			var span := float(int(b.ms) - int(a.ms))
			var frac := (float(target_ms - int(a.ms)) / span) if span > 0.0 else 0.0
			return (a.pos as Vector3).lerp(b.pos as Vector3, clampf(frac, 0.0, 1.0))
	return global_position


## Enemies, spore clouds, suit drain and (for Turned players) teammates' guns.
## Host: tell this player's owner where a hit came from.
func _send_hurt_from(at: Vector3) -> void:
	if is_multiplayer_authority():
		hurt_from.emit(at)
	elif Net.is_online():
		_receive_hurt_from.rpc_id(get_multiplayer_authority(), at)


@rpc("any_peer", "call_remote", "unreliable")
func _receive_hurt_from(at: Vector3) -> void:
	if multiplayer.get_remote_sender_id() != 1:
		return
	hurt_from.emit(at)


# ------------------------------------------------------------------ feel
var _air_speed := 0.0
var _was_floored := true


## Footstep by surface: puddle splash, grass, wood (porches, decks), asphalt.
func _footstep() -> void:
	if in_puddle:
		Sound.play("splash_%d" % (randi() % 2), -14.0, randf_range(0.9, 1.1))
		if is_multiplayer_authority() and velocity.length() > 6.0:
			ShotFX.puff(get_parent(), global_position + Vector3.UP * 0.1, Color(0.6, 0.75, 0.85, 0.6), 0.18, 0.35)
		return
	var surface := _surface_under()
	match surface:
		"grass":
			Sound.play("step_grass_%d" % (randi() % 2), -16.0, randf_range(0.9, 1.1))
		"wood":
			Sound.play("step_wood_%d" % (randi() % 2), -15.0, randf_range(0.9, 1.1))
		_:
			Sound.play("step_%d" % (randi() % 4), -20.0)


func _surface_under() -> String:
	var query := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 0.3, global_position + Vector3.DOWN * 0.6, WORLD_LAYER, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty() or hit.collider == null:
		return "asphalt"
	var path := str((hit.collider as Node).get_path()).to_lower()
	for key in ["grass", "lawn", "park", "yard", "planter"]:
		if path.contains(key):
			return "grass"
	for key in ["porch", "deck", "pavilion", "wood", "gazebo"]:
		if path.contains(key):
			return "wood"
	return "asphalt"


## A short dip and thud when landing from a real fall.
func _landing_check() -> void:
	var floored := is_on_floor()
	if not floored:
		_air_speed = minf(_air_speed, velocity.y)
	elif not _was_floored and _air_speed < -4.5:
		var dip := clampf(-_air_speed * 0.012, 0.04, 0.12)
		var base_y := head.position.y
		var tween := head.create_tween()
		tween.tween_property(head, "position:y", base_y - dip, 0.06)
		tween.tween_property(head, "position:y", base_y, 0.18)
		Sound.play("step_%d" % (randi() % 4), -12.0, 0.8)
		Juice.shake(0.12)
		_air_speed = 0.0
	if floored:
		_air_speed = 0.0
	_was_floored = floored


func take_damage(amount: float, _source: Node = null, continuous := false) -> void:
	if not Net.is_host():
		return
	match state:
		"ok":
			if _grace_left > 0.0 or _revive_grace_left > 0.0:
				return
			health = maxf(health - amount, 0.0)
			damaged.emit(amount)
			if _source is Node3D and amount >= 1.0:
				_send_hurt_from((_source as Node3D).global_position)
			# Brief hit i-frames on real combat hits so swarms can't instant-delete
			# the player in a single frame (continuous rain drain ticks stay smooth).
			if not continuous and health > 0.0 and (_source != null or amount >= 4.0):
				_grace_left = maxf(_grace_left, HIT_IFRAMES)
				invulnerable = true
			# Static Charge mutation: sprinting builds shock that retaliates on melee hit.
			if not continuous and GameManager.has_mutation("static_charge") and static_charge >= 0.25 and _source is EnemyBase:
				var attacker := _source as EnemyBase
				var shock := lerpf(15.0, 45.0, static_charge)
				static_charge = 0.0
				attacker.stagger(0.6)
				attacker.take_damage(shock, self)
				var shove := attacker.global_position - global_position
				shove.y = 0.0
				if shove.length_squared() > 0.001:
					attacker.knockback(shove.normalized() * 7.5)
				GameManager.broadcast_arc([global_position + Vector3.UP * 1.1, attacker.global_position + Vector3.UP * 1.0], Color(1.0, 0.92, 0.35))
			# Acid Blood player mutation: splash nearby infected on real health hits.
			if not continuous and GameManager.has_player_mutation("acid_blood") and amount >= 2.0 and _acid_blood_cooldown <= 0.0:
				_acid_blood_cooldown = 1.5
				for node in get_tree().get_nodes_in_group("enemies"):
					var enemy := node as EnemyBase
					if enemy == null or enemy.health <= 0.0:
						continue
					if enemy.global_position.distance_to(global_position) <= 4.0:
						enemy.take_damage(28.0, self)
						var push := enemy.global_position - global_position
						push.y = 0.0
						if push.length_squared() > 0.001:
							enemy.knockback(push.normalized() * 5.0)
				GameManager.broadcast_blast(global_position + Vector3.UP * 0.9, 1.4, Color(0.62, 1.0, 0.25, 0.85))
			if health <= 0.0:
				_go_down()
		"turned":
			health = maxf(health - amount, 0.0)
			damaged.emit(amount)
			if health <= 0.0:
				_set_state("out")


## The host chooses the impulse. Only the movement owner applies it.
func pull_from_enemy(impulse: Vector3) -> void:
	if not Net.is_host():
		return
	var pull_scale := 0.3 if GameManager.has_player_mutation("hydro_skin") else 1.0
	if is_multiplayer_authority():
		_enemy_pull = impulse * pull_scale
	else:
		_receive_enemy_pull.rpc_id(get_multiplayer_authority(), impulse * pull_scale)


@rpc("any_peer", "call_remote", "reliable")
func _receive_enemy_pull(impulse: Vector3) -> void:
	if multiplayer.get_remote_sender_id() == 1 and is_multiplayer_authority():
		_enemy_pull = impulse


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
	_grace_left = REVIVE_GRACE
	_revive_grace_left = REVIVE_GRACE
	invulnerable = true
	if by == self:
		self_revives -= 1
		# A small suit buffer so a solo self-revive in acid rain isn't an
		# instant re-down.
		suit_integrity = maxf(suit_integrity, SELF_REVIVE_SUIT)
	else:
		GameManager.record_revive(by, self)
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
	if new_state != state and new_state in ["downed", "turned", "out"]:
		Perf.mark("player state " + new_state)
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
		_enemy_pull = Vector3.ZERO
		_applied_pull = Vector3.ZERO


## Host grants utility ownership. The owner receives only the presentation state.
func grant(item: String) -> void:
	if not Net.is_host():
		return
	if item == "tarp":
		has_tarp = true
		if not is_multiplayer_authority():
			_grant_tarp.rpc_id(get_multiplayer_authority())
	elif item.begins_with("weapon:"):
		var loot := RunLoot.find(get_tree())
		var id := ItemCatalog.id_for_weapon_path(item.trim_prefix("weapon:"))
		if id != "" and id != "disruptor":
			var at := loot.ground_at(self, -global_basis.z)
			loot.spawn_item(id, global_position if at == Vector3.INF else at)


## Pouch pickups (frag / shield dome) show the belt count, or FULL at the cap.
func _interact_text(target: Node) -> String:
	var pickup := target as WorldPickup
	if pickup and pickup.item and ItemCatalog.is_pouch(pickup.item.id):
		var holder := get_node_or_null("Head/Camera3D/WeaponHolder") as WeaponHolder
		if holder:
			var id := pickup.item.id
			var cap := ItemCatalog.pouch_cap(id)
			var label := ItemCatalog.definition(id).display_name
			if holder.pouch_full(id):
				return "%s pouch FULL (%d/%d)" % [label, cap, cap]
			return "Take %s (%d/%d)" % [label, holder.pouch_count(id), cap]
	return target.get_prompt(self)


## What the current interact target sells or holds, for the HUD stat card:
## {id, tier, price, source[, count]} or {} when it is not an item.
func targeted_item_info() -> Dictionary:
	if not is_instance_valid(_hold_target):
		return {}
	var pad := _hold_target as SupplyInteract
	if pad:
		var station := pad.get_parent() as SupplyStation
		if station:
			var offer := station.offer_for(pad.mode)
			if not offer.is_empty():
				return {"id": str(offer[0]), "tier": int(offer[1]), "price": int(offer[2]), "source": "vending"}
			if pad.mode == "ammo":
				return {"id": "ammo_box", "tier": 0, "price": 5, "source": "vending"}
		return {}
	var pickup := _hold_target as WorldPickup
	if pickup and pickup.item != null:
		return {"id": pickup.item.id, "tier": pickup.item.tier, "count": pickup.item.count, "price": 0, "source": "pickup"}
	return {}


@rpc("any_peer", "call_remote", "reliable")
func _grant_tarp() -> void:
	if multiplayer.get_remote_sender_id() == 1:
		has_tarp = true


# ------------------------------------------------------------------ interact
func _handle_interact(delta: float, loadout_input: bool) -> void:
	var pressed := not loadout_input and Input.is_action_pressed("interact")
	var best: Interactable = null
	var best_score := INF
	if state != "turned" and not GameManager.is_voting():
		var forward := -camera.global_basis.z
		for node in get_tree().get_nodes_in_group("interactables"):
			var it := node as Interactable
			if it == null or not it.is_visible_in_tree() or not it.can_interact(self):
				continue
			var self_revive := it.get_parent() == self and state == "downed"
			var target_position := it.global_position
			if it is WorldPickup:
				target_position = it.interact_point()
			var direction := target_position - camera.global_position
			var distance := global_position.distance_to(it.global_position)
			if distance > it.radius + (0.6 if it == _hold_target and _hold > 0.0 else 0.0):
				continue
			# Holding E on a target keeps it while it stays in reach, so a slight
			# look-away doesn't reset a 1 s hold (the decon "repair isn't working"
			# playtest bug). Up close the view cone also widens.
			var keep := it == _hold_target and _hold > 0.0 and distance <= it.radius + 0.6
			if not self_revive and not keep:
				var cone := lerpf(0.25, 0.65, clampf((distance - 0.6) / 1.4, 0.0, 1.0))
				if forward.dot(direction.normalized()) < cone:
					continue
				var query := PhysicsRayQueryParameters3D.create(camera.global_position, target_position, WORLD_LAYER, [get_rid()])
				var hit := get_world_3d().direct_space_state.intersect_ray(query)
				if not hit.is_empty() and hit.collider != it.get_parent():
					continue
			var alignment := forward.dot(direction.normalized())
			var score := distance - alignment
			if it is SupplyInteract and it.mode != "airdrop":
				# Let the crosshair pick the bay even when another one is a
				# little closer from an oblique angle.
				score = distance * 0.2 - alignment + (1.0 - alignment) * 5.0
			if score < best_score:
				best = it
				best_score = score
	if best != _hold_target:
		if is_instance_valid(_hold_target):
			if _hold_target is SupplyInteract and _hold > 0.0 and not _hold_done:
				_hold_target.action(self, "cancel")
			_hold_target.set_targeted(false)
		_hold_target = best
		_hold = 0.0
		interact_progress = 0.0
		if best:
			best.set_targeted(true)
	if best == null:
		if not pressed:
			_hold_done = false
		interact_prompt = ""
		interact_progress = 0.0
		return
	interact_prompt = "[%s] %s" % [BroadcastUI.input_hint("interact"), _interact_text(best)]
	var need := best.get_hold_time(self)
	if pressed and not _hold_done:
		if _hold == 0.0 and best is SupplyInteract:
			best.action(self, "begin")
		_hold += delta
		interact_progress = clampf(_hold / maxf(need,0.001),0,1)
		if _hold >= need and not _hold_done:
			_hold_done = true
			if best is WorldPickup:
				best.request(self)
			elif best is SupplyInteract:
				best.action(self, "finish")
			else:
				GameManager.interact(best, self)
	elif not pressed:
		if best is SupplyInteract and _hold > 0.0 and not _hold_done:
			best.action(self, "cancel")
		_hold = 0.0
		_hold_done = false
		interact_progress = 0.0


# ------------------------------------------------------------------ visuals
func _apply_state_visuals() -> void:
	_shown_state = state
	var body := get_node_or_null("BodyModel") as Node3D
	if body:
		body.visible = state in ["ok", "downed", "turned"]
	# Turned players keep their hazmat model, overlaid sickly green (PlayerModel).
	_turned_model.visible = false
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
	if look_locked:
		return
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


## Shared by damage, bleed-out and local UI. A dome also covers the ground.
func acid_hazard() -> String:
	if not WeatherManager.is_raining():
		return ""
	if WeaponProjectile.protects(global_position + Vector3.UP, get_tree()):
		return "shelter"
	if in_puddle:
		return "puddle"
	return "shelter" if sheltered else "rain"


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
		_exposure_sync_pending = true


## Client -> host: this player's shelter and puddle state changed.
@rpc("any_peer", "call_remote", "reliable")
func _report_exposure(is_sheltered: bool, is_in_puddle: bool) -> void:
	if Net.is_host() and multiplayer.get_remote_sender_id() == get_multiplayer_authority():
		_set_exposure(is_sheltered, is_in_puddle)


func _set_exposure(is_sheltered: bool, is_in_puddle: bool) -> void:
	if is_in_puddle and not in_puddle and is_multiplayer_authority() and WeatherManager.is_raining():
		Sound.play("splash_0", -11.0, 0.75)
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
const DamageNumbers := preload("res://weapons/damage_number.gd")

var _net_left := 0.0
var _vitals_left := 0.0
var _exposure_sync_pending := true
var _numbers: DamageNumbers


func _net_step(delta: float) -> void:
	if not Net.is_online() or not Net.can_send_run_rpc():
		return
	if not Net.is_host() and is_multiplayer_authority() and _exposure_sync_pending:
		_exposure_sync_pending = false
		_report_exposure.rpc_id(1, sheltered, in_puddle)
	_net_left -= delta
	if _net_left <= 0.0:
		_net_left = 1.0 / NET_RATE
		if is_multiplayer_authority():
			if Net.is_host():
				Net.rpc_to_run(_relay_transform, [global_position, rotation.y, head.rotation.x, velocity])
			else:
				_push_transform.rpc_id(1, global_position, rotation.y, head.rotation.x, velocity)
	if not Net.is_host():
		return
	_vitals_left -= delta
	if _vitals_left <= 0.0:
		_vitals_left = VITALS_RATE
		Net.rpc_to_run(_apply_vitals, [health, suit_integrity, state, bleed_left, tarp_raised, max_health, static_charge, invulnerable])


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _push_transform(pos: Vector3, yaw: float, pitch: float, vel: Vector3) -> void:
	if not Net.is_host() or multiplayer.get_remote_sender_id() != get_multiplayer_authority():
		return
	_apply_transform(pos, yaw, pitch, vel)
	Net.rpc_to_run(_relay_transform, [pos, yaw, pitch, vel])


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
	# Remote copies glide toward the latest network state instead of snapping
	# 20 times a second (see _smooth_remote).
	_net_target_pos = pos
	_net_target_yaw = yaw
	_net_target_pitch = pitch
	_net_age = 0.0
	velocity = vel
	if not _net_has_target or global_position.distance_to(pos) > 4.0:
		global_position = pos
		rotation.y = yaw
		head.rotation.x = pitch
	_net_has_target = true


var _net_target_pos := Vector3.ZERO
var _net_target_yaw := 0.0
var _net_target_pitch := 0.0
var _net_age := 0.0
var _net_has_target := false


## Every frame on remote copies: extrapolate a little along the synced
## velocity, then ease toward it. Hides the 20 Hz steps.
func _smooth_remote(delta: float) -> void:
	if not _net_has_target or is_multiplayer_authority():
		return
	_net_age += delta
	var predicted := _net_target_pos + velocity * minf(_net_age, 0.1)
	var blend := 1.0 - exp(-14.0 * delta)
	global_position = global_position.lerp(predicted, blend)
	rotation.y = lerp_angle(rotation.y, _net_target_yaw, blend)
	head.rotation.x = lerpf(head.rotation.x, _net_target_pitch, blend)


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _apply_vitals(hp: float, suit: float, new_state: String, bleed: float, tarp: bool, max_hp := 100.0, charge := 0.0, invuln := false) -> void:
	if Net.is_host() or multiplayer.get_remote_sender_id() != 1:
		return
	max_health = max_hp
	health = hp
	suit_integrity = suit
	static_charge = charge
	invulnerable = invuln
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
		Net.rpc_to_run(_apply_tarp, [value])
	else:
		_push_tarp.rpc_id(1, value)


@rpc("any_peer", "call_remote", "reliable")
func _push_tarp(value: bool) -> void:
	if not Net.is_host() or multiplayer.get_remote_sender_id() != get_multiplayer_authority():
		return
	tarp_raised = value and has_tarp and state == "ok" and not GameManager.is_voting()
	Net.rpc_to_run(_apply_tarp, [tarp_raised])


@rpc("any_peer", "call_remote", "reliable")
func _apply_tarp(value: bool) -> void:
	if multiplayer.get_remote_sender_id() != 1:
		return
	tarp_raised = value


var _hit_batch_depth := 0
var _hit_batch: Dictionary = {}


func begin_hit_batch() -> void:
	_hit_batch_depth += 1


func end_hit_batch() -> void:
	_hit_batch_depth -= 1
	if _hit_batch_depth == 0 and not _hit_batch.is_empty():
		_send_hit_batch(_hit_batch.values())
		_hit_batch.clear()


func notify_hit(killed: bool, critical: bool, point: Vector3, amount: int, enemy_id := 0) -> void:
	if not Net.is_host():
		return
	if _hit_batch_depth == 0:
		_send_hit_batch([[killed, critical, point, amount, enemy_id]])
		return
	var key := enemy_id if enemy_id != 0 else -1 - _hit_batch.size()
	if _hit_batch.has(key):
		var row: Array = _hit_batch[key]
		row[0] = row[0] or killed
		row[1] = row[1] or critical
		row[3] += amount
	else:
		_hit_batch[key] = [killed, critical, point, amount, enemy_id]


func _send_hit_batch(hits: Array) -> void:
	var peer := get_multiplayer_authority()
	if peer == 1:
		_apply_hits(hits)
	elif Net.run_peers.has(peer):
		var loot := RunLoot.find(get_tree())
		_receive_hits.rpc_id(peer, loot.run_id, hits)


@rpc("any_peer", "call_remote", "reliable")
func _receive_hits(run: int, hits: Array) -> void:
	var loot := RunLoot.find(get_tree())
	if multiplayer.get_remote_sender_id() == 1 and loot and run == loot.run_id:
		_apply_hits(hits)


func _apply_hits(hits: Array) -> void:
	var killed := false
	var critical := false
	for row: Array in hits:
		killed = killed or row[0]
		critical = critical or row[1]
		if row[3] > 0:
			show_damage(row[2], row[3], row[1], row[4])
	local_hit(killed, critical, Vector3.ZERO, 0)


## Owner of the shot: hit marker, floating number and the headshot sting.
func local_hit(killed: bool, critical: bool, point: Vector3, amount: int, enemy_id := 0) -> void:
	GameManager.combat_hit.emit(killed, critical)
	if amount > 0:
		show_damage(point, amount, critical, enemy_id)
	# One headshot sting per shot even when several pellets crit.
	if critical and Time.get_ticks_msec() - _last_headshot_ms > 60:
		_last_headshot_ms = Time.get_ticks_msec()
		Sound.play("headshot", -10.0)


## A damage number at the point the shot landed. Rapid hits on the same enemy
## stack into one number, which is why the enemy's net id comes along: the
## stacking has to happen on the shooter's machine, whichever peer that is.
func show_damage(point: Vector3, amount: int, critical: bool, enemy_id := 0) -> void:
	if Net.dedicated or not is_inside_tree():
		return
	if not is_instance_valid(_numbers):
		var parent := get_tree().current_scene
		if parent == null:
			parent = get_parent()
		_numbers = parent.get_node_or_null("DamageNumbers/Markers") as DamageNumbers
		if _numbers == null:
			if DisplayServer.get_name() == "headless":
				return
			var layer := CanvasLayer.new()
			layer.name = "DamageNumbers"
			# Godot uses sibling indices within a layer. Append under the run
			# to clear RetroScreen's layer-5 passes and stay below the layer-6 HUD.
			layer.layer = 5
			_numbers = DamageNumbers.new()
			_numbers.name = "Markers"
			layer.add_child(_numbers)
			parent.add_child(layer)
	_numbers.add_hit(point, amount, critical, enemy_id)
