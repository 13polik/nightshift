class_name SkinnedCharacterVisual
extends CharacterVisual
## Rigged, animated character (survivor or creature) driven through an AnimationTree that
## is assembled in code from the model's animation names:
##
##   pose (Transition) --> work (Transition) --> hit/oneshot layers --> output
##     stand  : BlendSpace1D  idle / walk / run      (blend = speed ratio)
##     crouch : BlendSpace1D  crouch_idle / crouch_walk
##     downed : BlendSpace1D  downed_idle / crawl
##     dead   : death (clamped on its last frame)
##
## Creatures use profile "creature": a state Transition (idle, patrol, investigate,
## search, chase, stunned) plus one-shots (attack, alert, door_open) and a TimeScale so
## gait speed matches movement. Every input comes from replicated gameplay state, so all
## peers show the same animation without extra network traffic.

@export var model_scene: PackedScene
@export_enum("survivor", "creature") var profile: String = "survivor"
## Model-space point (Godot coords) the flashlight is mounted to (chest lamp).
@export var light_mount := Vector3(0.1, 1.47, -0.17)
@export var light_mount_bone := "chest"
## metres travelled per footstep at walk / run speeds
@export var stride := 0.75
## Bone + model-space grip point (Godot coords) where held items are placed.
@export var hand_bone := "hand_R"
@export var hand_grip := Vector3(0.305, 0.89, -0.04)

const LOOPS := ["idle", "walk", "run", "crouch_idle", "crouch_walk", "crawl", "downed_idle", "interact", "revive",
	"patrol", "investigate", "search", "chase", "stunned"]
const CREATURE_STATES := ["idle", "patrol", "investigate", "search", "chase", "stunned"]
## nominal ground speed (m/s) of each creature gait animation, for speed matching
const CREATURE_GAIT_SPEED := {"idle": 0.0, "patrol": 1.6, "investigate": 2.4, "search": 0.0, "chase": 4.9, "stunned": 0.0}

var model: Node3D
var skeleton: Skeleton3D
var anim_player: AnimationPlayer
var tree: AnimationTree
var _anchor: Node3D
var _pose := Pose.STAND
var _speed := 0.0
var _work := "none"
var _ai_state: StringName = &"IDLE"
var _dist := 0.0
var _suit_tint := Color.WHITE
var _ready_done := false
var _hand: Node3D
var _held_id: StringName = &""
var _held: Node3D


func _ready() -> void:
	if model_scene == null:
		push_error("SkinnedCharacterVisual without model_scene")
		return
	model = model_scene.instantiate()
	add_child(model)
	MaterialLibrary.apply_named(model)
	skeleton = model.find_child("*", true, false) as Skeleton3D
	for n in model.find_children("*", "Skeleton3D", true, false):
		skeleton = n
	for n in model.find_children("*", "AnimationPlayer", true, false):
		anim_player = n
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	if anim_player:
		_setup_loops()
		_build_tree()
	_build_anchor()
	_build_hand()
	_ready_done = true


func _setup_loops() -> void:
	for lib_name in anim_player.get_animation_library_list():
		var lib := anim_player.get_animation_library(lib_name)
		for a in lib.get_animation_list():
			var anim := lib.get_animation(a)
			anim.loop_mode = Animation.LOOP_LINEAR if String(a) in LOOPS else Animation.LOOP_NONE


func _has(anim: String) -> bool:
	return anim_player.has_animation(anim)


func _anim_node(anim: String) -> AnimationNodeAnimation:
	var n := AnimationNodeAnimation.new()
	n.animation = anim if _has(anim) else ("idle" if _has("idle") else "")
	return n


func _space(points: Array) -> AnimationNodeBlendSpace1D:
	var bs := AnimationNodeBlendSpace1D.new()
	bs.min_space = 0.0
	bs.max_space = 2.0
	for i in points.size():
		var p: Array = points[i]
		bs.add_blend_point(_anim_node(p[0]), p[1], -1, StringName("p%d" % i))
	return bs


