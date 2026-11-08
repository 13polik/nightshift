class_name MissionData
extends Resource
## A complete mission definition: where it takes place, its objective chain, the
## event pool used by the escalation director, loot and rewards.

@export var id: StringName
@export var name_key: String = ""
@export var description_key: String = ""
@export var location_key: String = ""
## JSON facility layout (rooms, doors, features). See data/facilities/.
@export_file("*.json") var layout_path: String = ""
@export var objectives: Array[ObjectiveData] = []
## Pool of optional objectives. optional_count of them are chosen per run.
@export var optional_objectives: Array[ObjectiveData] = []
@export var optional_count: int = 1
@export var events: Array[EventData] = []
@export var loot_table: LootTable
@export var rewards: RewardData
@export var enemies: Array[EnemyData] = []
## Seconds (or objective index) after which the first enemy is released.
@export var enemy_release_time: float = 75.0
@export var enemy_release_objective: int = 2
@export_range(1, 4) var max_players: int = 4
@export var recommended_level: int = 1
@export var unlock_level: int = 1
## Threat gained per minute just from time passing.
@export var threat_per_minute: float = 0.04
@export var target_duration_minutes: float = 15.0
@export var start_powered: bool = false


func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if id == &"":
		errors.append("mission has empty id")
	if layout_path.is_empty() or not FileAccess.file_exists(layout_path):
		errors.append("mission %s layout missing: %s" % [id, layout_path])
	if objectives.is_empty():
		errors.append("mission %s has no objectives" % id)
	var has_extract := false
	for o in objectives:
		if o == null:
			errors.append("mission %s has null objective" % id)
			continue
		if o.type == ObjectiveData.Type.EXTRACT:
			has_extract = true
	if not has_extract:
		errors.append("mission %s has no EXTRACT objective" % id)
	return errors
