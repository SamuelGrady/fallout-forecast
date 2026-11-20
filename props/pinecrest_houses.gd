class_name PinecrestHouses
extends BuildingKit
## Each house is laid out explicitly. The level's existing pumpkin pairs,
## garage openings and porch slabs mark the +Z side of each rotated lot.

const SLATE := "9fa1b5/shingles_teal"
const COPPER := "cfa98c/brick"
const CEDAR := "eed1ad/wood"
const CLARET := "884755"
const AMBER := "eabd83/lit"
const NAVY := "354a64"
const MOSS := "557667"
const PLASTER := "f2dbba/stucco"
const CLAY_BRICK := "bc7d68/brick"


func base(paint: String, trim: String, floors := 2) -> void:
	shell(paint)
	box("91877e/brick", 0, 0.25, 0, size.x + 0.035, 0.5, size.z + 0.035)
	box(trim, 0, size.y - 0.14, 0, size.x + 0.19, 0.21, size.z + 0.19)
	for yaw in [PI / 2, PI, -PI / 2]:
		wall(yaw)
		var width := size.x if yaw == PI else size.z
		for j in floors:
			for side in [-1, 1]:
				var pane := AMBER if side > 0 and j == 0 else NIGHT
				window(side * width * 0.26, 1.64 + j * (size.y / floors), 1.48, 1.34, 2, trim, pane, true)
		box(trim, -width / 2 + 0.13, size.y / 2, 0.06, 0.11, size.y - 0.3, 0.13)
	wall(0)


func shutter_window(
	x: float, y: float, w: float, h: float, trim: String, shutter: String, glass: String
) -> void:
	window(x, y, w, h, 2, trim, glass, true)
	for side in [-1, 1]:
		var sx: float = x + side * (w * 0.5 + 0.2)
		box(shutter, sx, y, 0.075, 0.32, h, 0.12)
		for j in 3:
			box(shutter, sx, y + (j - 1) * h * 0.28, 0.15, 0.34, 0.08, 0.08)


func stoop(x: float, w: float, depth: float, trim: String, own_roof := true) -> void:
	box("a99f91", x, 0.12, depth * 0.5, w, 0.24, depth)
	box("ada297", x, 0.065, depth + 0.15, w - 0.24, 0.13, 0.34)
	if own_roof:
		for side in [-1, 1]:
			box(trim, x + side * (w / 2 - 0.18), 1.4, depth - 0.15, 0.16, 2.45, 0.16)
		box(trim, x, 2.69, depth / 2 - 0.02, w + 0.18, 0.19, depth + 0.24)


func rail(x: float, width: float, depth: float, trim: String) -> void:
	box(trim, x, 1.03, depth, width, 0.11, 0.13)
	for i in 6:
		box(trim, x - width / 2 + width * i / 5, 0.64, depth, 0.075, 0.78, 0.075)


func mailbox(x: float, paint: String) -> void:
	box(paint, x, 1.27, 0.12, 0.46, 0.4, 0.24)
	box(INK, x, 1.38, 0.253, 0.33, 0.05, 0.035)
	box(paint, x, 1.5, 0.14, 0.53, 0.09, 0.32)
	box(CREAM, x, 1.24, 0.25, 0.17, 0.07, 0.03)


func attic_vent(x: float, y: float, z: float, w: float) -> void:
	frame = Transform3D.IDENTITY
	box(CREAM, x, y, z, w, 0.54, 0.12)
	box(NIGHT, x, y, z + 0.07, w - 0.14, 0.42, 0.06)
	for i in 3:
		box(CREAM, x, y + (i - 1) * 0.12, z + 0.12, w - 0.14, 0.055, 0.07)


func gutter(paint: String, right: bool) -> void:
	var x := size.x * 0.5 - 0.19
	if not right:
		x = -x
	box(paint, 0, size.y, 0.18, size.x + 0.22, 0.15, 0.22)
	box(paint, x, size.y * 0.5, 0.15, 0.11, size.y, 0.13)
	box(paint, x, 0.18, 0.25, 0.13, 0.14, 0.31)