func _transition(inputs: Array, xfade: float) -> AnimationNodeTransition:
	var t := AnimationNodeTransition.new()
	t.xfade_time = xfade
	for i in inputs:
		t.add_input(i)
	return t


func _oneshot(fade_in := 0.1, fade_out := 0.2) -> AnimationNodeOneShot:
	var o := AnimationNodeOneShot.new()
	o.fadein_time = fade_in
	o.fadeout_time = fade_out
	return o


func _build_tree() -> void:
	var bt := AnimationNodeBlendTree.new()
	if profile == "survivor":
		bt.add_node("stand", _space([["idle", 0.0], ["walk", 1.0], ["run", 1.8]]), Vector2(0, 0))
		bt.add_node("crouch", _space([["crouch_idle", 0.0], ["crouch_walk", 1.0]]), Vector2(0, 150))
		bt.add_node("downed", _space([["downed_idle", 0.0], ["crawl", 0.3]]), Vector2(0, 300))
		bt.add_node("dead", _anim_node("death"), Vector2(0, 450))
		bt.add_node("pose", _transition(["stand", "crouch", "downed", "dead"], 0.25), Vector2(250, 150))
		bt.add_node("interact", _anim_node("interact"), Vector2(250, 350))
		bt.add_node("revive", _anim_node("revive"), Vector2(250, 450))
		bt.add_node("work", _transition(["none", "interact", "revive"], 0.25), Vector2(450, 200))
		bt.add_node("use_anim", _anim_node("use_item"), Vector2(450, 400))
		bt.add_node("use", _oneshot(0.15, 0.2), Vector2(650, 200))
		bt.add_node("hit_anim", _anim_node("hit"), Vector2(650, 400))
		bt.add_node("hit", _oneshot(0.05, 0.15), Vector2(850, 200))
		for i in 4:
			bt.connect_node("pose", i, ["stand", "crouch", "downed", "dead"][i])
		bt.connect_node("work", 0, "pose")
		bt.connect_node("work", 1, "interact")
		bt.connect_node("work", 2, "revive")
		bt.connect_node("use", 0, "work")
		bt.connect_node("use", 1, "use_anim")
		bt.connect_node("hit", 0, "use")
		bt.connect_node("hit", 1, "hit_anim")
		bt.connect_node("output", 0, "hit")
	else:
		var i := 0
		for st in CREATURE_STATES:
			bt.add_node(st, _anim_node(st), Vector2(0, i * 120))
			i += 1
		bt.add_node("state", _transition(CREATURE_STATES, 0.3), Vector2(250, 300))
		bt.add_node("speed", AnimationNodeTimeScale.new(), Vector2(450, 300))
		for k in CREATURE_STATES.size():
			bt.connect_node("state", k, CREATURE_STATES[k])
		bt.connect_node("speed", 0, "state")
		var prev := "speed"
		var x := 650
		for shot in ["door_open", "attack", "alert"]:
			bt.add_node(shot + "_anim", _anim_node(shot), Vector2(x, 500))
			bt.add_node(shot, _oneshot(0.08, 0.25), Vector2(x, 300))
			bt.connect_node(shot, 0, prev)
			bt.connect_node(shot, 1, shot + "_anim")
			prev = shot
			x += 200
		bt.connect_node("output", 0, prev)
	tree = AnimationTree.new()
	tree.name = "AnimationTree"
	tree.tree_root = bt
	tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_IDLE
	model.add_child(tree)
	tree.anim_player = tree.get_path_to(anim_player)
	tree.active = true
	# Transition nodes output nothing until their first request: prime every layer.
	if profile == "survivor":
		tree.set("parameters/pose/transition_request", "stand")
		tree.set("parameters/work/transition_request", "none")
	else:
		tree.set("parameters/state/transition_request", "idle")


func _build_anchor() -> void:
	_anchor = Node3D.new()
	_anchor.name = "LightAnchor"
	if skeleton and skeleton.find_bone(light_mount_bone) != -1:
		var att := BoneAttachment3D.new()
		att.bone_name = light_mount_bone
		skeleton.add_child(att)
		var rest := skeleton.get_bone_global_rest(skeleton.find_bone(light_mount_bone))
		_anchor.transform = Transform3D(Basis(), rest.affine_inverse() * light_mount)
		att.add_child(_anchor)
	else:
		_anchor.position = light_mount
		add_child(_anchor)


