extends Node3D
## Local lightning effects for WeatherManager.lightning_struck: a sky flash
## (through the parent WeatherFX), a jagged bolt at the strike, outlines on
## every enemy within reveal_radius of the local camera for reveal_time, and
## thunder 0.5-2 s later depending on distance. The seed from the host makes
## the bolt shape the same on every client.
##
## The thunder is synthesized once at startup (filtered noise with a crack and
## a rumble), so it needs no audio file. Swap in a recorded clip later by
## setting thunder_stream.

signal flashed(position: Vector3)

@export var reveal_radius := 40.0
@export var reveal_time := 2.0
@export var bolt_time := 0.25
@export var thunder_stream: AudioStream
@export var thunder_volume_db := -10.0

var _thunder_player := AudioStreamPlayer.new()
var _bolt_material := StandardMaterial3D.new()


func _ready() -> void:
	WeatherManager.lightning_struck.connect(_on_lightning_struck)
	if thunder_stream == null:
		thunder_stream = _make_thunder()
	_thunder_player.stream = thunder_stream
	_thunder_player.volume_db = thunder_volume_db
	add_child(_thunder_player)

	_bolt_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_bolt_material.albedo_color = Color(0.9, 0.95, 1.0)
	_bolt_material.disable_fog = true


func _on_lightning_struck(position: Vector3, strike_seed: int) -> void:
	var fx := get_parent()
	if fx and "flash" in fx:
		fx.flash = Settings.flash_scale()
	flashed.emit(position)

	var rng := RandomNumberGenerator.new()
	rng.seed = strike_seed
	_spawn_bolt(position, rng)

	var listener := position
	var camera := get_viewport().get_camera_3d()
	if camera:
		listener = camera.global_position
		for enemy in get_tree().get_nodes_in_group("enemies"):
			if enemy.global_position.distance_to(listener) <= reveal_radius and enemy.has_method("reveal"):
				enemy.reveal(reveal_time)

	var distance := listener.distance_to(position)
	var delay := clampf(distance / 343.0 * 10.0, 0.5, 2.0)
	_thunder_player.volume_db = thunder_volume_db - clampf(distance / 10.0, 0.0, 8.0)
	get_tree().create_timer(delay).timeout.connect(_thunder_player.play)


func _spawn_bolt(ground: Vector3, rng: RandomNumberGenerator) -> void:
	var bolt := Node3D.new()
	add_child(bolt)
	var top := ground + Vector3(rng.randf_range(-6.0, 6.0), 60.0, rng.randf_range(-6.0, 6.0))
	var segments := 9
	var previous := top
	for i in range(1, segments + 1):
		var t := float(i) / segments
		var point := top.lerp(ground, t)
		if i < segments:
			point += Vector3(rng.randf_range(-2.5, 2.5), 0.0, rng.randf_range(-2.5, 2.5))
		_add_segment(bolt, previous, point, 0.25 * (1.0 - t * 0.5))
		previous = point
	get_tree().create_timer(bolt_time).timeout.connect(bolt.queue_free)


func _add_segment(parent: Node3D, from: Vector3, to: Vector3, width: float) -> void:
	var segment := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(width, from.distance_to(to), width)
	box.material = _bolt_material
	segment.mesh = box
	segment.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(segment)
	segment.global_position = (from + to) * 0.5
	var up := (to - from).normalized()
	var side := up.cross(Vector3.FORWARD)
	if side.length_squared() < 0.001:
		side = up.cross(Vector3.RIGHT)
	segment.global_basis = Basis(side.normalized(), up, side.normalized().cross(up)).orthonormalized()


## A few seconds of thunder: a sharp crack, then a low rumble that rolls off.
func _make_thunder() -> AudioStreamWAV:
	var rate := 22050
	var seconds := 4.0
	var count := int(rate * seconds)
	var data := PackedByteArray()
	data.resize(count * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1987
	var low := 0.0
	var lower := 0.0
	for i in count:
		var t := float(i) / rate
		var white := rng.randf_range(-1.0, 1.0)
		low += (white - low) * 0.08      # rumble
		lower += (low - lower) * 0.05    # deeper rumble
		var crack := white * exp(-t * 18.0) * 0.6
		var roll := 1.0 + 0.5 * sin(t * 5.0 + sin(t * 1.3) * 2.0)
		var rumble := (low * 2.5 + lower * 4.0) * exp(-t * 0.9) * minf(t * 20.0, 1.0) * roll
		var sample := clampf(crack + rumble, -1.0, 1.0)
		data.encode_s16(i * 2, int(sample * 32000.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.stereo = false
	wav.data = data
	return wav