func bay(x: float, y: float, w: float, h: float, trim: String, glass: String) -> void:
	box(trim, x, y, 0.24, w, h, 0.53)
	var previous := frame
	frame.origin += frame.basis.z * 0.49
	window(x, y + 0.08, w - 0.15, h - 0.4, 3, trim, glass)
	frame = previous
	box(trim, x, y + h / 2, 0.29, w + 0.22, 0.16, 0.7)


func side_gable(rise: float, roof: String, end: String, inset := 0.0, offset := 0.0) -> void:
	frame = Transform3D.IDENTITY
	ridge_roof(0, size.y + 0.06, 0, size.x + 0.38, size.z + 0.4, rise, inset, offset, roof, end)


func front_gable(
	x: float, y: float, z: float, w: float, d: float, rise: float, roof: String, end: String
) -> void:
	frame = Transform3D(Basis(Vector3.UP, PI / 2), Vector3(x, y, z))
	ridge_roof(0, 0, 0, d, w, rise, 0, 0, roof, end)
	frame = Transform3D.IDENTITY


func dormer(x: float, w: float, roof: String, trim: String) -> void:
	var z := front * 0.56
	box(trim, x, size.y + 0.69, z - 0.32, w, 1.42, 1.48)
	front_gable(x, size.y + 1.45, z - 0.32, w + 0.21, 1.7, 0.63, roof, trim)
	frame.origin = Vector3(0, 0, z + 0.42)
	window(x, size.y + 1.0, w - 0.28, 0.69, 2, trim, NIGHT)
	frame = Transform3D.IDENTITY


func house_west() -> void:
	base("d6cb8f/siding", CREAM)
	stoop(-2.35, 2.55, 1.05, CREAM)
	door(-2.35, MOSS, CREAM, true, 0.24)
	mailbox(-3.32, MOSS)
	bay(1.65, 1.67, 3.46, 1.86, CREAM, AMBER)
	for x in [-2.6, 1.7]:
		shutter_window(x, 4.47, 1.48, 1.38, CREAM, MOSS, NIGHT)
	side_gable(1.65, SLATE, CREAM, 1.9)
	chimney(3.35, -0.8, size.y + 1.94, 0.81, CLAY_BRICK)


func house_north_west() -> void:
	base("e9b699/siding", CREAM)
	stoop(2.1, 3.48, 1.25, CREAM)
	rail(1.0, 0.91, 1.07, CREAM)
	door(2.18, CLARET, CREAM, true, 0.24)
	gutter(CREAM, false)
	window(-1.78, 1.74, 3.45, 1.67, 3, CREAM, AMBER)
	for x in [-2.9, 0.0, 2.9]:
		window(x, 4.27, 1.32, 1.43, 1, CREAM, NIGHT, true)
	side_gable(1.82, "897d81/stucco", CREAM, 0, 1.09)
	dormer(-1.6, 1.82, "897d81/stucco", CREAM)
	chimney(3.55, 0.64, size.y + 2.3, 0.67, CLAY_BRICK)


func house_north() -> void:
	base("98c3c5/siding", CREAM)
	stoop(0, 4.76, 2.38, CREAM, false)
	door(0, NAVY, CREAM, true, 0.24)
	for x in [-3.22, 3.22]:
		shutter_window(x, 1.68, 1.46, 1.55, CREAM, NAVY, AMBER)
		shutter_window(x, 4.78, 1.46, 1.65, CREAM, NAVY, NIGHT)
	window(0, 4.78, 1.18, 1.65, 1, CREAM, NIGHT, true)
	mailbox(1.14, NAVY)
	side_gable(1.72, SLATE, CREAM)
	dormer(-2, 1.42, SLATE, CREAM)
	dormer(2, 1.42, SLATE, CREAM)
	chimney(-3.8, -0.54, size.y + 2.05, 0.75, COPPER)


