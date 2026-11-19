class_name WeaponData
extends Resource
## Tuning for one weapon (WeaponData.tres in the design doc).

enum Kind { HITSCAN, FLARE, GRENADE }

@export var display_name := "Weapon"
@export var kind: Kind = Kind.HITSCAN
@export var model: PackedScene

@export_group("Damage")
## Per pellet for hitscan, direct hit for a flare, at the center for a grenade.
@export var damage := 10.0
@export var pellets := 1
@export var spread_degrees := 1.0
## Hitscan: full damage up to half range, falling to 30% at full range.
@export var max_range := 50.0
@export var knockback := 0.0

@export_group("Handling")
@export var fire_interval := 0.2
@export var automatic := false
@export var mag_size := 6
@export var reserve_ammo := 30
@export var reload_time := 2.0

@export_group("Projectile")
@export var projectile_speed := 30.0
@export var projectile_gravity := 1.0
## Grenade blast radius, or the flare's reveal radius.
@export var effect_radius := 5.0
## Grenade fuse, or how long a flare burns.
@export var effect_time := 1.6

@export_group("Viewmodel")
@export var view_position := Vector3(0.28, -0.26, -0.5)
@export var view_rotation_degrees := Vector3.ZERO
@export var view_scale := 1.0
## Muzzle position in the model's own space, for tracers and flashes.
@export var muzzle := Vector3(0, 0.06, -0.45)
@export var tracer_color := Color(1.0, 0.85, 0.4)
