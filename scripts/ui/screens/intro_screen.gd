extends Node
## Story intro, rendered in-engine: the real Kessler facility is built (solo mission in
## "cinematic" mode: HUD off, enemies parked), then a camera rail visits a few rooms while
## a narrator line types out under letterbox bars. Shown once on first launch and from
## the main menu. Any key / tap on SKIP ends it.

const FADE := 0.45

## [text_key, room ("" = black card), cam from, cam to, look at (offsets from the room's
##  floor centre), main power on, seconds, special]
const SHOTS := [
	["INTRO_01", "", Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, false, 5.0, ""],
	["INTRO_02", "yard", Vector3(-7, 1.4, 4.5), Vector3(-3.5, 1.9, 2.0), Vector3(1.5, 2.2, -6), false, 6.0, ""],
	["INTRO_03", "corridor_main", Vector3(-14, 1.6, 0.2), Vector3(-8, 1.55, -0.2), Vector3(10, 1.3, 0), false, 6.0, "flicker"],
	["INTRO_04", "containment", Vector3(-5, 2.6, 6.5), Vector3(-2.5, 2.0, 3.5), Vector3(2, 1.0, -3), false, 6.5, ""],
	["INTRO_05", "corridor_north", Vector3(-6.5, 1.45, 0.25), Vector3(-3.0, 1.6, 0.1), Vector3(0.6, 1.85, 0.2), false, 6.5, "hunter"],
	["INTRO_06", "yard", Vector3(1.0, 1.0, 5.0), Vector3(0.0, 1.35, 3.2), Vector3(0, 1.4, -2), false, 7.0, "crew"],
	["", "", Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, false, 5.0, "title"],
]

var mission: MissionController
var cam: Camera3D
var _ui: CanvasLayer
var _fade: ColorRect
var _sub: Label
var _title: VBoxContainer
var _skip: Button
var _shot := -1
var _t := 0.0
var _finished := false
var _extras: Array[Node] = []
var _flicker: OmniLight3D
var _hunter: SkinnedCharacterVisual
var _hunter_light: OmniLight3D
var _crew: Array[SkinnedCharacterVisual] = []
var _loading := false
var _shot_saved := false


func _ready() -> void:
	_build_ui()
	Audio.play_2d("music_tension", -6.0, &"Music")
	_next_shot()


func _build_ui() -> void:
	_ui = CanvasLayer.new()
	_ui.layer = 30
	add_child(_ui)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.theme = UiTheme.get_theme()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(root)
	# letterbox
	for top in [true, false]:
		var bar := ColorRect.new()
		bar.color = Color.BLACK
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.anchor_right = 1.0
		if top:
			bar.anchor_bottom = 0.11
		else:
			bar.anchor_top = 0.89
			bar.anchor_bottom = 1.0
		root.add_child(bar)
	_fade = ColorRect.new()
	_fade.color = Color.BLACK
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_fade)
	_sub = UiTheme.label("", 26, UiTheme.TEXT)
	_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_sub.anchor_left = 0.12
	_sub.anchor_right = 0.88
	_sub.anchor_top = 0.74
	_sub.anchor_bottom = 0.88
	_sub.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_sub.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_sub.add_theme_constant_override("shadow_offset_x", 2)
	_sub.add_theme_constant_override("shadow_offset_y", 2)
	root.add_child(_sub)
	_title = VBoxContainer.new()
	_title.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_title.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_title.grow_vertical = Control.GROW_DIRECTION_BOTH
	_title.alignment = BoxContainer.ALIGNMENT_CENTER
	_title.modulate.a = 0.0
	var t1 := UiTheme.label("NIGHT SHIFT", 84, UiTheme.TEXT)
	t1.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_child(t1)
	var t2 := UiTheme.label(tr("INTRO_TAGLINE"), 24, UiTheme.ACCENT)
	t2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_child(t2)
	root.add_child(_title)
	_skip = UiTheme.button(tr("INTRO_SKIP"), 44)
	_skip.anchor_left = 1.0
	_skip.anchor_right = 1.0
	_skip.offset_left = -200
	_skip.offset_right = -24
	_skip.offset_top = 18
	_skip.offset_bottom = 62
	_skip.focus_mode = Control.FOCUS_NONE
	_skip.pressed.connect(finish)
	root.add_child(_skip)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode in [KEY_ESCAPE, KEY_ENTER, KEY_SPACE, KEY_KP_ENTER]:
			get_viewport().set_input_as_handled()
			finish()


