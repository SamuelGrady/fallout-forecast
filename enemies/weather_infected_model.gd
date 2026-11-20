extends "res://enemies/infected_model.gd"
## Weather silhouettes reuse the animated bones, mutation trim and corpse path.

static var _rock: SphereMesh
static var _shard: CylinderMesh
static var _pipe: CylinderMesh

var charge_amount := 0.0
var _sparks: Node3D
var _spark_offset := 0.0


func _build_model() -> void:
	if _rock == null:
		_rock = SphereMesh.new()
		_rock.radius = 0.5
		_rock.height = 1.0
		_rock.radial_segments = 7
		_rock.rings = 3
		_shard = CylinderMesh.new()
		_shard.top_radius = 0.0
		_shard.bottom_radius = 0.5
		_shard.height = 1.0
		_shard.radial_segments = 4
		_shard.rings = 0
		_pipe = CylinderMesh.new()
		_pipe.top_radius = 0.5
		_pipe.bottom_radius = 0.5
		_pipe.height = 1.0
		_pipe.radial_segments = 6
		_pipe.rings = 0
	_body.add_child(_head)
	match _kind:
		"sleet": _sleet()
		"hailstone": _hailstone()
		"undertow": _undertow()
		"static": _static_infected()
		"smog": _smog()
		"thunderhead": _thunderhead()


func _sleet() -> void:
	var ice := Color("#bbebff")
	var blue := Color("#4b8cb3")
	var glint := Color("#d8faff")
	_reach = 0.7
	_shape(_body, _rock, Vector3(0, .72, .06), Vector3(.35, .37, .85), blue)
	for i in 4:
		var spike := _shape(_body, _shard, Vector3((i % 2 - .5) * .23, .92, .36 - i * .16), Vector3(.26, .46, .29), ice)
		spike.rotation.x = .6
	_head.position = Vector3(0, .78, -.49)
	_shape(_head, _rock, Vector3.ZERO, Vector3(.39, .34, .47), ice)
	_eyes(.115, .025, -.222, glint, .05)
	_piece(_head, Vector3(0, -.075, -.205), Vector3(.25, .045, .036), Color("#22425e"))
	_build_limbs(.245, .76, .48, .35, .36, .12, ice, blue)
	for arm in limbs:
		arm.rotation.z = signf(arm.position.x) * .38
	for claw in _elbows:
		_shape(claw, _shard, Vector3(.014, -.42, -.05), Vector3(.11, .23, .13), glint).rotation.x = PI


func _hailstone() -> void:
	var snow := Color("#dbe5e4")
	var granite := Color("#617684")
	var core := Color("#ff7d53")
	_reach = 0.25
	_shape(_body, _rock, Vector3(0, 1.38, 0), Vector3(1.38, 1.45, 1.04), granite)
	for side in [-1.0, 1.0]:
		var shield := _shape(_body, _rock, Vector3(side * .39, 1.58, -.42), Vector3(.91, .96, .51), snow)
		shield.rotation.z = side * .38
		_piece(_body, Vector3(side * .38, 1.53, -.65), Vector3(.062, .24, .048), granite).rotation.z = side * .68
		_shape(_body, _rock, Vector3(side * .28, .99, -.39), Vector3(.55, .52, .43), snow.darkened(.16))
		_shape(_body, _rock, Vector3(side * .33, 1.44, .39), Vector3(.47, .75, .38), granite.darkened(.24))
	_shape(_body, _rock, Vector3(0, 1.43, .53), Vector3(.56, .82, .32), core, true)
	_piece(_body, Vector3(0, 1.44, .70), Vector3(.16, .44, .035), Color("#ffe0a4"), true)
	_head.position = Vector3(0, 2.02, -.25)
	_shape(_head, _rock, Vector3.ZERO, Vector3(.68, .49, .57), snow)
	_piece(_head, Vector3(0, -.03, -.25), Vector3(.49, .15, .09), granite.darkened(.5))
	_eyes(.15, -.03, -.306, core, .076)
	_build_limbs(.76, 1.64, .91, .65, .56, .4, snow, granite)


