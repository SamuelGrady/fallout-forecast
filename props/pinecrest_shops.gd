class_name PinecrestShops
extends BuildingKit
## Parts in wall space project towards the sidewalk. The existing block awnings
## run across the row at 3.3 m. Keep the shop displays below that datum.

const PLUM := "835887/stucco"
const TEAL := "347d80/brick"
const TILE := "ecddbb/tile"
const STEEL := "b9ccd0"
const GREEN := "51876d/brick"
const CLAY := "b46a55/brick"
const ROSE := "ed7894"
const GOLD := "f6ac58"
var sign_mount: Vector3


func shop_base(material: String, trim: String) -> void:
	shell(material)
	box(INK, 0, size.y - 0.035, 0, size.x - 0.04, 0.09, size.z - 0.04)
	wall(PI)
	door(-2.6, INK, trim, false)
	window(1.6, 2.2, 2.45, 1.15, 3, trim, NIGHT)
	for i in 7:
		box(CHROME, -0.6, 0.5 + i * 0.78, 0.22, 0.53, 0.055, 0.06)
	for x in [-0.88, -0.32]:
		box(CHROME, x, size.y / 2, 0.19, 0.07, size.y, 0.09)
	wall(0)


## A deep false front stands on the exterior wall and has a solid return on
## both ends. Its painted face is the actual mounting plane for the sign.
func band(x: float, y: float, w: float, h: float, material: String, coping: String) -> void:
	box(material, x, y, -0.14, w, h, 0.56)
	box(coping, x, y + h / 2, -0.12, w, 0.16, 0.66)
	sign_mount = Vector3(x, y, front + 0.14)


func walk(x: float, width: float) -> void:
	# Bridge the 2 m planting strip between the threshold and the shared walk.
	box("dfd3bf/sidewalk", x, 0.026, 1.02, width, 0.054, 2.05)


func video_vault() -> void:
	shop_base(PLUM, CREAM)
	band(0, 5.4, 9.85, 2.15, "50405c", ROSE)
	for y in [4.52, 6.25]:
		box("b77568", 0, y, 0.22, 9.7, 0.17, 0.22)
		for i in 22:
			disc(LAMP + "/lit", -4.57 + 0.435 * i, y, 0.345, 0.075, 8)
	for x in [-4.54, 4.54]:
		box(ROSE, x, 2.17, 0.08, 0.28, 4.3, 0.2)
	door(0, "543652", GOLD)
	walk(0, 1.65)
	for x in [-2.55, 2.55]:
		box(GOLD, x, 1.63, 0.1, 2.03, 2.44, 0.2)
		box(INK, x, 1.63, 0.22, 1.85, 2.26, 0.055)
		if x < 0:
			# Sunset over a two-tone mountain on the first one-sheet.
			disc(GOLD, x + 0.22, 1.95, 0.26, 0.44)
			face(
				"997699",
				[Vector3(x - 0.83, 1.13, 0.27), Vector3(x - 0.13, 2.08, 0.27), Vector3(x + 0.8, 1.13, 0.27)],
				Vector3.BACK
			)
		else:
			# Oversize VHS cassette with paired spools on the second one.
			box(ROSE, x, 1.8, 0.27, 1.54, 0.86, 0.045)
			for dx in [-0.39, 0.39]:
				disc(CREAM, x + dx, 1.82, 0.302, 0.21, 10)
				disc(INK, x + dx, 1.82, 0.315, 0.085, 8)
		for i in 2:
			box(CREAM, x, 0.87 + 0.15 * i, 0.28, 0.85 + i * 0.43, 0.055, 0.035)
	wall(PI / 2)
	# The exposed end wall advertises the shop to traffic entering town.
	disc("523f5e/stucco", 0, 3.1, 0.015, 1.34, 16)
	disc("c18c9f/stucco", 0, 3.1, 0.023, 1.16, 16)
	for i in 5:
		var angle := TAU * i / 5
		disc("523f5e/stucco", sin(angle) * 0.66, 3.1 + cos(angle) * 0.66, 0.032, 0.27)
	disc("523f5e/stucco", 0, 3.1, 0.033, 0.12)
	rooftop_unit(-2.6, -1.3)


func arcade() -> void:
	shop_base(TEAL, MINT)
	band(0, 5.48, 7.85, 1.85, "15595d", MINT)
	for x in [-4.38, 4.38]:
		box("245355", x, 4.77, -0.12, 0.81, 2.35, 0.58)
		for j in 3:
			box("71f1ce/lit", x, 5.03 + j * 0.24, 0.19, 0.58, 0.085, 0.07)
	for j in 2:
		for i in 25:
			var key := CREAM if (i + j) % 2 == 0 else INK
			box(key, -4.8 + 0.4 * i, 2.83 + j * 0.21, 0.07, 0.4, 0.21, 0.12)
	door(-0.61, INK, MINT)
	door(0.64, INK, MINT)
	walk(0, 2.85)
	for x in [-2.95, 2.95]:
		box(INK, x, 1.69, 0.07, 2.77, 2.02, 0.15)
		for i in 5:
			for j in 4:
				var tile := "8fbac1" if (i + 2 * j) % 4 == 0 else "5c999d"
				box(tile, x + (i - 2) * 0.52, 0.99 + j * 0.47, 0.15, 0.47, 0.42, 0.09)
	rooftop_unit(2.7, -0.7, 1.8)


