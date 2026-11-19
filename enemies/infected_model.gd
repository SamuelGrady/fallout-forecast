extends Node3D
## Original chunky infected silhouettes with articulated limbs.
var limbs: Array[Node3D] = []
var _clock := 0.0
var _hurt := 0.0
var _body: Node3D
var _enemy: EnemyBase

func _ready() -> void:
	_enemy = get_parent() as EnemyBase
	var kind := _enemy.data.display_name.to_lower()
	var gutter := kind == "gutter"
	var mister := kind == "mister"
	var skin := Color("#b5df68") if not mister else Color("#d2b0db")
	var coat := Color("#d9613c") if gutter else (Color("#76599e") if mister else Color("#337c87"))
	_body = Node3D.new()
	add_child(_body)
	_piece(_body, Vector3(0, 1.05, 0), Vector3(.62, .7, .35), coat)
	_piece(_body, Vector3(0, 1.63, -.04), Vector3(.43, .45, .4), skin)
	_piece(_body, Vector3(0, 1.88, .02), Vector3(.5, .12, .46), coat.darkened(.5))
	for side in [-1.0, 1.0]:
		_piece(_body, Vector3(side*.12, 1.68, -.25), Vector3(.09, .07, .05), Color("#ffed8a"), true)
		var arm := Node3D.new()
		arm.position = Vector3(side*.43, 1.32, 0)
		_body.add_child(arm)
		_piece(arm, Vector3(0, -.25, -.08), Vector3(.2, .55, .22), coat)
		_piece(arm, Vector3(0, -.53, -.15), Vector3(.23, .18, .24), skin)
		limbs.append(arm)
		var leg := Node3D.new()
		leg.position = Vector3(side*.19, .72, 0)
		_body.add_child(leg)
		_piece(leg, Vector3(0, -.3, 0), Vector3(.24, .6, .26), Color("#273143"))
		_piece(leg, Vector3(0, -.61, -.09), Vector3(.28, .17, .42), Color("#111b28"))
		limbs.append(leg)
	if mister:
		for side in [-1.0, 1.0]:
			_piece(_body, Vector3(side*.38, 1.18, .28), Vector3(.38, .6, .38), Color("#c6f075"), true)
		scale = Vector3(1.25, 1.15, 1.15)
	if gutter:
		scale = Vector3(1.05, .82, 1.0)
		_body.rotation.x = -.25
	_enemy.damaged.connect(func(_amount, _health): _hurt = 1.0)

func _piece(parent: Node3D, at: Vector3, size: Vector3, color: Color, glow := false) -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.position = at
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = .9
	material.emission_enabled = glow
	material.emission = color
	material.emission_energy_multiplier = .7
	mesh.material_override = material
	parent.add_child(mesh)

func _process(delta: float) -> void:
	_clock += delta * (3.0 + Vector2(_enemy.velocity.x, _enemy.velocity.z).length()*2.0)
	_hurt = move_toward(_hurt, 0.0, delta*5.0)
	for i in limbs.size():
		limbs[i].rotation.x = sin(_clock + (PI if i > 1 else 0.0)) * .45
	_body.position.y = absf(sin(_clock))*.045
	_body.rotation.z = sin(_clock*.5)*.04 + _hurt*.16
