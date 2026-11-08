class_name EventData
extends Resource
## Configuration for a mission event. `event_script` must extend MissionEvent.

@export var id: StringName
@export var name_key: String = ""
@export var banner_key: String = ""
@export var event_script: Script
@export var weight: float = 1.0
## Minimum escalation threat (0..1) before the director may pick this randomly.
@export_range(0.0, 1.0) var min_threat: float = 0.0
@export var cooldown: float = 120.0
@export var duration: float = 30.0
## When false the event is only triggered by objectives / scripts, never randomly.
@export var random: bool = true
@export var max_occurrences: int = 3
@export var params: Dictionary = {}
