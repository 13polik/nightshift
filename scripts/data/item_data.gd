class_name ItemData
extends Resource
## Static definition of an inventory item. Instances live in res://data/items/*.tres
## and are registered by id in the Content database.

enum Category { CONSUMABLE, TOOL, KEY, COMPONENT, OBJECTIVE, AMMO }
enum UseEffect { NONE, HEAL, RECHARGE_BATTERY, STUN_PULSE }

@export var id: StringName
@export var name_key: String = ""
@export var description_key: String = ""
@export var category: Category = Category.CONSUMABLE
@export var icon: Texture2D
## Fallback glyph drawn in the HUD when no icon texture is assigned.
@export var icon_glyph: String = "?"
@export var color: Color = Color(0.8, 0.85, 0.9)
@export_range(1, 99) var max_stack: int = 1
@export var use_effect: UseEffect = UseEffect.NONE
@export var effect_amount: float = 0.0
## Seconds the player must channel to use the item (0 = instant).
@export var use_time: float = 0.0
@export var consumed_on_use: bool = true
## Optional item id that must be in the inventory (and is consumed) to use this one (e.g. ammo).
@export var requires_ammo: StringName
@export var droppable: bool = true
## Optional replacement world model. When null a procedural dev model is generated.
@export var world_model: PackedScene
## Relative probability when rolled from a loot table without explicit weights.
@export var spawn_weight: float = 1.0
@export var tags: PackedStringArray = PackedStringArray()


## Inventory icon: the hand-assigned texture, else the icon rendered from the item's 3D
## model (tools/render_icons.tscn -> res://assets/ui/icons/<id>.png), else null (glyph).
func get_icon() -> Texture2D:
	if icon:
		return icon
	var p := "res://assets/ui/icons/%s.png" % id
	if ResourceLoader.exists(p):
		icon = load(p)
	return icon


func is_usable() -> bool:
	return use_effect != UseEffect.NONE


func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if id == &"":
		errors.append("item has empty id")
	if name_key.is_empty():
		errors.append("item %s has no name_key" % id)
	if max_stack < 1:
		errors.append("item %s max_stack < 1" % id)
	return errors