func house_north_east() -> void:
	base("dcaab5/siding", "f5d6bc")
	stoop(0, 4.7, 2.4, CREAM, false)
	rail(1.58, 1.26, 2.31, CREAM)
	door(-0.82, CLARET, CREAM, true, 0.24)
	bay(2.68, 1.8, 2.64, 2.0, CREAM, NIGHT)
	window(-3.19, 1.75, 1.52, 1.55, 2, CREAM, AMBER)
	for x in [-2.85, 0, 2.85]:
		window(x, 5.44, 1.53, 2.02, 2, CREAM, NIGHT, true)
	side_gable(1.84, "77718a/stucco", CREAM)
	front_gable(2.3, size.y + 0.11, front * 0.43, 4.86, size.z * 0.72, 2.25, "77718a/stucco", CREAM)
	attic_vent(2.3, size.y + 0.82, front * 0.43 + size.z * 0.36, 1.08)
	chimney(-2.55, -1.6, size.y + 2.3, 0.85, CLAY_BRICK)


func house_east() -> void:
	base("bb775b/brick", CREAM)
	stoop(1.74, 2.63, 1.24, NAVY)
	door(1.74, NAVY, CREAM, false, 0.24)
	window(-1.95, 1.78, 3.78, 1.5, 4, CREAM, AMBER)
	box(CREAM, 0, 3.38, 0.07, size.x, 0.23, 0.17)
	window(0, 5.47, 7.25, 1.43, 6, NAVY, BLUE_GLASS)
	gutter(NAVY, true)
	side_gable(1.05, "8f8e83/stucco", CREAM, 2.35)
	chimney(-3.65, 1.0, size.y + 1.87, 1.29, CLAY_BRICK)


func lane_west() -> void:
	base("9dbba4/siding", CREAM)
	stoop(0, 4.8, 2.4, CREAM, false)
	door(0.62, MOSS, CREAM, true, 0.24)
	for x in [-3.1, 3.1]:
		shutter_window(x, 1.8, 1.48, 1.61, CREAM, MOSS, NIGHT)
	window(-2.27, 5.32, 2.41, 1.72, 2, CREAM, AMBER, true)
	window(2.27, 5.32, 2.41, 1.72, 2, CREAM, NIGHT, true)
	# Dutch gambrel: steep lower pitch and a shallow ridge, facing the lane.
	frame = Transform3D(Basis(Vector3.UP, PI / 2), Vector3.ZERO)
	slope_course(
		0, size.y, 0, size.z + 0.38, size.x + 0.44, size.z + 0.32, size.x - 2.25, 1.62, "857483/stucco"
	)
	ridge_roof(0, size.y + 1.63, 0, size.z + 0.34, size.x - 2.24, 0.92, 0, 0, "857483/stucco", CREAM)
	frame = Transform3D.IDENTITY
	chimney(2.8, -1.77, size.y + 2.65, 0.69, COPPER)


func lane_east() -> void:
	base("dfc39d/stucco", "664f48")
	stoop(-1.3, 3.25, 1.07, "664f48")
	door(-1.3, "80584b", CREAM, true, 0.24)
	window(2.12, 1.68, 2.55, 1.56, 3, "664f48", AMBER)
	window(-3.42, 1.68, 1.08, 1.56, 1, "664f48", NIGHT)
	for x in [-3.9, -1.3, 1.3, 3.9]:
		box("664f48", x, 5.53, 0.08, 0.18, 4.12, 0.18)
	for x in [-2.55, 0, 2.55]:
		window(x, 5.32, 1.54, 1.79, 2, "664f48", NIGHT, true)
	box("664f48", 0, 3.54, 0.085, size.x, 0.26, 0.19)
	front_gable(0, size.y, 0, size.x + 0.48, size.z + 0.43, 2.68, "736873/stucco", PLASTER)
	wall(0)
	box("664f48", 0, size.y + 1.18, 0.24, 0.2, 2.34, 0.13)
	for side in [-1, 1]:
		face(
			"664f48",
			[
				Vector3(side * 0.1, size.y + 0.2, 0.25),
				Vector3(side * 0.1, size.y + 0.43, 0.25),
				Vector3(side * 2.05, size.y + 1.28, 0.25),
				Vector3(side * 2.05, size.y + 1.06, 0.25)
			],
			Vector3.BACK
		)
	frame = Transform3D.IDENTITY
	chimney(-2.6, 1.2, size.y + 2.43, 0.96, CLAY_BRICK)


