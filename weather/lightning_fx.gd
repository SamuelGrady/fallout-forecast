extends Node3D
## Local lightning effects for WeatherManager:
## - lightning_struck (item / targeted strikes): a sky lift (through parent
##   WeatherFX), a crisp branching bolt with a ground flash and tactical shock
##   ring, outlines on infected near the strike, and loud thunder.
## - ambient_lightning_struck (natural storm lightning): an atmospheric bolt,
##   softer sky flash and shake, subtle ground flash/sparks without the tactical
##   ring, and softer rolling thunder — never revealing or hurting enemies.
## The seed from the host makes the bolt shape the same on every client.
##
## Thunder goes through Sound (a fresh stream-mode player per strike, owned by
## the Sound autoload), so overlapping strikes, a freed LightningFX or the Web
## audio path can't drop it. Close strikes crack almost at once (~0.05 s);
## distant ones lag slightly (up to 0.35 s) and sit a few dB lower.

signal flashed(position: Vector3)

@export var reveal_radius := 22.0
@export var reveal_time := 2.5
@export var bolt_time := 0.32
## Peak thunder level for a strike at the listener, before Sound's trims.
@export var thunder_volume_db := -1.0

const CORE_COLOR := Color(0.93, 1.0, 0.97, 0.99)
const SHEATH_COLOR := Color(0.55, 0.95, 1.0, 0.32)
const IMPACT_COLOR := Color(0.7, 1.0, 0.55, 0.6)

static var _segment_mesh: BoxMesh
static var _ring_mesh: TorusMesh


func _ready() -> void:
	WeatherManager.lightning_struck.connect(_on_lightning_struck)
	WeatherManager.ambient_lightning_struck.connect(_on_ambient_lightning_struck)
	if _segment_mesh == null:
		_segment_mesh = BoxMesh.new()
		_segment_mesh.size = Vector3.ONE
	if _ring_mesh == null:
		_ring_mesh = TorusMesh.new()
		_ring_mesh.inner_radius = 0.86
		_ring_mesh.outer_radius = 1.0
		_ring_mesh.rings = 28
		_ring_mesh.ring_segments = 4


func _exit_tree() -> void:
	if WeatherManager.lightning_struck.is_connected(_on_lightning_struck):
		WeatherManager.lightning_struck.disconnect(_on_lightning_struck)
	if WeatherManager.ambient_lightning_struck.is_connected(_on_ambient_lightning_struck):
		WeatherManager.ambient_lightning_struck.disconnect(_on_ambient_lightning_struck)


func _on_lightning_struck(position: Vector3, strike_seed: int) -> void:
	if Net.dedicated or DisplayServer.get_name() == "headless":
		return
	Perf.mark("lightning strike")
	Juice.shake(0.45, position)
	var fx := get_parent()
	if fx and "flash" in fx:
		fx.flash = maxf(fx.flash, Settings.flash_scale())
	flashed.emit(position)

	var rng := RandomNumberGenerator.new()
	rng.seed = strike_seed
	_spawn_bolt(position, rng)
	_spawn_impact(position, true)

	for enemy in get_tree().get_nodes_in_group("enemies"):
		if enemy.global_position.distance_to(position) <= reveal_radius and enemy.has_method("reveal"):
			enemy.reveal(reveal_time)

	_schedule_thunder(position, rng, 0.0)


func _on_ambient_lightning_struck(position: Vector3, strike_seed: int) -> void:
	if Net.dedicated or DisplayServer.get_name() == "headless":
		return
	Perf.mark("ambient lightning strike")
	Juice.shake(0.22, position)
	var fx := get_parent()
	if fx and "flash" in fx:
		fx.flash = maxf(fx.flash, 0.65 * Settings.flash_scale())

	var rng := RandomNumberGenerator.new()
	rng.seed = strike_seed
	_spawn_bolt(position, rng)
	_spawn_impact(position, false)
	_schedule_thunder(position, rng, -3.0)


func _schedule_thunder(position: Vector3, rng: RandomNumberGenerator, volume_offset_db: float = 0.0) -> void:
	var listener := position
	var camera := get_viewport().get_camera_3d()
	if camera:
		listener = camera.global_position
	var distance := listener.distance_to(position)
	# Sound travels ~343 m/s: close strikes crack right away, far ones lag a touch.
	var delay := clampf(0.05 + distance / 343.0, 0.05, 0.35)
	var level := thunder_volume_db + volume_offset_db - clampf(distance / 18.0, 0.0, 7.0)
	var pitch := rng.randf_range(0.93, 1.06)
	# Bound to the Sound autoload so the cue survives this node being freed.
	get_tree().create_timer(delay, false).timeout.connect(Sound.play_thunder.bind(level, pitch))


