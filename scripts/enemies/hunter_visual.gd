class_name HunterVisual
extends CharacterVisual
## Development model for THE HUNTER: a gaunt, too-tall figure with long arms, a hunched
## spine and pale glowing eyes. Procedural stalking/sprinting/attack/alert/stun poses.
## Replace with a rigged creature via EnemyData.scene + AnimatedCharacterVisual.

var _root: Node3D
var _spine: Node3D
var _neck: Node3D
var _head: Node3D
var _arms: Array[Node3D] = []
var _elbows: Array[Node3D] = []
var _legs: Array[Node3D] = []
var _knees: Array[Node3D] = []
var _eyes: Array[MeshInstance3D] = []
var _phase := 0.0
var _speed := 0.0
var _sprint := false
var _state: StringName = &"IDLE"
var _state_t := 0.0
var _last_step := 1.0
var _t := 0.0


func _ready() -> void:
	var skin := "hunter_skin"
	_root = _j(self, Vector3(0, 1.25, 0))
	_mesh(_root, MeshKit.capsule_mesh(0.16, 0.45), skin, Vector3(0, 0, 0), Vector3(0, 0, 90), Vector3(1, 1, 0.7))
	_spine = _j(_root, Vector3(0, 0.1, 0))
	_mesh(_spine, MeshKit.capsule_mesh(0.17, 0.85), skin, Vector3(0, 0.42, 0.02), Vector3.ZERO, Vector3(1.15, 1, 0.65))
	# exposed ribs / vertebrae ridge
	for i in 5:
		_mesh(_spine, MeshKit.sphere_mesh(0.05, 6), skin, Vector3(0, 0.15 + i * 0.15, -0.14))
	_neck = _j(_spine, Vector3(0, 0.85, 0.06))
	_mesh(_neck, MeshKit.capsule_mesh(0.06, 0.3), skin, Vector3(0, 0.1, 0.05), Vector3(30, 0, 0))
	_head = _j(_neck, Vector3(0, 0.22, 0.12))
	_mesh(_head, MeshKit.sphere_mesh(0.15, 12), skin, Vector3(0, 0.06, 0.04), Vector3.ZERO, Vector3(0.85, 1.25, 1.1))
	_mesh(_head, MeshKit.box_mesh(Vector3(0.16, 0.05, 0.14)), "metal_dark", Vector3(0, -0.07, 0.1))
	for s in [-1.0, 1.0]:
		_eyes.append(_mesh(_head, MeshKit.sphere_mesh(0.025, 6), "hunter_eyes", Vector3(0.05 * s, 0.1, 0.16)))
		var sh := _j(_spine, Vector3(0.24 * s, 0.75, 0))
		_mesh(sh, MeshKit.capsule_mesh(0.05, 0.6), skin, Vector3(0, -0.3, 0))
		var el := _j(sh, Vector3(0, -0.6, 0))
		_mesh(el, MeshKit.capsule_mesh(0.045, 0.6), skin, Vector3(0, -0.3, 0))
		for f in 3:
			_mesh(el, MeshKit.cyl_mesh(0.012, 0.22, 0.004, 5), "metal_dark", Vector3((f - 1) * 0.03, -0.68, 0.03), Vector3(10, 0, (f - 1) * 8))
		_arms.append(sh)
		_elbows.append(el)
		var hp := _j(_root, Vector3(0.12 * s, -0.05, 0))
		_mesh(hp, MeshKit.capsule_mesh(0.07, 0.62), skin, Vector3(0, -0.3, 0))
		var kn := _j(hp, Vector3(0, -0.6, 0))
		_mesh(kn, MeshKit.capsule_mesh(0.055, 0.62), skin, Vector3(0, -0.3, 0))
		_legs.append(hp)
		_knees.append(kn)
	for c in find_children("*", "MeshInstance3D", true, false):
		(c as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON


func _j(parent: Node3D, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	parent.add_child(n)
	return n


func _mesh(parent: Node3D, mesh: Mesh, mat: String, pos: Vector3, rot := Vector3.ZERO, scl := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshKit.add_mesh(parent, mesh, mat, pos, rot)
	mi.scale = scl
	return mi


func set_motion(speed_ratio: float, pose: int, sprinting: bool) -> void:
	_speed = speed_ratio
	_sprint = sprinting
	visible = pose != Pose.HIDDEN


func set_ai_state(s: StringName) -> void:
	if s != _state:
		_state = s
		_state_t = 0.0


func _process(delta: float) -> void:
	if not visible:
		return
	_t += delta
	_state_t += delta
	var moving := _speed > 0.05
	_phase += delta * (2.6 + _speed * 3.5) * (1.0 if moving else 0.0)
	var s := sin(_phase)
	var amp := clampf(_speed, 0.0, 2.6) * 0.45
	var hunch := 0.5 if not _sprint else 0.85
	var head_tilt := sin(_t * 0.7) * 0.15
	match _state:
		&"ALERT":
			hunch = -0.15 + sin(_state_t * 30.0) * 0.03
			head_tilt = -0.4
		&"SEARCH", &"INVESTIGATE", &"LOST_TARGET":
			head_tilt = sin(_t * 1.9) * 0.6
		&"STUNNED":
			hunch = 0.9 + sin(_state_t * 40.0) * 0.08
			head_tilt = sin(_state_t * 25.0) * 0.5
	_root.position.y = 1.25 - hunch * 0.2 + absf(cos(_phase)) * 0.05 * amp
	_spine.rotation.x = hunch * 0.75
	_neck.rotation.x = -hunch * 0.6
	_head.rotation.z = head_tilt * (1.0 if _state != &"CHASE" else 0.2)
	_head.rotation.y = head_tilt * 0.8 if _state in [&"SEARCH", &"INVESTIGATE", &"IDLE"] else 0.0
	for i in 2:
		var side := 1.0 if i == 0 else -1.0
		_legs[i].rotation.x = s * side * amp - hunch * 0.3
		_knees[i].rotation.x = maxf(0.0, -cos(_phase + (0.0 if side > 0 else PI))) * amp * 1.4 + hunch * 0.3
		var arm_x := -s * side * amp * 0.8 - 0.25
		if _state == &"ATTACK":
			var k := clampf(_state_t / 0.55, 0.0, 1.0)
			arm_x = lerpf(-2.6, 0.6, ease(k, 3.0)) if i == 0 else lerpf(-0.4, -1.2, k)
		elif _state == &"ALERT":
			arm_x = -0.9 - sin(_state_t * 30.0) * 0.1
		_arms[i].rotation.x = arm_x
		_arms[i].rotation.z = side * (0.15 + (0.4 if _state == &"ALERT" else 0.0))
		_elbows[i].rotation.x = -0.5 - absf(s) * 0.2
	var eye_glow := 1.0 if _state in [&"CHASE", &"ALERT", &"ATTACK"] else 0.6
	for e in _eyes:
		e.scale = Vector3.ONE * eye_glow
	if moving:
		var step := signf(s)
		if step != _last_step and step != 0.0:
			_last_step = step
			footstep.emit(clampf(_speed, 0.3, 2.0))
