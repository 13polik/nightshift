class_name EnemyData
extends Resource
## Tuning + behaviour configuration for an enemy archetype.

@export var id: StringName
@export var name_key: String = ""
@export var scene: PackedScene
## Script implementing the AI state set (must extend EnemyBrain). Allows new enemy types
## to reuse or replace states without touching EnemyBase.
@export var brain_script: Script

@export_group("Movement")
@export var patrol_speed: float = 1.6
@export var investigate_speed: float = 2.6
@export var search_speed: float = 2.0
@export var chase_speed: float = 4.9
@export var turn_speed: float = 6.0

@export_group("Perception")
@export var sight_range: float = 18.0
@export_range(10.0, 360.0) var fov_degrees: float = 110.0
@export var close_detect_radius: float = 2.5
## Awareness gained per second when a target is fully visible at point-blank range.
@export var awareness_gain: float = 1.6
@export var awareness_decay: float = 0.35
@export var hearing_multiplier: float = 1.0
## Multiplier on sight range for targets using a flashlight.
@export var flashlight_sight_multiplier: float = 1.6
## Multiplier on sight range when the target is in an unpowered (dark) area without light.
@export var darkness_sight_multiplier: float = 0.55
@export var crouch_sight_multiplier: float = 0.7

@export_group("Combat")
@export var attack_damage: float = 34.0
@export var attack_range: float = 1.9
@export var attack_windup: float = 0.55
@export var attack_cooldown: float = 1.4
@export var stun_resistance: float = 0.0

@export_group("Behaviour")
@export var alert_duration: float = 0.9
@export var lose_target_time: float = 3.5
@export var search_duration: float = 18.0
@export var search_radius: float = 9.0
@export var idle_time_min: float = 2.0
@export var idle_time_max: float = 5.0
@export var door_bash_time: float = 2.2
@export var linger_after_down: float = 10.0
