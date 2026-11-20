class_name WeaponData
extends Resource
## Tuning for one weapon (WeaponData.tres in the design doc).

enum Kind { HITSCAN, FLARE, GRENADE, ROCKET, PLACE, USE }

@export var mechanic := ""
@export var charge_time := 0.0
@export var critical_bonus := 1.0

@export var shot_sound := ""
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
@export var shell_reload := false
@export var recoil_degrees := 0.6
## Extra spread after a sustained automatic burst.
@export var burst_spread := 0.0

@export_group("Projectile")
@export var fuse := 0.0
@export var projectile_speed := 30.0
@export var projectile_gravity := 1.0
## Grenade blast radius, or the flare's reveal radius.
@export var effect_radius := 5.0
## Grenade fuse, or how long a flare burns.
@export var effect_time := 1.6

@export_group("Cursed")
## Drains the holder's suit even in shelter (Leaky Nailgun).
@export var held_suit_drain := 0.0
## Bullets go through this many enemies (Leaky Nailgun).
@export var pierce := 0
## Each shot drags enemies within this radius toward the shooter (Boombox).
@export var pull_radius := 0.0
## Lucky Penny: chance a shot one-hit kills, chance it jams for jam_time.
@export var lucky_kill_chance := 0.0
@export var jam_chance := 0.0
@export var jam_time := 2.0
@export var cursed := false

@export_group("Viewmodel")
@export var view_position := Vector3(0.28, -0.26, -0.5)
@export var view_rotation_degrees := Vector3.ZERO
@export var view_scale := 1.0
## Muzzle position in the model's own space, for tracers and flashes.
@export var muzzle := Vector3(0, 0.06, -0.45)
@export var tracer_color := Color(1.0, 0.85, 0.4)

## Custom model id from GunModels (rifle, shotgun, flare, bug_bomb,
## revolver, nailgun, boombox). Overrides `model` when set.
@export var gun_model := ""


## The viewmodel / display model for this weapon.
func make_model() -> Node3D:
	if gun_model != "":
		return GunModels.build(gun_model)
	if model:
		return model.instantiate() as Node3D
	return null


@export_group("Sights")
## "red_dot": reflex sight on top. "bead": shotgun rib + front bead.
## "": no sight, plain centered ADS.
@export var sight := ""
## Field of view while aiming down sights.
@export var ads_fov := 52.0
## Distance from the eye to the sight while aiming, in meters.
@export var ads_eye_relief := 0.32