func _build_hand() -> void:
	if skeleton == null or skeleton.find_bone(hand_bone) == -1:
		return
	var att := BoneAttachment3D.new()
	att.name = "HandAttachment"
	att.bone_name = hand_bone
	skeleton.add_child(att)
	_hand = Node3D.new()
	_hand.name = "HeldItem"
	# convert the model-space grip into the bone's rest frame
	var skel_in_model := _relative_to_model(skeleton)
	var rest := skel_in_model * skeleton.get_bone_global_rest(skeleton.find_bone(hand_bone))
	_hand.transform = rest.affine_inverse() * Transform3D(Basis(), hand_grip)
	att.add_child(_hand)


func _relative_to_model(n: Node3D) -> Transform3D:
	var t := Transform3D()
	var cur: Node = n
	while cur and cur != model:
		if cur is Node3D:
			t = (cur as Node3D).transform * t
		cur = cur.get_parent()
	return t


func set_held_item(item: StringName) -> void:
	if not _ready_done:
		await ready
	if _hand == null or item == _held_id:
		return
	_held_id = item
	if _held:
		_held.queue_free()
		_held = null
	if item == &"":
		return
	var ps := PropFactory.model_for(String(item), "items")
	if ps == null:
		return
	var inst: Node3D = ps.instantiate()
	MaterialLibrary.apply_named(inst)
	for mi in inst.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_held = Node3D.new()
	_held.add_child(inst)
	_hand.add_child(_held)
	_pose_held(inst)
	_update_held_visibility()


## Grip pose derived from the model's bounds. The hand node is already aligned with the
## model at rest (bone rest x inverse rest), so items keep a natural upright orientation:
## small items sit under the palm, long thin items (crowbar) hang along the arm gripped
## near one end.
func _pose_held(inst: Node3D) -> void:
	var b := AABB()
	var first := true
	for mi in inst.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var bb := _relative_xf(inst, m) * m.get_aabb()
		b = bb if first else b.merge(bb)
		first = false
	var c := b.get_center()
	if b.size.x > 0.3 and b.size.x > b.size.y * 2.5 and b.size.x > b.size.z * 1.5:
		# +90 deg about Z maps (x, y, z) -> (-y, x, z): the +X end points up into the hand,
		# the rest hangs down. Grip 20 % in from the +X end.
		inst.rotation = Vector3(0, 0, PI * 0.5)
		var grip_x := b.end.x - b.size.x * 0.2
		inst.position = Vector3(c.y, -grip_x, -c.z)
	else:
		inst.position = Vector3(-c.x, -b.end.y + 0.02, -c.z)


func _relative_xf(root: Node3D, n: Node3D) -> Transform3D:
	var t := n.transform
	var p := n.get_parent()
	while p and p != root:
		if p is Node3D:
			t = (p as Node3D).transform * t
		p = p.get_parent()
	return t


func _update_held_visibility() -> void:
	if _held:
		_held.visible = _pose == Pose.STAND or _pose == Pose.CROUCH


func flashlight_anchor() -> Node3D:
	return _anchor if _anchor else self


# --- CharacterVisual API ---------------------------------------------------------------

func set_motion(speed_ratio: float, pose: int, sprinting: bool) -> void:
	_speed = speed_ratio
	_pose = pose as Pose
	visible = pose != Pose.HIDDEN
	_update_held_visibility()
	if tree == null:
		return
	if profile == "survivor":
		var target := 0
		match _pose:
			Pose.CROUCH: target = 1
			Pose.DOWNED: target = 2
			Pose.DEAD: target = 3
		_set_transition("pose", ["stand", "crouch", "downed", "dead"][target])
		tree.set("parameters/stand/blend_position", clampf(speed_ratio * (1.0 if not sprinting else 1.05), 0.0, 1.8))
		tree.set("parameters/crouch/blend_position", clampf(speed_ratio * 1.6, 0.0, 1.0))
		tree.set("parameters/downed/blend_position", clampf(speed_ratio, 0.0, 0.3))
	else:
		var st := _creature_anim()
		_set_transition("state", st)
		var nominal: float = CREATURE_GAIT_SPEED.get(st, 0.0)
		var actual := speed_ratio * 2.0
		tree.set("parameters/speed/scale", clampf(actual / nominal, 0.5, 1.6) if nominal > 0.0 else 1.0)


