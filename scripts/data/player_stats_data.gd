class_name PlayerStatsData
extends Resource
## Base player tuning. Perks apply small sidegrade modifiers on top of these values.

@export_group("Movement")
@export var walk_speed: float = 3.0
@export var sprint_speed: float = 5.4
@export var crouch_speed: float = 1.5
@export var downed_speed: float = 0.6
@export var acceleration: float = 14.0
@export var air_control: float = 0.3
@export var gravity: float = 18.0

@export_group("Stamina")
@export var stamina_max: float = 100.0
@export var stamina_drain: float = 22.0
@export var stamina_regen: float = 16.0
@export var stamina_regen_delay: float = 1.0
@export var stamina_min_to_sprint: float = 15.0

@export_group("Health")
@export var max_health: float = 100.0
@export var bleed_out_time: float = 45.0
@export var revive_time: float = 4.5
@export var revive_health: float = 35.0
@export var invulnerable_after_revive: float = 2.0

@export_group("Equipment")
@export var inventory_slots: int = 4
@export var flashlight_battery_seconds: float = 180.0
@export var interact_range: float = 2.4

@export_group("Noise")
## Radius (m) of the noise produced by movement in each state.
@export var noise_walk: float = 6.0
@export var noise_sprint: float = 14.0
@export var noise_crouch: float = 1.5
@export var noise_land: float = 8.0
