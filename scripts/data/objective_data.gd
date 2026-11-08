class_name ObjectiveData
extends Resource
## One step of a mission. The MissionDirector instantiates an ObjectiveHandler for the
## objective type, so new mechanics are added by writing a new handler, not by editing
## the director.

enum Type {
	REACH_ZONE,   ## any (or all) players enter a tagged zone
	INTERACT,     ## interact with one of the chosen tagged interactables
	COLLECT,      ## the team carries N items (ids from item_pool) in their inventories
	DELIVER,      ## interact with a tagged target while carrying required items (consumed)
	SURVIVE,      ## survive for duration seconds
	EXTRACT,      ## at least one player extracts
}

@export var id: StringName
@export var title_key: String = ""
@export var hint_key: String = ""
@export var type: Type = Type.REACH_ZONE
## Tag of facility anchors / interactables / zones this objective targets.
@export var target_tag: StringName
## How many of the candidate targets are activated (rest stay dormant) - procedural variation.
@export var target_count: int = 1
## Item ids this objective needs. With pick_items > 0 the generator picks that many from the pool.
@export var item_pool: PackedStringArray = PackedStringArray()
@export var pick_items: int = 0
@export var required_count: int = 1
## Where required items are spawned (feature tag). Empty = do not spawn (items come from elsewhere).
@export var spawn_items_tag: StringName
## Extra copies of required items spawned so players are not soft-locked by bad luck.
@export var spare_items: int = 1
## Hold time (s) for interact/deliver, or duration for SURVIVE.
@export var duration: float = 0.0
@export var require_all_players: bool = false
## Mission flag set when the objective completes (e.g. power_main).
@export var sets_flag: StringName
@export var events_on_start: PackedStringArray = PackedStringArray()
@export var events_on_complete: PackedStringArray = PackedStringArray()
## Threat added to the escalation meter on completion (0..1 scale).
@export var threat_on_complete: float = 0.05
## Noise radius produced while working on this objective (attracts enemies).
@export var work_noise: float = 0.0
@export var reward_xp: int = 50
@export var reward_currency: int = 10
@export var optional: bool = false
## Interactables/doors with this tag are unlocked when the objective completes.
@export var unlock_tag: StringName
## Item spawned at the target when completed (e.g. sample case after the console).
@export var grants_item: StringName
## COLLECT: show players which rooms hide the required items (e.g. after a terminal hack).
@export var reveal_item_location: bool = false
