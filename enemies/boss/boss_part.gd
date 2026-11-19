extends StaticBody3D
## A hittable piece of Cumulus (a sac or the core). Guns find it through the
## "boss_parts" group; damage goes to the boss, which decides what it does.

var boss: Node
var index := -1
var _mesh: MeshInstance3D
var _flash_left := 0.0


func _ready() -> void:
	add_to_group("boss_parts")
	collision_layer = 1 << 2
	collision_mask = 0
	for c in get_children():
		if c is MeshInstance3D:
			_mesh = c


func take_damage(amount: float, source: Node = null) -> void:
	if boss:
		boss.damage_part(index, amount, source)


func hit_flash() -> void:
	_flash_left = 0.08
	if _mesh:
		_mesh.material_overlay = _flash_material()


func reveal(_seconds: float) -> void:
	pass


func _process(delta: float) -> void:
	if _flash_left > 0.0:
		_flash_left -= delta
		if _flash_left <= 0.0 and _mesh:
			_mesh.material_overlay = null


static var _flash: StandardMaterial3D
static func _flash_material() -> StandardMaterial3D:
	if _flash == null:
		_flash = StandardMaterial3D.new()
		_flash.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_flash.albedo_color = Color(1, 1, 1, 0.6)
		_flash.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_flash.grow = true
		_flash.grow_amount = 0.05
	return _flash
