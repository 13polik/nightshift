class_name CharacterVisual
extends Node3D
## Interface between gameplay and character art. Gameplay only calls these methods, so a
## rigged/animated model (AnimationTree) can replace the procedural dev visual by
## implementing the same API (see AnimatedCharacterVisual).

signal footstep(strength: float)

enum Pose { STAND, CROUCH, DOWNED, DEAD, HIDDEN }

## speed_ratio: 0 idle .. 1 walk .. ~1.8 sprint
func set_motion(_speed_ratio: float, _pose: int, _sprinting: bool) -> void:
	pass


func set_look_pitch(_pitch_rad: float) -> void:
	pass


func play_action(_action: StringName) -> void:
	pass


func apply_cosmetics(_cosmetics: Dictionary) -> void:
	pass


## Shows the given item in the character's hand (&"" = empty hand).
func set_held_item(_item: StringName) -> void:
	pass


## World-space attachment for the flashlight (shoulder / hand).
func flashlight_anchor() -> Node3D:
	return self