func laundromat() -> void:
	shop_base(TILE, BLUE_GLASS)
	band(0, 5.04, 9.94, 1.55, "505575/tile", "77b7bb")
	box("65b8bd", 0, 0.38, 0.04, 9.97, 0.72, 0.09)
	door(3.74, "56888c", CREAM)
	walk(3.74, 1.63)
	window(-0.96, 1.65, 6.68, 2.21, 1, CHROME, BLUE_GLASS)
	for i in 5:
		var x := -3.6 + i * 1.32
		box("c5d0bf", x, 1.23, 0.165, 1.1, 1.12, 0.052)
		disc(INK, x, 1.23, 0.20, 0.425)
		disc("81aab0", x, 1.23, 0.213, 0.31)
		disc("bed9c9", x - 0.09, 1.33, 0.22, 0.09, 8)
		box("efcc78", x + 0.27, 1.66, 0.2, 0.17, 0.07, 0.04)
		if i < 4:
			box(CHROME, x + 0.66, 1.65, 0.235, 0.09, 2.15, 0.07)
	wall(-PI / 2)
	for x in [-1.62, 0.0, 1.62]:
		box(CHROME, x, 2.1, 0.09, 1.06, 0.89, 0.2)
		for i in 4:
			box(INK, x, 1.84 + i * 0.16, 0.2, 0.85, 0.075, 0.06)
	for i in 3:
		rooftop_unit(-2.55 + i * 2.45, -1, 1.05)


func diner() -> void:
	shop_base(STEEL, RED)
	band(0, 5.07, 9.88, 1.45, STEEL, RED)
	# Bullnose caps on the long speed lines and a stepped Deco crown.
	for y in [0.34, 0.58, 3.74, 4.0]:
		box(RED, 0, y, 0.16, 9.17, 0.13, 0.34)
		for x in [-4.58, 4.58]:
			disc(RED, x, y, 0.331, 0.066)
	for i in 3:
		box("e4d8b3", (i - 1) * 0.35, 5.77, -0.14, 0.21, 1.03 - abs(i - 1) * 0.38, 0.52)
	door(-3.62, RED, CHROME)
	walk(-3.62, 1.65)
	window(0.75, 1.79, 6.32, 1.93, 4, CHROME, "c39e87/lit")
	for i in 4:
		var x := -1.62 + i * 1.58
		# Pendant shades and booth backs silhouette against the lit panes.
		box(INK, x, 2.54, 0.16, 0.045, 0.24, 0.04)
		face(
			"a65a46",
			[
				Vector3(x - 0.29, 2.28, 0.19),
				Vector3(x - 0.08, 2.47, 0.19),
				Vector3(x + 0.08, 2.47, 0.19),
				Vector3(x + 0.29, 2.28, 0.19)
			],
			Vector3.BACK
		)
		box("985758", x, 1.07, 0.16, 1.28, 0.36, 0.05)
		box("d19579", x, 1.25, 0.19, 1.18, 0.07, 0.05)
	# Rolled sheet metal wraps the alley end of the counter in a quarter circle.
	frame = Transform3D.IDENTITY
	var start := Vector3(3.93, 0, front - 0.87)
	var previous := start + Vector3.BACK * 1.51
	for i in range(1, 7):
		var a := PI * 0.5 * i / 6
		var outward := Vector3(sin(a), 0, cos(a))
		var p := start + 1.51 * outward
		var bottom := 0.0
		for strip in [
			[0.28, STEEL],
			[0.41, RED],
			[0.61, STEEL],
			[0.73, RED],
			[0.95, STEEL],
			[2.65, BLUE_GLASS],
			[2.84, STEEL],
			[2.97, RED],
			[3.12, STEEL]
		]:
			var top: float = strip[0]
			face(
				strip[1],
				[
					previous + Vector3.UP * bottom,
					previous + Vector3.UP * top,
					p + Vector3.UP * top,
					p + Vector3.UP * bottom
				],
				outward
			)
			bottom = top
		face(
			STEEL,
			[start + Vector3.UP * 3.12, previous + Vector3.UP * 3.12, p + Vector3.UP * 3.12],
			Vector3.UP
		)
		box(CHROME, p.x, 1.8, p.z, 0.055, 1.7, 0.055)
		previous = p
	box(STEEL, start.x, 1.55, front + 0.28, 0.075, 3.1, 0.72)
	box(STEEL, 5.2, 1.55, start.z, 0.49, 3.1, 0.075)
	wall(PI / 2)
	window(-0.15, 1.79, 4.5, 1.93, 4, CREAM, "ca9b76/lit")
	rooftop_unit(1.8, -1.2)