func _set_transition(node: String, state: String) -> void:
	var path := "parameters/%s/transition_request" % node
	var cur := "parameters/%s/current_state" % node
	if str(tree.get(cur)) != state:
		tree.set(path, state)


func _creature_anim() -> String:
	var moving := _speed > 0.15
	match _ai_state:
		&"CHASE", &"ATTACK":
			return "chase" if moving else "search"
		&"INVESTIGATE", &"LOST_TARGET":
			return "investigate" if moving else "search"
		&"SEARCH":
			return "investigate" if moving else "search"
		&"STUNNED":
			return "stunned"
		&"ALERT":
			return "idle"
		&"IDLE":
			return "patrol" if moving else "idle"
	return "patrol" if moving else "idle"


func set_ai_state(s: StringName) -> void:
	_ai_state = s


## Survivor: &"interact", &"revive", &"none" (held states), &"use_item", &"hit" (one-shots).
## Creature: &"attack", &"alert", &"door" (one-shots).
func play_action(action: StringName) -> void:
	if tree == null:
		return
	match String(action):
		"interact", "revive", "none":
			if _work != String(action):
				_work = String(action)
				tree.set("parameters/work/transition_request", _work)
		"use_item":
			tree.set("parameters/use/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
		"hit":
			if profile == "survivor":
				tree.set("parameters/hit/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
		"attack", "alert":
			tree.set("parameters/%s/request" % action, AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
		"door":
			tree.set("parameters/door_open/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


func set_look_pitch(_pitch_rad: float) -> void:
	pass


func apply_cosmetics(cosmetics: Dictionary) -> void:
	if not _ready_done:
		await ready
	if model == null:
		return
	var suit: CosmeticData = Content.cosmetic(StringName(str(cosmetics.get(str(CosmeticData.Slot.SUIT_COLOR), ""))))
	var helmet: CosmeticData = Content.cosmetic(StringName(str(cosmetics.get(str(CosmeticData.Slot.HELMET), ""))))
	# fabric texture is light grey (~0.6); scale so the suit colour reads correctly
	var suit_col := (suit.primary_color * 1.7) if suit else Color(0.55, 0.6, 0.55)
	var accent := helmet.accent_color if helmet else Color(1.0, 0.62, 0.18)
	var lamp := MaterialLibrary.get_mat("emissive_amber").duplicate() as StandardMaterial3D
	lamp.emission = accent
	lamp.albedo_color = accent * 0.4
	var visor := MaterialLibrary.get_mat("visor").duplicate() as StandardMaterial3D
	visor.emission = accent.lerp(Color(0.2, 0.9, 1.0), 0.5)
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		for i in m.mesh.get_surface_count():
			var src := m.mesh.surface_get_material(i)
			var n := String(src.resource_name).get_slice(".", 0) if src else ""
			match n:
				"fabric_suit":
					m.set_surface_override_material(i, MaterialLibrary.tinted("fabric_suit", suit_col))
				"emissive_amber":
					m.set_surface_override_material(i, lamp)
				"visor":
					m.set_surface_override_material(i, visor)


func _process(delta: float) -> void:
	if not visible or _pose == Pose.DEAD:
		return
	# footsteps from distance travelled (independent of animation timing => robust)
	var mps := _speed * (2.0 if profile == "creature" else 3.0)
	if mps > 0.3:
		_dist += mps * delta
		var step := stride * (1.35 if _speed > 1.25 else 1.0)
		if _pose == Pose.DOWNED:
			step *= 1.5
		if _dist >= step:
			_dist = 0.0
			footstep.emit(clampf(_speed, 0.2, 1.8) * (0.4 if _pose == Pose.CROUCH else 1.0))
