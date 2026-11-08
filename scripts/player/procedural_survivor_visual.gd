class_name ProceduralSurvivorVisual
extends CharacterVisual
## Development character: an articulated hazard-suit operative built from shaped meshes,
## animated procedurally (walk/sprint/crouch/downed/dead, look pitch, breathing). It reads
## cosmetics (suit colours, helmet accent) and is replaced by a rigged model later through
## CharacterModelData without touching gameplay.

var _hips: Node3D
var _spine: Node3D
var _head: Node3D
var _arm: Array[Node3D] = []      # shoulders L, R
var _forearm: Array[Node3D] = []
var _thigh: Array[Node3D] = []
var _shin: Array[Node3D] = []
var _anchor: Node3D
var _suit_parts: Array[MeshInstance3D] = []
var _dark_parts: Array[MeshInstance3D] = []
var _accent_parts: Array[MeshInstance3D] = []

var _phase := 0.0
var _speed := 0.0
var _pose := Pose.STAND
var _sprint := false
var _pitch := 0.0
var _pose_blend := 0.0      # 0 stand .. 1 crouch
var _down_blend := 0.0      # 0 upright .. 1 lying
var _last_step_sign := 1.0
var _t := 0.0

const HIP_H := 0.95


func _ready() -> void:
	_build()


func _build() -> void:
	_hips = _joint(self, Vector3(0, HIP_H, 0))
	_part(_hips, MeshKit.capsule_mesh(0.17, 0.42), _suit_parts, Vector3(0, 0.02, 0), Vector3(0, 0, 90), Vector3(1, 1, 0.75))
	_spine = _joint(_hips, Vector3(0, 0.08, 0))
	_part(_spine, MeshKit.capsule_mesh(0.2, 0.62), _suit_parts, Vector3(0, 0.3, 0), Vector3.ZERO, Vector3(1.08, 1, 0.72))
	# chest rig / vest
	_part(_spine, MeshKit.box_mesh(Vector3(0.38, 0.32, 0.12)), _dark_parts, Vector3(0, 0.38, 0.12))
	var lamp := MeshKit.add_box(_spine, Vector3(0.08, 0.05, 0.03), "emissive_amber", Vector3(0.1, 0.48, 0.19))
	_accent_parts.append(lamp)
	# backpack with oxygen cylinder
	_part(_spine, MeshKit.box_mesh(Vector3(0.34, 0.42, 0.18)), _dark_parts, Vector3(0, 0.35, -0.2))
	_part(_spine, MeshKit.cyl_mesh(0.06, 0.4), _suit_parts, Vector3(0.12, 0.38, -0.31))
	_head = _joint(_spine, Vector3(0, 0.66, 0.02))
	_part(_head, MeshKit.sphere_mesh(0.13, 14), _dark_parts, Vector3(0, 0.1, 0), Vector3.ZERO, Vector3(1, 1.08, 1.04))
	# helmet + visor
	_part(_head, MeshKit.sphere_mesh(0.165, 14), _suit_parts, Vector3(0, 0.13, -0.01), Vector3.ZERO, Vector3(1, 0.92, 1.05))
	var visor := MeshKit.add_mesh(_head, MeshKit.box_mesh(Vector3(0.22, 0.08, 0.06)), "emissive_cyan", Vector3(0, 0.11, 0.14))
	_accent_parts.append(visor)
	for s in [-1.0, 1.0]:
		var sh := _joint(_spine, Vector3(0.25 * s, 0.53, 0))
		_part(sh, MeshKit.sphere_mesh(0.09, 10), _suit_parts, Vector3.ZERO)
		_part(sh, MeshKit.capsule_mesh(0.065, 0.32), _suit_parts, Vector3(0, -0.16, 0))
		var el := _joint(sh, Vector3(0, -0.31, 0))
		_part(el, MeshKit.capsule_mesh(0.055, 0.3), _suit_parts, Vector3(0, -0.14, 0))
		_part(el, MeshKit.sphere_mesh(0.055, 8), _dark_parts, Vector3(0, -0.31, 0.01))
		_arm.append(sh)
		_forearm.append(el)
		var hp := _joint(_hips, Vector3(0.11 * s, -0.04, 0))
		_part(hp, MeshKit.capsule_mesh(0.085, 0.46), _suit_parts, Vector3(0, -0.22, 0))
		var kn := _joint(hp, Vector3(0, -0.44, 0))
		_part(kn, MeshKit.capsule_mesh(0.07, 0.44), _suit_parts, Vector3(0, -0.2, 0))
		_part(kn, MeshKit.box_mesh(Vector3(0.11, 0.08, 0.24)), _dark_parts, Vector3(0, -0.44, 0.05))
		_thigh.append(hp)
		_shin.append(kn)
	_anchor = _joint(_arm[1], Vector3(0.0, -0.1, 0.12))
	apply_cosmetics({})


func _joint(parent: Node3D, pos: Vector3) -> Node3D:
	var j := Node3D.new()
	j.position = pos
	parent.add_child(j)
	return j