func _spawn_bolt(ground: Vector3, rng: RandomNumberGenerator) -> void:
	var bolt := Node3D.new()
	add_child(bolt)
	var top := ground + Vector3(rng.randf_range(-7.0, 7.0), 60.0, rng.randf_range(-7.0, 7.0))
	var segments := 12
	var points: Array[Vector3] = [top]
	for i in range(1, segments + 1):
		var t := float(i) / segments
		var point := top.lerp(ground, t)
		if i < segments:
			var jag := 2.8 * (1.0 - t * 0.6)
			point += Vector3(rng.randf_range(-jag, jag), rng.randf_range(-0.8, 0.8), rng.randf_range(-jag, jag))
		points.append(point)
	for i in range(1, points.size()):
		var t := float(i) / segments
		_add_channel(bolt, points[i - 1], points[i], lerpf(0.2, 0.09, t))
	# Forks: thinner, shorter, tapering off the main channel.
	var forks := rng.randi_range(2, 4)
	for f in forks:
		var start_index := rng.randi_range(2, segments - 3)
		var from: Vector3 = points[start_index]
		var away := Vector3(rng.randf_range(-1.0, 1.0), 0.0, rng.randf_range(-1.0, 1.0)).normalized()
		var steps := rng.randi_range(2, 4)
		var width := 0.08
		for s in steps:
			var to := from + away * rng.randf_range(1.6, 3.4) + Vector3.DOWN * rng.randf_range(2.0, 4.2) \
					+ Vector3(rng.randf_range(-0.8, 0.8), 0.0, rng.randf_range(-0.8, 0.8))
			_add_channel(bolt, from, to, width)
			from = to
			width *= 0.65
	# Flicker like a real return stroke: on, off, on, fade.
	var tween := bolt.create_tween()
	tween.tween_interval(0.06)
	tween.tween_callback(bolt.hide)
	tween.tween_interval(0.035)
	tween.tween_callback(bolt.show)
	tween.tween_interval(maxf(bolt_time - 0.2, 0.05))
	tween.tween_method(_fade_pieces.bind(bolt.get_children()), 0.0, 1.0, 0.1)
	tween.tween_callback(bolt.queue_free)


func _fade_pieces(value: float, pieces: Array) -> void:
	for piece in pieces:
		if is_instance_valid(piece):
			(piece as GeometryInstance3D).transparency = value


## One channel piece: a bright core with a faint wider sheath around it.
func _add_channel(parent: Node3D, from: Vector3, to: Vector3, width: float) -> void:
	_add_segment(parent, from, to, width, ShotFX._unshaded(CORE_COLOR))
	_add_segment(parent, from, to, width * 3.2, ShotFX._unshaded(SHEATH_COLOR))


func _add_segment(parent: Node3D, from: Vector3, to: Vector3, width: float, material: Material) -> void:
	var length := from.distance_to(to)
	if length < 0.01:
		return
	var segment := MeshInstance3D.new()
	segment.mesh = _segment_mesh
	segment.material_override = material
	segment.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(segment)
	segment.global_position = (from + to) * 0.5
	var up := (to - from) / length
	var side := up.cross(Vector3.FORWARD)
	if side.length_squared() < 0.001:
		side = up.cross(Vector3.RIGHT)
	side = side.normalized()
	segment.global_basis = Basis(side * width, up * length, side.cross(up).normalized() * width)


## Ground impact: optional expanding tactical shock ring, sparks, a short puff
## and (desktop) a brief local light that fades out instead of a full-scene sun pop.
func _spawn_impact(at: Vector3, show_ring: bool = true) -> void:
	var world := get_tree().current_scene
	if world == null:
		world = self
	if show_ring:
		var ring := MeshInstance3D.new()
		ring.mesh = _ring_mesh
		ring.material_override = ShotFX._unshaded(IMPACT_COLOR)
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(ring)
		ring.global_position = at + Vector3.UP * 0.08
		ring.scale = Vector3(0.4, 0.5, 0.4)
		var tween := ring.create_tween().set_parallel(true)
		tween.tween_property(ring, "scale", Vector3(6.5, 0.5, 6.5), 0.38).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_property(ring, "transparency", 1.0, 0.38)
		tween.chain().tween_callback(ring.queue_free)
	ShotFX.sparks(world, at + Vector3.UP * 0.2, Vector3.UP, 14 if show_ring else 8)
	ShotFX.puff(world, at + Vector3.UP * 0.25, Color(CORE_COLOR, 0.7), 0.7 if show_ring else 0.45, 0.25)
	if OS.has_feature("web"):
		return
	var light := OmniLight3D.new()
	light.light_color = Color(0.78, 0.92, 1.0)
	light.light_energy = (7.0 if show_ring else 4.5) * Settings.flash_scale()
	light.omni_range = 18.0 if show_ring else 14.0
	light.omni_attenuation = 1.4
	light.shadow_enabled = false
	add_child(light)
	light.global_position = at + Vector3.UP * 2.5
	var fade := light.create_tween()
	fade.tween_interval(0.05)
	fade.tween_property(light, "light_energy", 0.0, 0.4).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	fade.tween_callback(light.queue_free)
