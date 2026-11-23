extends "res://tools/levels/level_builder.gd"

const HALF_EXTENT := 50.0
const WALL_THICKNESS := 0.5
const WALL_HEIGHT := 5.0


func build() -> void:
	district = "sandbox"
	begin_map("Sandbox", false)
	# The texture repeats every two meters and contains two checks per axis.
	var grid := surface("#ffffff", "checkerboard", 0.5)
	grid.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS_ANISOTROPIC
	grid.set_meta("storm_wet_surface", true)
	section("Floor")
	box(Vector3(0, -0.5, 0), Vector3(2.0 * HALF_EXTENT, 1, 2.0 * HALF_EXTENT), grid)
	build_walls(grid)
	build_shelter()
	build_range()
	markers()
	bake_map()


func build_walls(grid: StandardMaterial3D) -> void:
	section("Bounds")
	var span := 2.0 * HALF_EXTENT
	var wall_center := HALF_EXTENT + WALL_THICKNESS * 0.5
	for side: float in [-wall_center, wall_center]:
		box(Vector3(side, WALL_HEIGHT * 0.5, 0), Vector3(WALL_THICKNESS, WALL_HEIGHT, span), grid)
		box(Vector3(0, WALL_HEIGHT * 0.5, side), Vector3(span + 2.0 * WALL_THICKNESS, WALL_HEIGHT, WALL_THICKNESS), grid)


func build_shelter() -> void:
	var center := Vector3(-12, 0, -10)
	var frame := paint("#59636c")
	section("ShelterPosts")
	for x: float in [-2.8, 2.8]:
		for z: float in [-2.8, 2.8]:
			box(center + Vector3(x, 1.6, z), Vector3(0.25, 3.2, 0.25), frame)
	# The roof clears the navigation agent and needs no walkable surface above it.
	section("ShelterRoof", scene)
	box(center + Vector3(0, 3.35, 0), Vector3(6, 0.3, 6), frame)
	shelter("DryZone", center + Vector3(0, 1.6, 0), Vector3(6, 3.2, 6))
	label("SHELTER", center + Vector3(0, 3.35, 3.01), 0.23, "#f8e6b8")
	var puddle_sign := section("PuddleSign", scene)
	puddle_sign.position = Vector3(-6, 0.02, -11.5)
	puddle_sign.rotation_degrees.x = -90
	label("PUDDLE", Vector3.ZERO, 0.32, "#f8e6b8")


func build_range() -> void:
	section("Range")
	var cover := paint("#59636c")
	var line := paint("#c9a66b")
	var depth := 0.8
	for lane in 3:
		var distance := 10 * (lane + 1)
		var x := 20.0 + 4.0 * lane
		# Distances run from the firing stripe to the block's front face.
		box(Vector3(x, 0.003, 0), Vector3(2.4, 0.006, 0.05), line, false)
		box(Vector3(x, 1.1, -distance - depth * 0.5), Vector3(2.4, 2.2, depth), cover)
		label("%dM" % distance, Vector3(x, 1.8, -distance + 0.01), 0.45, "#f8e6b8")


func markers() -> void:
	points("PlayerSpawns", "player_spawn", [Vector2.ZERO, Vector2(-2, 0),
		Vector2(0, 2), Vector2(-2, 2)])
	points("EnemySpawns", "enemy_spawn", [Vector2(-44, -44), Vector2(0, -44),
		Vector2(44, -44), Vector2(44, 0), Vector2(44, 44), Vector2(0, 44),
		Vector2(-44, 44), Vector2(-44, 0)])
	points("CrateSpawns", "crate_spawn", [Vector2(-28, -28), Vector2(10, -26),
		Vector2(32, 14), Vector2(12, 32), Vector2(-30, 24)])
	points("StreetSupplySpawns", "street_supply_spawn", [Vector2(-28, 8),
		Vector2(-8, 28), Vector2(22, 22), Vector2(12, -32)], 0.06)
	directories["CrateStations"] = add(scene, Node3D.new(), "CrateStations")
	marker("CrateStations", "crate_station", "RangeVending", Vector3(8, 0, -8)).rotation_degrees.y = 135
	shower("RangeDecon", Vector3(-12, 0, -4))
	puddles([Vector3(-6, 2.2, -14)])
	drain(Vector3(-6, 0.02, -17))
	marker("", "boss_anchor", "BossAnchor", Vector3(0, 16, -32))
