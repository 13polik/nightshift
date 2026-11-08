class_name CosmeticData
extends Resource
## Purely visual customisation item. `store_sku` is reserved for future (cosmetic-only)
## monetisation: the unlock pipeline already supports non-currency sources.

enum Slot { SUIT_COLOR, OUTFIT, HELMET, FLASHLIGHT, TOOL, PROFILE_ICON, PROFILE_BANNER }
enum Rarity { COMMON, UNCOMMON, RARE, EPIC, LEGENDARY }
enum Source { DEFAULT, LEVEL, CURRENCY, ACHIEVEMENT, STORE, EVENT }

@export var id: StringName
@export var name_key: String = ""
@export var slot: Slot = Slot.SUIT_COLOR
@export var rarity: Rarity = Rarity.COMMON
@export var source: Source = Source.CURRENCY
@export var price: int = 0
@export var unlock_level: int = 1
@export var store_sku: String = ""
@export var primary_color: Color = Color(0.25, 0.3, 0.32)
@export var secondary_color: Color = Color(0.12, 0.13, 0.14)
@export var accent_color: Color = Color(1.0, 0.65, 0.2)
## Optional mesh/scene override applied by the character visual (outfits, helmets...).
@export var model_override: PackedScene
@export var icon_glyph: String = "*"


func is_default() -> bool:
	return source == Source.DEFAULT