func _part(parent: Node3D, mesh: Mesh, group: Array[MeshInstance3D], pos: Vector3, rot := Vector3.ZERO, scl := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.rotation_degrees = rot
	mi.scale = scl
	parent.add_child(mi)
	group.append(mi)
	return mi


func flashlight_anchor() -> Node3D:
	return _anchor


func apply_cosmetics(cosmetics: Dictionary) -> void:
	var primary := Color(0.32, 0.36, 0.34)
	var secondary := Color(0.1, 0.11, 0.12)
	var accent := Color(1.0, 0.62, 0.18)
	var suit: CosmeticData = Content.cosmetic(StringName(str(cosmetics.get(str(CosmeticData.Slot.SUIT_COLOR), ""))))
	if suit:
		primary = suit.primary_color
		secondary = suit.secondary_color
	var helmet: CosmeticData = Content.cosmetic(StringName(str(cosmetics.get(str(CosmeticData.Slot.HELMET), ""))))
	if helmet:
		accent = helmet.accent_color
	var suit_mat := StandardMaterial3D.new()
	suit_mat.albedo_color = primary
	suit_mat.roughness = 0.8
	var dark_mat := StandardMaterial3D.new()
	dark_mat.albedo_color = secondary
	dark_mat.roughness = 0.6
	dark_mat.metallic = 0.2
	var accent_mat := StandardMaterial3D.new()
	accent_mat.albedo_color = accent * 0.4
	accent_mat.emission_enabled = true
	accent_mat.emission = accent
	accent_mat.emission_energy_multiplier = 2.5
	for m in _suit_parts:
		m.material_override = suit_mat
	for m in _dark_parts:
		m.material_override = dark_mat
	for m in _accent_parts:
		m.material_override = accent_mat


func set_motion(speed_ratio: float, pose: int, sprinting: bool) -> void:
	_speed = speed_ratio
	_pose = pose as Pose
	_sprint = sprinting
	visible = pose != Pose.HIDDEN


func set_look_pitch(pitch_rad: float) -> void:
	_pitch = pitch_rad


func _process(delta: float) -> void:
	if not visible:
		return
	_t += delta
	var crouch_target := 1.0 if _pose == Pose.CROUCH else 0.0
	var down_target := 1.0 if _pose == Pose.DOWNED or _pose == Pose.DEAD else 0.0
	_pose_blend = move_toward(_pose_blend, crouch_target, delta * 5.0)
	_down_blend = move_toward(_down_blend, down_target, delta * 3.0)
	var moving := _speed > 0.05
	_phase += delta * (4.2 + _speed * 3.2) * (1.0 if moving else 0.0)
	var swing := clampf(_speed, 0.0, 1.8)
	var s := sin(_phase)
	var c := cos(_phase)
	var breath := sin(_t * 1.8) * 0.012
	var crawling := _pose == Pose.DOWNED and moving
	var dead := _pose == Pose.DEAD

	# hips height / lean
	var hip_y := HIP_H - _pose_blend * 0.32 + absf(c) * 0.04 * swing
	hip_y = lerpf(hip_y, 0.22, _down_blend)
	_hips.position.y = hip_y
	_hips.rotation.x = lerpf(-0.08 * swing - _pose_blend * 0.1, -1.45, _down_blend)
	_spine.rotation.x = lerpf(0.12 * swing * (1.4 if _sprint else 1.0) + _pose_blend * 0.35 + breath, 0.15, _down_blend)
	_spine.rotation.y = s * 0.08 * swing
	_head.rotation.x = clampf(-_pitch * 0.6, -0.6, 0.6) * (1.0 - _down_blend) - _spine.rotation.x * 0.5 + lerpf(0.0, -0.9, _down_blend)

	var leg_amp := 0.55 * swing
	for i in 2:
		var side := 1.0 if i == 0 else -1.0
		var ph := s * side
		if crawling:
			ph = sin(_phase * 0.6) * side
		_thigh[i].rotation.x = ph * leg_amp - _pose_blend * 1.0 + lerpf(0.0, 0.1 * ph, _down_blend)
		_shin[i].rotation.x = maxf(0.0, -cos(_phase + (0.0 if side > 0 else PI))) * 0.9 * swing + _pose_blend * 1.6
		var arm_swing := -ph * 0.5 * swing
		if dead:
			_arm[i].rotation.x = -0.25
			_forearm[i].rotation.x = -0.2
		elif i == 1:
			# right arm holds the flashlight forward, following the look pitch
			_arm[i].rotation.x = lerpf(-1.2 - _pitch * 0.8, -2.6, _down_blend)
			_forearm[i].rotation.x = -0.25
		else:
			var reach := -2.4 + (sin(_phase * 0.6) * 0.5 if crawling else 0.0)
			_arm[i].rotation.x = arm_swing + lerpf(0.0, reach, _down_blend)
			_forearm[i].rotation.x = -0.35 - absf(arm_swing) * 0.4
		_arm[i].rotation.z = side * (0.08 + breath)
	if dead:
		_hips.rotation.z = lerpf(_hips.rotation.z, 0.6, delta * 2.0)
	else:
		_hips.rotation.z = lerpf(_hips.rotation.z, 0.0, delta * 4.0)

	# footsteps at each foot plant
	if moving and _pose != Pose.DOWNED and not dead:
		var step_sign := signf(s)
		if step_sign != _last_step_sign and step_sign != 0.0:
			_last_step_sign = step_sign
			footstep.emit(clampf(_speed, 0.2, 1.8) * (0.4 if _pose == Pose.CROUCH else 1.0))