func _undertow() -> void:
	var skin := Color("#419e9e")
	var wet := Color("#173f53")
	var foam := Color("#76ffec")
	_reach = .24
	_shape(_body, _rock, Vector3(0, 1.05, 0), Vector3(.52, .74, .39), wet)
	_shape(_body, _rock, Vector3(0, 1.41, 0), Vector3(.67, .45, .43), skin)
	_head.position = Vector3(0, 1.49, -.21)
	_shape(_head, _rock, Vector3(0, .10, 0), Vector3(.47, .62, .43), wet)
	for i in 3:
		var fin := _shape(_head, _shard, Vector3(0, .28 - .11 * i, .13 + .08 * i), Vector3(.23, .36, .29), skin)
		fin.rotation.x = 1.2
	for side in [-1.0, 1.0]:
		var fin := _shape(_head, _shard, Vector3(side * .23, .08, .025), Vector3(.20, .28, .16), skin)
		fin.rotation.z = -side * 1.1
	_eyes(.13, .12, -.20, foam, .075)
	_piece(_head, Vector3(0, -.02, -.19), Vector3(.30, .068, .035), Color("#101f33"))
	_build_limbs(.35, 1.42, .67, .60, .69, .16, wet, skin)
	for i in [0, 2]:
		limbs[i].rotation.z = signf(limbs[i].position.x) * .15
	for claw in _elbows:
		for finger in 3:
			_shape(claw, _shard, Vector3((finger - 1) * .095, -.83, -.035), Vector3(.087, .26 - absf(finger - 1) * .06, .11), foam.darkened(.22)).rotation.x = PI


func _static_infected() -> void:
	var rubber := Color("#43364b")
	var copper := Color("#9c6143")
	var volt := Color("#fff36c")
	_reach = .57
	_piece(_body, Vector3(0, 1.12, 0), Vector3(.53, .76, .42), rubber)
	_piece(_body, Vector3(0, 1.31, -.23), Vector3(.36, .28, .10), copper)
	_piece(_body, Vector3(0, 1.31, -.29), Vector3(.20, .12, .03), volt, true)
	for side in [-1.0, 1.0]:
		var antenna := _shape(_body, _pipe, Vector3(side * .36, 1.77, .08), Vector3(.09, .79, .09), copper)
		antenna.rotation.z = -side * .42
		_shape(_body, _rock, Vector3(side * .51, 2.13, .08), Vector3(.24, .24, .24), volt, true)
		_piece(_body, Vector3(side * .31, 1.51, .06), Vector3(.26, .29, .47), copper)
	_head.position = Vector3(0, 1.70, -.09)
	_shape(_head, _rock, Vector3.ZERO, Vector3(.44, .49, .43), rubber)
	_piece(_head, Vector3(0, .045, -.20), Vector3(.35, .115, .08), volt, true)
	_build_limbs(.36, 1.41, .73, .36, .33, .17, rubber, copper)
	_sparks = Node3D.new()
	_body.add_child(_sparks)
	var points := [Vector2(-.28, -.06), Vector2(-.02, .12), Vector2(.045, -.13), Vector2(.30, .02)]
	for i in points.size() - 1:
		var a: Vector2 = points[i]
		var b: Vector2 = points[i + 1]
		var mid := (a + b) * .5
		var bolt := _piece(_sparks, Vector3(mid.x, mid.y, 0), Vector3(a.distance_to(b), .031, .023), volt, true)
		bolt.rotation.z = (b - a).angle()
	MeshMerge.merge_children(_sparks, false)
	_sparks.hide()


func _smog() -> void:
	var soot := Color("#433c45")
	var ash := Color("#766573")
	var sour := Color("#dfed63")
	_reach = .25
	_shape(_body, _rock, Vector3(0, 1.12, -.03), Vector3(1.21, 1.37, 1.01), soot)
	_shape(_body, _rock, Vector3(0, 1.00, -.24), Vector3(.98, .86, .86), ash)
	for side in [-1.0, 1.0]:
		var y: float = 1.62 + side * .14
		_shape(_body, _pipe, Vector3(side * .36, y, .30), Vector3(.32, .95, .40), soot)
		_shape(_body, _pipe, Vector3(side * .36, y + .49, .30), Vector3(.44, .17, .46), ash)
		_shape(_body, _pipe, Vector3(side * .36, y + .58, .30), Vector3(.28, .025, .31), sour, true)
	_head.position = Vector3(0, 1.58, -.44)
	_shape(_head, _rock, Vector3.ZERO, Vector3(.66, .50, .47), soot)
	_shape(_head, _pipe, Vector3(0, -.04, -.27), Vector3(.45, .37, .36), ash).rotation.x = PI * .5
	_shape(_head, _pipe, Vector3(0, -.04, -.46), Vector3(.32, .03, .24), sour, true).rotation.x = PI * .5
	_eyes(.17, .123, -.21, Color("#ff9d43"), .066)
	_build_limbs(.56, 1.37, .65, .38, .42, .21, soot, ash)


