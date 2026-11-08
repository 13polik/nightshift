class_name AnimatedCharacterVisual
extends CharacterVisual
## Adapter for production character models: an imported rigged scene with an AnimationTree
## whose state machine exposes these parameters:
##   parameters/locomotion/blend_position (float speed ratio)
##   parameters/conditions/crouched, downed, dead (bools)
##   parameters/look_pitch/blend_position (float)
## Gameplay code does not change when switching from ProceduralSurvivorVisual to this.

@export var animation_tree: AnimationTree
@export var flashlight_bone_attachment: Node3D
@export var footstep_threshold: float = 0.5

var _last_phase := 0.0


func set_motion(speed_ratio: float, pose: int, _sprinting: bool) -> void:
	visible = pose != Pose.HIDDEN
	if animation_tree == null:
		return
	animation_tree.set("parameters/locomotion/blend_position", speed_ratio)
	animation_tree.set("parameters/conditions/crouched", pose == Pose.CROUCH)
	animation_tree.set("parameters/conditions/downed", pose == Pose.DOWNED)
	animation_tree.set("parameters/conditions/dead", pose == Pose.DEAD)


func set_look_pitch(pitch_rad: float) -> void:
	if animation_tree:
		animation_tree.set("parameters/look_pitch/blend_position", pitch_rad)


func play_action(action: StringName) -> void:
	if animation_tree:
		animation_tree.set("parameters/%s/request" % action, AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


func flashlight_anchor() -> Node3D:
	return flashlight_bone_attachment if flashlight_bone_attachment else self


## Animation tracks call this through a method track on foot plants.
func anim_footstep(strength: float = 1.0) -> void:
	footstep.emit(strength)
