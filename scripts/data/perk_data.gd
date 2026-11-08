class_name PerkData
extends Resource
## A sidegrade ability. Every perk has an upside and a downside so progression widens
## choice instead of raw power.

@export var id: StringName
@export var name_key: String = ""
@export var description_key: String = ""
@export var unlock_level: int = 1
@export var icon_glyph: String = "+"
## stat name (matches PlayerStatsData property) -> multiplier
@export var stat_multipliers: Dictionary = {}


func apply_to(stats: PlayerStatsData) -> void:
	for key in stat_multipliers:
		var prop := String(key)
		if prop in stats:
			stats.set(prop, float(stats.get(prop)) * float(stat_multipliers[key]))
