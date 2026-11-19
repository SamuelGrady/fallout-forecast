class_name EnemyData
extends Resource
## Tuning numbers for one enemy type (EnemyData.tres in the design doc).

@export var display_name := "Enemy"
@export var max_health := 60.0
@export var move_speed := 2.5
@export var damage := 10.0
@export var attack_range := 1.6
@export var attack_cooldown := 1.2
## How often the enemy picks a new target, in seconds.
@export var retarget_interval := 0.5