func pharmacy() -> void:
	shop_base(GREEN, CREAM)
	band(-0.69, 5.22, 8.46, 1.84, GREEN, CREAM)
	box("376857", 3.88, 4.91, -0.15, 1.78, 2.19, 0.61)
	box(CREAM, 3.88, 5.08, 0.19, 1.47, 1.47, 0.15)
	box("67e89a/lit", 3.88, 5.08, 0.29, 1.12, 0.39, 0.1)
	box("67e89a/lit", 3.88, 5.08, 0.30, 0.4, 1.11, 0.1)
	door(2.16, "365d49", CREAM)
	walk(2.16, 1.62)
	window(-1.54, 1.67, 5.1, 1.93, 3, CREAM, NIGHT, true)
	# Apothecary jars on the lower display shelf.
	for i in 8:
		var x := -3.68 + i * 0.59
		var h := 0.26 + 0.11 * (i % 3)
		var glaze := "a9c5aa" if i % 3 == 0 else "ab8662"
		box(glaze, x, 0.95 + h / 2, 0.19, 0.20, h, 0.075)
		box(CREAM, x, 0.98 + h, 0.19, 0.13, 0.07, 0.08)
		box("e6d5b7", x, 1.0 + h / 3, 0.235, 0.18, 0.1, 0.025)
	box("a77357", -1.56, 0.92, 0.17, 4.87, 0.09, 0.23)
	window(3.85, 1.67, 1.32, 1.93, 1, CREAM, BLUE_GLASS, true)
	for x in [-4.65, 1.16, 4.68]:
		box(CREAM, x, 1.6, 0.10, 0.26, 3.18, 0.25)
		box("c1b79c", x, 0.37, 0.15, 0.38, 0.66, 0.32)
	rooftop_unit(-1.85, -0.4)


func hardware() -> void:
	shop_base(CLAY, INK)
	band(-0.2, 5.12, 9.58, 1.49, "644e46", GOLD)
	for i in 13:
		box(BRICK, -4.44 + i * 0.74, 5.99, -0.08, 0.38, 0.21, 0.45)
	box(INK, 2.77, 1.47, 0.07, 3.45, 2.95, 0.16)
	box("78858c", 2.77, 1.43, 0.17, 3.18, 2.78, 0.09)
	for i in 12:
		box("526774", 2.77, 0.22 + i * 0.22, 0.23, 3.1, 0.045, 0.04)
	box(INK, 2.77, 0.65, 0.25, 0.52, 0.08, 0.08)
	door(0.12, "ad623d", GOLD)
	walk(0.12, 1.52)
	walk(2.77, 3.29)
	window(-2.74, 1.58, 3.36, 1.98, 1, CREAM, NIGHT)
	# Three long-handled tools on the display rack.
	for i in 3:
		var x := -3.55 + i * 0.77
		box("d8ac77", x, 1.52, 0.168, 0.08, 1.23, 0.06)
		box(CHROME, x, 2.11, 0.20, 0.42, 0.13 + i * 0.05, 0.065)
	wall(-PI / 2)
	window(0, 3.92, 4.55, 0.99, 6, INK, BLUE_GLASS)
	box(INK, -2.78, size.y / 2, 0.12, 0.16, size.y - 0.06, 0.18)
	rooftop_unit(2.44, -1.3, 1.85)


func kiosk() -> void:
	shell("d4ccac/tile")
	wall(0)
	door(-2.18, RED, CHROME)
	window(0.92, 1.72, 4.24, 2.04, 3, INK, "b7bc94/lit")
	box(CHROME, 0.92, 0.76, 0.22, 4.37, 0.12, 0.44)
	for turn in [0.0, PI / 2, PI, -PI / 2]:
		wall(turn)
		var w := size.x if absf(sin(turn)) < 0.5 else size.z
		box(RED, 0, 3.16, 0.09, w, 0.33, 0.21)
		box(RED, 0, size.y - 0.41, 0.12, w, 0.59, 0.28)
		box(GOLD, 0, size.y - 0.68, 0.18, w, 0.13, 0.21)
		window(0, 5.38, w - 0.83, 0.99, 5, CHROME, NIGHT)
		if absf(sin(turn)) > 0.5:
			window(0, 1.74, w - 1.2, 1.78, 5, INK, BLUE_GLASS)
	wall(PI)
	door(-2.4, INK, CHROME, false)
	rooftop_unit(1.8, -1.9)