func _process(delta: float) -> void:
	if _finished or _shot < 0 or _loading:
		return
	_t += delta
	var s: Array = SHOTS[_shot]
	var dur: float = s[6]
	if not String(s[1]).is_empty() and cam and mission:
		var k := smoothstep(0.0, 1.0, clampf(_t / dur, 0.0, 1.0))
		var base := _room_base(StringName(s[1]))
		var p: Vector3 = base + (s[2] as Vector3).lerp(s[3], k)
		# subtle handheld drift
		p += Vector3(sin(_t * 0.9) * 0.03, sin(_t * 1.3) * 0.02, 0)
		cam.global_position = p
		cam.look_at(base + (s[4] as Vector3))
	_animate_special(String(s[7]), delta)
	# fades in/out at shot edges
	if _t < FADE:
		_fade.color.a = 1.0 - _t / FADE
	elif _t > dur - FADE:
		_fade.color.a = clampf((_t - (dur - FADE)) / FADE, 0.0, 1.0)
	else:
		_fade.color.a = 0.0
	if String(s[1]).is_empty() and String(s[7]) != "title":
		_fade.color.a = 1.0 # black card
	if String(s[7]) == "title":
		_fade.color.a = 1.0
		_title.modulate.a = clampf(_t / 1.2, 0.0, 1.0) * clampf((dur - _t) / 0.8, 0.0, 1.0)
	# QA: --ns-intro-shots=<dir> saves a frame late in every shot
	if not _shot_saved and _t >= dur * 0.72 and CmdArgs.has("intro-shots"):
		_shot_saved = true
		var dir := CmdArgs.value("intro-shots")
		DirAccess.make_dir_recursive_absolute(dir)
		get_viewport().get_texture().get_image().save_png(dir.path_join("intro_%d.png" % _shot))
	if _t >= dur:
		_next_shot()


func _animate_special(kind: String, _delta: float) -> void:
	match kind:
		"flicker":
			if _flicker:
				var n := sin(_t * 21.0) * sin(_t * 6.7)
				_flicker.light_energy = 0.0 if n > 0.55 else 1.6
		"hunter":
			if _hunter and _hunter_light:
				_hunter_light.light_energy = 0.4 + 0.8 * absf(sin(_t * 1.8))
				if _t > 3.6:
					_hunter.rotation.y = lerp_angle(_hunter.rotation.y, PI * 0.5, 0.04) # turns to face us
					_hunter.set_ai_state(&"ALERT")
		"crew":
			for i in _crew.size():
				_crew[i].set_motion(0.0, CharacterVisual.Pose.STAND, false)


func _next_shot() -> void:
	_clear_extras()
	_shot += 1
	_t = 0.0
	_shot_saved = false
	if _shot >= SHOTS.size():
		finish()
		return
	var s: Array = SHOTS[_shot]
	_set_subtitle(tr(String(s[0])) if not String(s[0]).is_empty() else "")
	if not String(s[1]).is_empty() and mission == null:
		_load_facility()
		return
	_setup_shot(s)


func _set_subtitle(text: String) -> void:
	_sub.text = text
	_sub.visible_ratio = 0.0
	var tw := create_tween()
	tw.tween_interval(0.5)
	tw.tween_property(_sub, "visible_ratio", 1.0, maxf(1.2, text.length() * 0.035))


## Builds the facility the first time a 3D shot is needed (the text card covers the hitch).
func _load_facility() -> void:
	_loading = true
	_fade.color.a = 1.0
	await get_tree().process_frame
	await get_tree().process_frame
	Net.start_solo()
	Net.pending_mission = {"mission_id": &"power_restoration", "seed": 1987, "roster": Net.players}
	mission = load(Router.MISSION).instantiate()
	mission.auto_route_results = false
	add_child(mission)
	while is_instance_valid(mission) and not mission.running and not _finished:
		await get_tree().process_frame
	if _finished or not is_instance_valid(mission):
		return
	if mission.hud:
		mission.hud.visible = false
		mission.hud.process_mode = Node.PROCESS_MODE_DISABLED
	for e: EnemyBase in mission.enemies.all():
		e.active = false
		e.visible = false
	var lp := mission.local_player()
	if lp:
		lp.process_mode = Node.PROCESS_MODE_DISABLED
		lp.visible = false
	cam = Camera3D.new()
	cam.fov = 58
	cam.far = 90
	add_child(cam)
	cam.current = true
	_loading = false
	_t = 0.0
	_setup_shot(SHOTS[_shot])


