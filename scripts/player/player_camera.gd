class_name PlayerCamera
extends Node3D
## Third-person over-the-shoulder camera for the local player (also spectator camera).
## Look input comes from GameInput (touch drag, mouse, right stick) in degrees.

const PIVOT_HEIGHT := 1.55
const CROUCH_PIVOT := 1.05
const DOWNED_PIVOT := 0.6
const ARM_LENGTH := 2.6
const SHOULDER := 0.5
const PITCH_MIN := -70.0
const PITCH_MAX := 55.0
const BASE_FOV := 70.0
const SPRINT_FOV := 77.0
const COLLISION_MASK := 1 | 32 | 64

var target: Node3D
var yaw := 0.0
var pitch := -10.0
var camera: Camera3D
var arm: SpringArm3D
var _pitch_node: Node3D
var _pivot_h := PIVOT_HEIGHT
var _trauma := 0.0
var _shake_t := 0.0
var _fov_target := BASE_FOV
var _bob_t := 0.0


func _ready() -> void:
	top_level = true
	_pitch_node = Node3D.new()
	add_child(_pitch_node)
	arm = SpringArm3D.new()
	arm.spring_length = ARM_LENGTH
	arm.collision_mask = COLLISION_MASK
	arm.margin = 0.15
	var probe := SphereShape3D.new()
	probe.radius = 0.2
	arm.shape = probe
	arm.position = Vector3(SHOULDER, 0, 0)
	_pitch_node.add_child(arm)
	camera = Camera3D.new()
	camera.fov = BASE_FOV
	camera.near = 0.05
	camera.far = float(Settings.preset().draw_distance)
	arm.add_child(camera)
	camera.current = true
	Events.graphics_quality_changed.connect(func(_q: int) -> void:
		if is_instance_valid(camera):
			camera.far = float(Settings.preset().draw_distance))


func set_target(t: Node3D) -> void:
	target = t
	if t:
		arm.add_excluded_object((t as CollisionObject3D).get_rid() if t is CollisionObject3D else RID())


func add_trauma(amount: float) -> void:
	_trauma = clampf(_trauma + amount * float(Settings.get_value("gameplay", "camera_shake")), 0.0, 1.0)


func forward() -> Vector3:
	return -global_basis.z


## Horizontal camera basis for camera-relative movement.
func flat_basis() -> Basis:
	return Basis(Vector3.UP, deg_to_rad(yaw))


func aim_direction() -> Vector3:
	return -camera.global_basis.z if camera else -global_basis.z


func set_pose_height(pose: int) -> void:
	match pose:
		CharacterVisual.Pose.CROUCH:
			_pivot_h = CROUCH_PIVOT
		CharacterVisual.Pose.DOWNED, CharacterVisual.Pose.DEAD:
			_pivot_h = DOWNED_PIVOT
		_:
			_pivot_h = PIVOT_HEIGHT


func set_sprint(on: bool) -> void:
	_fov_target = SPRINT_FOV if on else BASE_FOV


func _process(delta: float) -> void:
	var look := GameInput.consume_look()
	var sens := float(Settings.get_value("controls", "look_sensitivity"))
	var inv := -1.0 if Settings.get_value("controls", "invert_y") else 1.0
	yaw -= look.x * sens
	pitch = clampf(pitch - look.y * sens * inv, PITCH_MIN, PITCH_MAX)
	rotation_degrees = Vector3(0, yaw, 0)
	_pitch_node.rotation_degrees = Vector3(pitch, 0, 0)
	if target and is_instance_valid(target):
		var goal := target.global_position + Vector3.UP * _pivot_h
		global_position = global_position.lerp(goal, 1.0 - exp(-delta * 18.0)) if global_position.distance_to(goal) < 4.0 else goal
	camera.fov = lerpf(camera.fov, _fov_target, 1.0 - exp(-delta * 6.0))
	# trauma-based shake
	_trauma = maxf(0.0, _trauma - delta * 1.3)
	_shake_t += delta * 30.0
	var s := _trauma * _trauma
	# subtle head bob while moving + slow breathing sway when still (scaled by the
	# camera-shake accessibility setting)
	var mv := 0.0
	if target and is_instance_valid(target) and target.has_method("ground_speed"):
		mv = clampf(float(target.call("ground_speed")) / 5.0, 0.0, 1.0)
	_bob_t += delta * (2.0 + mv * 9.0)
	var shake_set := float(Settings.get_value("gameplay", "camera_shake"))
	var bob := Vector3(sin(_bob_t) * 0.35 * mv + sin(_bob_t * 0.31) * 0.12, cos(_bob_t * 0.5) * 0.15 * mv, 0.0) * shake_set
	camera.rotation_degrees = Vector3(sin(_shake_t * 1.1) * 2.2 * s + bob.x, sin(_shake_t * 0.9 + 1.3) * 2.2 * s + bob.y, sin(_shake_t * 1.3 + 2.1) * 1.4 * s)
