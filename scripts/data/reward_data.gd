class_name RewardData
extends Resource
## Reward configuration for a mission. Rewards are computed by the host and sent to each
## player; nothing here can be bought with real money (no pay-to-win).

@export var base_xp: int = 100
@export var base_currency: int = 25
@export var extraction_xp: int = 250
@export var extraction_currency: int = 60
@export var survival_xp: int = 100
@export var revive_xp: int = 40
@export var optional_multiplier: float = 1.0
## Multiplier when the mission fails (players still earn progress for their effort).
@export var failure_multiplier: float = 0.35
@export var carried_objective_bonus_xp: int = 120