func _room_base(room: StringName) -> Vector3:
	var info: Dictionary = mission.facility.room_info.get(room, {})
	if info.is_empty():
		return Vector3.ZERO
	var aabb: AABB = info.aabb
	var c := aabb.get_center()
	c.y = aabb.position.y
	return c


func _setup_shot(s: Array) -> void:
	if mission == null or String(s[1]).is_empty():
		return
	cam.current = true
	mission.state.set_flag(&"power_main", bool(s[5]))
	var base := _room_base(StringName(s[1]))
	match String(s[7]):
		"flicker":
			_flicker = _omni(base + Vector3(-2, 3.2, 0), Color(0.85, 0.92, 1.0), 1.6, 10.0)
			_omni(base + Vector3(6, 2.8, 0.5), Color(1.0, 0.12, 0.06), 1.4, 9.0)
		"hunter":
			_hunter = load("res://assets/creatures/hunter/hunter_visual.tscn").instantiate()
			_hunter.position = base + Vector3(0.6, 0, 0.2)
			_hunter.rotation.y = -PI * 0.5 # back to the camera
			add_child(_hunter)
			_extras.append(_hunter)
			_hunter.set_ai_state(&"SEARCH")
			_hunter.set_motion(0.0, CharacterVisual.Pose.STAND, false)
			_hunter_light = _omni(base + Vector3(2.0, 2.6, 1.0), Color(1.0, 0.1, 0.05), 1.0, 7.0)
			_omni(base + Vector3(-1.2, 1.9, -0.6), Color(0.5, 0.65, 0.9), 0.9, 5.0)
			get_tree().create_timer(3.4).timeout.connect(func() -> void:
				if not _finished and _hunter:
					Audio.play_2d("hunter_growl_1", -2.0))
		"crew":
			var suits := ["suit_hazard", "suit_night", "suit_medic", "suit_arctic"]
			var helmets := ["helmet_amber", "helmet_cyan", "helmet_red", "helmet_green"]
			for i in 4:
				var v: SkinnedCharacterVisual = load("res://assets/characters/survivor/survivor_visual.tscn").instantiate()
				v.position = base + Vector3(-2.4 + i * 1.6, 0, -0.6 + absf(i - 1.5) * 0.35)
				v.rotation.y = PI + (i - 1.5) * 0.12 # facing the camera
				add_child(v)
				_extras.append(v)
				_crew.append(v)
				var payload := {str(CosmeticData.Slot.SUIT_COLOR): suits[i], str(CosmeticData.Slot.HELMET): helmets[i]}
				v.apply_cosmetics(payload)
				v.set_motion(0.0, CharacterVisual.Pose.STAND, false)
				var torch := SpotLight3D.new()
				torch.spot_range = 16.0
				torch.spot_angle = 20.0
				torch.light_energy = 3.0
				torch.light_color = Color(1.0, 0.95, 0.85)
				add_child(torch)
				_extras.append(torch)
				torch.global_position = v.position + Vector3(-0.15, 1.45, 0.2)
				torch.look_at(torch.global_position + Vector3((i - 1.5) * 0.35, -0.35, 1.0))
			_omni(base + Vector3(0, 2.6, 2.5), Color(0.55, 0.7, 0.9), 1.2, 8.0)


func _omni(pos: Vector3, col: Color, energy: float, rng: float) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.light_color = col
	l.light_energy = energy
	l.omni_range = rng
	add_child(l)
	l.global_position = pos
	_extras.append(l)
	return l


func _clear_extras() -> void:
	for n in _extras:
		if is_instance_valid(n):
			n.queue_free()
	_extras.clear()
	_crew.clear()
	_flicker = null
	_hunter = null
	_hunter_light = null


func finish() -> void:
	if _finished:
		return
	_finished = true
	Profile.data.seen_intro = true
	Profile.save()
	Log.i("intro", "finished at shot %d" % _shot)
	if is_instance_valid(mission):
		mission.queue_free()
	await get_tree().process_frame
	Net.leave(false)
	Router.go_main_menu()