func _thunderhead() -> void:
	var cloud := Color("#4c506e")
	var shadow := Color("#25293d")
	var flash := Color("#ffa15d")
	_reach = .35
	_shape(_body, _rock, Vector3(0, 1.14, 0), Vector3(1.36, 1.34, 1.18), shadow)
	for i in 7:
		var angle := TAU * i / 7.0
		var lump := Vector3(cos(angle) * .45, 1.21 + sin(angle * 3.0) * .20, sin(angle) * .37)
		_shape(_body, _rock, lump, Vector3(.84, .94, .85), cloud.lightened(i * .033))
	_shape(_body, _rock, Vector3(0, 1.73, .03), Vector3(1.14, .8, 1.13), cloud.lightened(.17))
	_head.position = Vector3(0, 1.26, -.65)
	_shape(_head, _rock, Vector3.ZERO, Vector3(.64, .50, .46), shadow)
	_eyes(.15, .05, -.21, flash, .091)
	for i in 3:
		_piece(_head, Vector3((i - 1) * .11, -.10, -.215), Vector3(.11, .034, .035), flash, true).rotation.z = .45 if i != 1 else -.56
	_build_limbs(.69, 1.25, .59, .30, .33, .2, cloud, shadow)


func _eyes(x: float, y: float, z: float, color: Color, size: float) -> void:
	for side in [-1.0, 1.0]:
		_piece(_head, Vector3(side * x, y, z), Vector3(size * 1.35, size, .05), color, true)


func _build_limbs(width: float, shoulder: float, hip: float, upper: float, fore: float, girth: float, outer: Color, inner: Color) -> void:
	for side in [-1.0, 1.0]:
		var arm := Node3D.new()
		arm.position = Vector3(side * width, shoulder, 0)
		_body.add_child(arm)
		_shape(arm, _rock, Vector3(0, -upper * .39, 0), Vector3(girth * 1.35, upper * 1.28, girth * 1.23), outer)
		var elbow := Node3D.new()
		elbow.position.y = -upper
		arm.add_child(elbow)
		_piece(elbow, Vector3(0, -fore * .43, -.025), Vector3(girth * .78, fore, girth), inner)
		_shape(elbow, _rock, Vector3(0, -fore, -.035), Vector3(girth * 1.42, girth * 1.45, girth * 1.29), outer)
		limbs.append(arm)
		_elbows.append(elbow)

		var leg := Node3D.new()
		leg.position = Vector3(side * minf(width * .57, .33), hip, .08)
		_body.add_child(leg)
		_piece(leg, Vector3(0, -hip * .23, .026), Vector3(girth, hip * .52, girth * 1.24), inner)
		var knee := Node3D.new()
		knee.position = Vector3(0, -hip * .47, .04)
		leg.add_child(knee)
		_piece(knee, Vector3(0, -hip * .23, 0), Vector3(girth * .88, hip * .49, girth), outer)
		_piece(knee, Vector3(0, -hip * .49, -.075), Vector3(girth * 1.21, .09, girth * 1.4 + .10), inner.darkened(.28))
		limbs.append(leg)
		_knees.append(knee)


func elite_crest_height() -> float:
	match _kind:
		"sleet": return 1.40
		"undertow": return 2.03
		"smog", "thunderhead": return 2.35
	return 2.47


func _setup_gait() -> void:
	super._setup_gait()
	match _kind:
		"sleet": _gait.merge({"freq": 5.5, "leg": 0.85, "sway": .14, "lean": -.15}, true)
		"hailstone": _gait.merge({"freq": 1.8, "leg": .36, "bounce": .07}, true)
		"undertow": _gait.merge({"freq": 2.2, "arm": .95, "lean": -.17}, true)
		"static": _gait.merge({"freq": 5.0, "arm": .7, "sway": .12}, true)
		"smog": _gait.merge({"freq": 1.8, "bounce": .08, "sway": .13}, true)
		"thunderhead": _gait.merge({"freq": 3.3, "bounce": .11, "sway": .12}, true)


func _process(delta: float) -> void:
	super._process(delta)
	if _kind == "thunderhead":
		_body.scale = Vector3.ONE * (1.0 + charge_amount * (.53 + .035 * sin(_clock * 12.0)))
		_body.position.y += charge_amount * .10
	if _sparks:
		_spark_offset += delta * (5.0 + charge_amount * 10.0)
		_sparks.visible = fmod(_spark_offset, 1.0) < (.34 + charge_amount * .41)
		_sparks.position = Vector3(.52 * sin(_spark_offset * 17.0), 1.55 + .48 * cos(_spark_offset * 13.0), -.42)
		_sparks.rotation.z = _spark_offset * 4.0