func main_north_east_one() -> void:
	base("b2c9d8/siding", CREAM)
	stoop(-1.15, 6.18, 1.46, NAVY)
	rail(-3, 1.88, 1.3, CREAM)
	rail(0.88, 1.25, 1.3, CREAM)
	door(-0.7, "af6659", CREAM, true, 0.24)
	window(-3.18, 1.83, 1.59, 1.83, 2, CREAM, NIGHT, true)
	bay(2.85, 2, 2.57, 2.22, CREAM, AMBER)
	for x in [-2.86, 0, 2.86]:
		shutter_window(x, 5.97, 1.37, 2.04, CREAM, NAVY, NIGHT)
	side_gable(1.46, SLATE, CREAM, 2.02)
	front_gable(-2.41, size.y + 0.06, front * 0.4, 4.76, size.z * 0.74, 2.19, SLATE, CREAM)
	attic_vent(-2.41, size.y + 0.8, front * 0.4 + size.z * 0.37, 0.92)
	chimney(3.08, -1.77, size.y + 1.98, 0.75, COPPER)


func main_north_east_two() -> void:
	base("d3a383/brick", CREAM, 3)
	stoop(0, 4.8, 2.4, CREAM, false)
	door(0.1, CLARET, CREAM, true, 0.24)
	mailbox(1.16, CLARET)
	for x in [-2.65, 2.65]:
		window(x, 1.84, 1.68, 1.96, 2, CREAM, AMBER, true)
		bay(x, 5.25, 2.35, 2.06, CREAM, NIGHT)
	for x in [-2.66, 0, 2.66]:
		window(x, 8.77, 1.41, 1.65, 1, CREAM, NIGHT, true)
	frame = Transform3D.IDENTITY
	slope_course(
		0, size.y, 0, size.x + 0.42, size.z + 0.42, size.x - 2.66, size.z - 2.76, 1.66, "706f87/stucco"
	)
	box(CREAM, 0, size.y + 1.69, 0, size.x - 2.59, 0.11, size.z - 2.69)
	chimney(-2.75, -2.49, size.y + 2.24, 0.77, CLAY_BRICK)


func back_north_east() -> void:
	base("b68f71/siding", CREAM, 3)
	stoop(0, 4.8, 2.4, CREAM, false)
	door(-0.86, "925f42", CREAM, false, 0.24)
	window(2.07, 1.73, 2.49, 1.62, 3, CREAM, AMBER)
	window(-3.34, 1.73, 1.28, 1.62, 1, CREAM, NIGHT)
	for y in [5.22, 8.74]:
		window(-2.55, y, 2.34, 1.62, 2, CREAM, NIGHT, true)
		window(1.55, y, 3.62, 1.62, 3, CREAM, BLUE_GLASS, true)
	# Two unequal shed roofs meet at a vertical clerestory.
	frame = Transform3D.IDENTITY
	var eave := size.y
	var w := size.x + 0.46
	var d := size.z + 0.46
	for side in [-1, 1]:
		var high := eave + (1.85 if side < 0 else 0.86)
		var x: float = side * w / 2
		var a := Vector3(x, eave, d / 2)
		var b := Vector3(0, high, d / 2)
		var c := Vector3(0, high, -d / 2)
		var e := Vector3(x, eave, -d / 2)
		face(SLATE, [a, b, c, e], Vector3.UP)
		face(CEDAR, [a, b, Vector3(0, eave, d / 2)], Vector3.BACK)
		face(CEDAR, [e, c, Vector3(0, eave, -d / 2)], Vector3.FORWARD)
	box(BLUE_GLASS, 0, eave + 1.33, 0, 0.1, 1.04, d - 0.05)
	chimney(3.28, -2.55, eave + 1.47, 1.04, COPPER)
