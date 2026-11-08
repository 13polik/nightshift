class_name LoadoutOptionData
extends Resource
## Starting equipment a player can bring into a mission. Players pick one option.

@export var id: StringName
@export var name_key: String = ""
@export var description_key: String = ""
@export var unlock_level: int = 1
## item id (String) -> count
@export var items: Dictionary = {}
