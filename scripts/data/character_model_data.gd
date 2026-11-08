class_name CharacterModelData
extends Resource
## Points at a visual scene implementing CharacterVisual. Swapping the art for a rigged,
## animated model only requires a new CharacterModelData - gameplay code is untouched.

@export var id: StringName
@export var name_key: String = ""
## Scene whose root script extends CharacterVisual. Null = procedural dev visual.
@export var scene: PackedScene
@export var height: float = 1.8
