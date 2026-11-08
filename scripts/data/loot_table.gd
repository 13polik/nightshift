class_name LootTable
extends Resource
## Configurable resource spawning. Nothing about item placement is hard-coded: the
## facility layout exposes tagged spawn points and this table decides what goes there.

## item id (String) -> relative weight (float)
@export var weights: Dictionary = {}
## item id (String) -> guaranteed count per mission
@export var guaranteed: Dictionary = {}
## Fraction (0..1) of generic loot points that receive an item.
@export_range(0.0, 1.0) var fill_ratio: float = 0.55
## Fraction of searchable containers that hold something.
@export_range(0.0, 1.0) var container_fill_ratio: float = 0.6
## Per-player scaling: fill ratio multiplier added per extra player.
@export var per_player_bonus: float = 0.08


func roll(rng: RandomNumberGenerator) -> StringName:
	var total := 0.0
	for k in weights:
		total += float(weights[k])
	if total <= 0.0:
		return &""
	var r := rng.randf() * total
	for k in weights:
		r -= float(weights[k])
		if r <= 0.0:
			return StringName(k)
	return StringName(weights.keys().back())
