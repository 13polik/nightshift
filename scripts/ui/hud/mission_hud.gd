class_name MissionHud
extends CanvasLayer
## In-mission HUD. Designed for a phone in landscape: objective top-left, team top-right,
## vitals top-centre, inventory bottom-centre, touch cluster bottom-right, joystick
## bottom-left. Everything reads replicated state; nothing here is authoritative.

const QUICK_CHAT := ["QC_HELP", "QC_FOLLOW", "QC_HUNTER", "QC_FOUND", "QC_WAIT", "QC_GO"]

var mission: MissionController
var root: Control
var touch: TouchControls
var markers: MarkerLayer
var _obj_title: Label
var _obj_hint: Label
var _obj_detail: Label
var _obj_bar: ProgressBar
var _location: Label
var _optional_box: VBoxContainer
var _team_box: VBoxContainer
var _health_bar: ProgressBar
var _stamina_bar: ProgressBar
var _battery_bar: ProgressBar
var _noise_label: Label
var _prompt: Label
var _prompt_bar: ProgressBar
var _slots: Array[InventorySlot] = []
var _banner: Label
var _status: Label
var _vignette: ColorRect
var _vignette_mat: ShaderMaterial
var _desat: ColorRect
var _fade: ColorRect
var _downed_panel: PanelContainer
var _downed_label: Label
var _spectate_label: Label
var _note_panel: PanelContainer
var _note_text: Label
var _pause_layer: Control
var _chat_menu: VBoxContainer
var _fps: Label
var _pings: Array[Dictionary] = []
var _chat_lines: Dictionary = {} # peer -> {text, t}
var _damage_flash := 0.0
var _spectate_index := 0
var _banner_t := 0.0
var _local: PlayerCharacter


func setup(p_mission: MissionController) -> void:
	mission = p_mission
	_build()
	mission.player_spawned.connect(_on_player_spawned)
	mission.ping_received.connect(func(peer: int, pos: Vector3) -> void:
		_pings.append({"pos": pos, "t": 6.0, "label": Net.player_name(peer)}))
	Net.quick_chat_received.connect(func(peer: int, key: String) -> void:
		_chat_lines[peer] = {"text": tr(key), "t": 6.0}
		Events.toast("%s: %s" % [Net.player_name(peer), tr(key)], Events.ToastKind.INFO))
	mission.director.client_updated.connect(_refresh_objective)
	mission.mission_started.connect(func() -> void: _fade_to(0.0, 1.8))
	mission.mission_ended.connect(func(_s: bool) -> void: _fade_to(1.0, 2.2))
	Events.language_changed.connect(func(_l: String) -> void: _refresh_objective())


# --- construction ---------------------------------------------------------------------

func _build() -> void:
	layer = 10
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UiTheme.get_theme()
	add_child(root)

	_vignette = ColorRect.new()
	_vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vignette_mat = ShaderMaterial.new()
	_vignette_mat.shader = load("res://shaders/vignette.gdshader")
	_vignette.material = _vignette_mat
	_desat = ColorRect.new()
	_desat.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_desat.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var dm := ShaderMaterial.new()
	dm.shader = load("res://shaders/desaturate.gdshader")
	_desat.material = dm
	_desat.visible = false
	root.add_child(_desat)
	root.add_child(_vignette)

	markers = MarkerLayer.new()
	root.add_child(markers)

	var margin := UiTheme.safe_area_margin()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(margin)
	var frame := Control.new()
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(frame)

	# objective (top-left)
	var obj := PanelContainer.new()
	obj.add_theme_stylebox_override("panel", UiTheme.box(Color(0.02, 0.025, 0.03, 0.62), Color(0, 0, 0, 0), 0, 8, 14))
	obj.position = Vector2(0, 0)
	obj.custom_minimum_size = Vector2(380, 0)
	obj.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(obj)
	var ov := VBoxContainer.new()
	ov.add_theme_constant_override("separation", 4)
	obj.add_child(ov)
	var tag := UiTheme.label(tr("HUD_OBJECTIVE"), 14, UiTheme.ACCENT)
	ov.add_child(tag)
	_obj_title = UiTheme.label("", 24)
	_obj_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_obj_title.custom_minimum_size.x = 360
	ov.add_child(_obj_title)
	_obj_hint = UiTheme.label("", 16, UiTheme.TEXT_DIM)
	_obj_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_obj_hint.custom_minimum_size.x = 360
	ov.add_child(_obj_hint)
	_obj_bar = ProgressBar.new()
	_obj_bar.custom_minimum_size = Vector2(360, 8)
	_obj_bar.show_percentage = false
	_obj_bar.max_value = 1.0
	ov.add_child(_obj_bar)
	_obj_detail = UiTheme.label("", 16, UiTheme.ACCENT_2)
	_obj_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_obj_detail.custom_minimum_size.x = 360
	ov.add_child(_obj_detail)
	_location = UiTheme.label("", 14, UiTheme.TEXT_DIM)
	ov.add_child(_location)
	_optional_box = VBoxContainer.new()
	_optional_box.add_theme_constant_override("separation", 2)
	ov.add_child(_optional_box)

	# vitals (top-centre)
	var vit := VBoxContainer.new()
	vit.set_anchors_preset(Control.PRESET_CENTER_TOP)
	vit.position = Vector2(-150, 0)
	vit.custom_minimum_size = Vector2(300, 0)
	vit.add_theme_constant_override("separation", 4)
	vit.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(vit)
	_health_bar = _bar(vit, UiTheme.DANGER, 14)
	_stamina_bar = _bar(vit, Color(0.85, 0.85, 0.8), 6)
	var batt_row := HBoxContainer.new()
	batt_row.add_theme_constant_override("separation", 6)
	vit.add_child(batt_row)
	batt_row.add_child(UiTheme.label("*", 14, Color(1, 0.95, 0.7)))
	_battery_bar = _bar(batt_row, Color(1, 0.92, 0.6), 6)
	_battery_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_noise_label = UiTheme.label("", 13, UiTheme.TEXT_DIM)
	batt_row.add_child(_noise_label)
	_banner = UiTheme.label("", 26, UiTheme.ACCENT)
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.custom_minimum_size.x = 300
	vit.add_child(_banner)
	_status = UiTheme.label("", 20, UiTheme.TEXT)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.custom_minimum_size.x = 300
	vit.add_child(_status)

	# team + pause (top-right)
	var right := VBoxContainer.new()
	right.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	right.position = Vector2(-260, 0)
	right.custom_minimum_size = Vector2(260, 0)
	right.alignment = BoxContainer.ALIGNMENT_BEGIN
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(right)
	var top_buttons := HBoxContainer.new()
	top_buttons.alignment = BoxContainer.ALIGNMENT_END
	right.add_child(top_buttons)
	var chat_btn := UiTheme.button("...", 56)
	chat_btn.custom_minimum_size.x = 64
	chat_btn.pressed.connect(_toggle_chat)
	top_buttons.add_child(chat_btn)
	var pause_btn := UiTheme.button("II", 56)
	pause_btn.custom_minimum_size.x = 64
	pause_btn.pressed.connect(open_pause)
	top_buttons.add_child(pause_btn)
	_chat_menu = VBoxContainer.new()
	_chat_menu.visible = false
	right.add_child(_chat_menu)
	for key in QUICK_CHAT:
		var b := UiTheme.button(tr(key), 48)
		b.pressed.connect(func() -> void:
			Net.send_quick_chat(key)
			_chat_menu.visible = false)
		_chat_menu.add_child(b)
	_team_box = VBoxContainer.new()
	_team_box.add_theme_constant_override("separation", 4)
	right.add_child(_team_box)
	_fps = UiTheme.label("", 14, UiTheme.TEXT_DIM)
	right.add_child(_fps)

	# prompt (bottom-centre) + inventory
	var bottom := VBoxContainer.new()
	bottom.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	bottom.position = Vector2(-220, -150)
	bottom.custom_minimum_size = Vector2(440, 0)
	bottom.alignment = BoxContainer.ALIGNMENT_END
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(bottom)
	_prompt = UiTheme.label("", 22)
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_prompt.add_theme_constant_override("outline_size", 6)
	bottom.add_child(_prompt)
	_prompt_bar = ProgressBar.new()
	_prompt_bar.custom_minimum_size = Vector2(440, 8)
	_prompt_bar.max_value = 1.0
	_prompt_bar.show_percentage = false
	_prompt_bar.visible = false
	bottom.add_child(_prompt_bar)
	var inv_row := HBoxContainer.new()
	inv_row.alignment = BoxContainer.ALIGNMENT_CENTER
	inv_row.add_theme_constant_override("separation", 8)
	bottom.add_child(inv_row)
	for i in 4:
		var s := InventorySlot.new()
		s.index = i
		s.tapped.connect(_on_slot_tapped)
		s.long_pressed.connect(_on_slot_long)
		inv_row.add_child(s)
		_slots.append(s)

	# downed / spectate / note overlays
	_downed_panel = PanelContainer.new()
	_downed_panel.set_anchors_preset(Control.PRESET_CENTER)
	_downed_panel.position = Vector2(-220, -60)
	_downed_panel.custom_minimum_size = Vector2(440, 0)
	_downed_panel.visible = false
	_downed_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(_downed_panel)
	_downed_label = UiTheme.label("", 24, UiTheme.DANGER)
	_downed_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_downed_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_downed_panel.add_child(_downed_label)
	_spectate_label = UiTheme.label("", 20, UiTheme.TEXT_DIM)
	_spectate_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_spectate_label.position = Vector2(-300, -60)
	_spectate_label.custom_minimum_size.x = 600
	_spectate_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_spectate_label.visible = false
	frame.add_child(_spectate_label)
	_note_panel = PanelContainer.new()
	_note_panel.set_anchors_preset(Control.PRESET_CENTER)
	_note_panel.position = Vector2(-300, -180)
	_note_panel.custom_minimum_size = Vector2(600, 360)
	_note_panel.visible = false
	frame.add_child(_note_panel)
	var nv := VBoxContainer.new()
	_note_panel.add_child(nv)
	_note_text = UiTheme.label("", 20)
	_note_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_note_text.custom_minimum_size = Vector2(560, 260)
	nv.add_child(_note_text)
	var close_note := UiTheme.button(tr("UI_CLOSE"), 56)
	close_note.pressed.connect(func() -> void: _note_panel.visible = false)
	nv.add_child(close_note)

	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 1)
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_fade)

	_pause_layer = Control.new()
	_pause_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pause_layer.visible = false
	root.add_child(_pause_layer)

	if Settings.touch_ui_enabled():
		touch = TouchControls.new()
		root.add_child(touch)
		root.move_child(touch, 2)
		touch.ui_blockers = [obj, chat_btn, pause_btn, _chat_menu, inv_row, _note_panel, _pause_layer]
	_refresh_objective()


func _bar(parent: Control, color: Color, h: int) -> ProgressBar:
	var b := ProgressBar.new()
	b.custom_minimum_size = Vector2(300, h)
	b.max_value = 1.0
	b.value = 1.0
	b.show_percentage = false
	var fill := UiTheme.box(color, Color(0, 0, 0, 0), 0, 3, 0)
	b.add_theme_stylebox_override("fill", fill)
	parent.add_child(b)
	return b


func _on_player_spawned(p: PlayerCharacter) -> void:
	if not p.is_local:
		return
	_local = p
	markers.camera = p.camera.camera if p.camera else null
	p.interactor.denied.connect(func(reason: String) -> void: Events.toast(reason, Events.ToastKind.WARNING))
	p.interactor.hold_progress.connect(func(v: float) -> void:
		_prompt_bar.visible = v > 0.0
		_prompt_bar.value = v
		if touch:
			touch.buttons[&"interact"].progress = v
			touch.buttons[&"interact"].queue_redraw())
	p.interactor.inspect_requested.connect(func(note: Interactable) -> void:
		_note_text.text = tr((note as NoteInteractable).text_key)
		_note_panel.visible = true)
	if not Settings.touch_ui_enabled() and not Settings.is_mobile() and DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


# --- per-frame ------------------------------------------------------------------------

func _process(delta: float) -> void:
	if mission == null:
		return
	_local = mission.local_player()
	_update_vitals(delta)
	_update_prompt()
	_update_inventory()
	_update_team()
	_update_status()
	_update_markers(delta)
	_banner_t -= delta
	if _banner_t <= 0.0:
		_banner.text = ""
	_fps.visible = bool(Settings.get_value("graphics", "show_fps"))
	if _fps.visible:
		_fps.text = "%d FPS" % Engine.get_frames_per_second()
	if int(Engine.get_process_frames()) % 15 == 0:
		_refresh_location()


func _update_vitals(delta: float) -> void:
	if _local == null:
		return
	var h := _local.health
	_health_bar.value = h.health / maxf(h.max_health, 1.0)
	_stamina_bar.value = _local.stamina / maxf(_local.stats.stamina_max, 1.0)
	_battery_bar.value = _local.flashlight.battery / maxf(_local.flashlight.battery_max, 1.0)
	var loud := NoiseSystem.movement_loudness(_local)
	_noise_label.text = tr("HUD_NOISE_%s" % ("LOUD" if loud >= _local.stats.noise_sprint else ("QUIET" if loud <= _local.stats.noise_crouch else "NORMAL")))
	_noise_label.add_theme_color_override("font_color", UiTheme.DANGER if loud >= _local.stats.noise_sprint else UiTheme.TEXT_DIM)
	_damage_flash = maxf(0.0, _damage_flash - delta * 1.5)
	var low := clampf(1.0 - h.health / maxf(h.max_health, 1.0), 0.0, 1.0)
	var downed := _local.is_downed()
	_vignette_mat.set_shader_parameter("intensity", clampf(low * 0.6 + _damage_flash + (0.8 if downed else 0.0), 0.0, 1.2))
	_desat.visible = downed
	_downed_panel.visible = downed
	if downed:
		var rv := h.revive_progress
		_downed_label.text = tr("HUD_DOWNED").format({"time": int(h.bleed_left)}) + ("\n" + tr("HUD_BEING_REVIVED") if rv > 0.0 else "")
	var spectating := _local.is_dead() or _local.is_extracted()
	_spectate_label.visible = spectating
	if spectating:
		_spectate()
	if touch:
		touch.visible = not spectating and not _pause_layer.visible
		var b: Dictionary = touch.buttons
		b[&"crouch"].toggled_on = _local.crouched
		b[&"sprint"].toggled_on = _local.sprinting
		b[&"flashlight"].toggled_on = _local.flashlight.on
		for k in b:
			b[k].queue_redraw()


func _update_prompt() -> void:
	if _local == null or _local.interactor == null:
		_prompt.text = ""
		return
	var it := _local.interactor
	_prompt.text = it.prompt_text()
	var usable := it.can_use_focus()
	_prompt.add_theme_color_override("font_color", UiTheme.TEXT if usable else UiTheme.TEXT_DIM)
	if touch:
		touch.buttons[&"interact"].dimmed = it.focus == null


func _update_inventory() -> void:
	if _local == null:
		return
	var inv := _local.inventory
	for i in _slots.size():
		var s := _slots[i]
		s.visible = i < inv.slots.size()
		if not s.visible:
			continue
		var data := inv.slot_item(i)
		s.set_content(data, int(inv.slots[i].n), i == inv.selected, inv.use_progress if inv.using_slot == i else 0.0)


func _on_slot_tapped(i: int) -> void:
	if _local == null:
		return
	if _local.inventory.selected == i:
		_local.inventory.request_use(i)
	else:
		_local.inventory.request_select(i)
	Audio.play_ui("ui_click", -8.0)


func _on_slot_long(i: int) -> void:
	if _local:
		_local.inventory.request_drop(i)
		Audio.play_ui("ui_back", -6.0)


func _update_team() -> void:
	var players := mission.get_players()
	while _team_box.get_child_count() < players.size():
		var l := UiTheme.label("", 16)
		_team_box.add_child(l)
	for i in _team_box.get_child_count():
		var l: Label = _team_box.get_child(i)
		if i >= players.size():
			l.visible = false
			continue
		var p: PlayerCharacter = players[i]
		l.visible = true
		var st := ""
		var col := UiTheme.TEXT
		match p.health.state:
			PlayerHealth.State.DOWNED:
				st = tr("STATE_DOWNED") + " %ds" % int(p.health.bleed_left)
				col = UiTheme.DANGER
			PlayerHealth.State.DEAD:
				st = tr("STATE_DEAD")
				col = UiTheme.TEXT_DIM
			PlayerHealth.State.EXTRACTED:
				st = tr("STATE_EXTRACTED")
				col = UiTheme.SUCCESS
			_:
				st = "%d%%" % int(p.health.health / p.health.max_health * 100.0)
		var dist := ""
		if _local and p != _local:
			dist = "  %dm" % int(_local.global_position.distance_to(p.global_position))
		var chat := ""
		if _chat_lines.has(p.peer_id):
			chat = "\n  \"%s\"" % _chat_lines[p.peer_id].text
		l.text = "%s%s  %s%s%s" % ["> " if p == _local else "", p.display_name(), st, dist, chat]
		l.add_theme_color_override("font_color", col)


func _update_status() -> void:
	var st: MissionState = mission.state
	var parts: PackedStringArray = []
	if st.get_flag(&"extraction_open", false):
		parts.append(tr("HUD_EVAC_DEPARTS").format({"time": _fmt_time(float(st.get_flag(&"departure_left", 0.0)))}))
	elif st.get_flag(&"evac", false):
		parts.append(tr("HUD_EVAC_INBOUND"))
	if st.get_flag(&"blackout", false):
		parts.append(tr("HUD_BLACKOUT"))
	if st.get_flag(&"lockdown", false):
		parts.append(tr("HUD_LOCKDOWN"))
	if st.get_flag(&"alarm", false) and not st.get_flag(&"evac", false):
		parts.append(tr("HUD_ALARM"))
	_status.text = "  |  ".join(parts)
	_status.add_theme_color_override("font_color", UiTheme.DANGER if st.get_flag(&"alarm", false) else UiTheme.ACCENT_2)


func _update_markers(delta: float) -> void:
	if _local and _local.camera:
		markers.camera = _local.camera.camera
	var list: Array[Dictionary] = []
	for pos in objective_marker_positions():
		list.append({"pos": pos, "color": UiTheme.ACCENT, "label": ""})
	for p: PlayerCharacter in mission.get_players():
		if p == _local or p.is_extracted():
			continue
		var col := UiTheme.DANGER if p.is_downed() else UiTheme.ACCENT_2
		if p.is_downed() or (_local and _local.global_position.distance_to(p.global_position) > 8.0):
			list.append({"pos": p.global_position + Vector3.UP * 2.0, "color": col, "label": p.display_name()})
	for i in range(_pings.size() - 1, -1, -1):
		_pings[i].t = float(_pings[i].t) - delta
		if float(_pings[i].t) <= 0.0:
			_pings.remove_at(i)
		else:
			list.append({"pos": _pings[i].pos, "color": Color(1, 1, 1), "label": "! " + str(_pings[i].label)})
	for k in _chat_lines.keys():
		_chat_lines[k].t = float(_chat_lines[k].t) - delta
		if float(_chat_lines[k].t) <= 0.0:
			_chat_lines.erase(k)
	markers.markers = list


## World positions the current objective points at (client side).
func objective_marker_positions() -> Array[Vector3]:
	var out: Array[Vector3] = []
	var d := mission.director
	var def := d.current_def()
	if def == null or mission.setup.is_empty():
		return out
	var rt := d.runtime_for(d.client_index)
	match def.type:
		ObjectiveData.Type.INTERACT, ObjectiveData.Type.DELIVER:
			for id in rt.get("targets", []):
				var i := mission.interactions.get_interactable(int(id)) as ObjectiveDevice
				if i and not i.done:
					out.append(i.focus_point() + Vector3.UP * 0.6)
		ObjectiveData.Type.REACH_ZONE:
			var best := Vector3.INF
			for rid in rt.get("rooms", []):
				var c: Vector3 = (mission.facility.room_info[StringName(rid)].aabb as AABB).get_center()
				if _local == null or best == Vector3.INF or c.distance_to(_local.global_position) < best.distance_to(_local.global_position):
					best = c
			if best != Vector3.INF:
				out.append(best)
		ObjectiveData.Type.COLLECT:
			for rid in d.client_detail.get("hint_rooms", []):
				out.append((mission.facility.room_info[StringName(rid)].aabb as AABB).get_center())
			for c in mission.pickups.get_children():
				if c is ItemPickup and rt.get("items", {}).has(String(c.item_id)) and _local and c.global_position.distance_to(_local.global_position) < 30.0:
					out.append(c.global_position + Vector3.UP * 0.5)
		ObjectiveData.Type.EXTRACT, ObjectiveData.Type.SURVIVE:
			var room := StringName(str(mission.state.get_flag(&"extraction_room", "")))
			if room != &"" and mission.facility.room_info.has(room):
				out.append((mission.facility.room_info[room].aabb as AABB).get_center())
	return out


func _refresh_objective() -> void:
	if _obj_title == null or mission == null:
		return
	var d := mission.director
	var def := d.current_def()
	if def == null:
		_obj_title.text = tr("HUD_WAITING") if d.client_index < 0 else tr("HUD_ALL_DONE")
		_obj_hint.text = ""
		_obj_detail.text = ""
		_obj_bar.value = 0.0
		return
	_obj_title.text = tr(def.title_key)
	_obj_hint.text = tr(def.hint_key) if Settings.get_value("gameplay", "show_hints") else ""
	_obj_bar.value = d.client_progress
	_obj_detail.text = _detail_text(def, d.client_detail)
	for c in _optional_box.get_children():
		c.queue_free()
	for o: Dictionary in d.client_optional:
		var od: ObjectiveData = mission.data.optional_objectives[int(o.i)]
		var l := UiTheme.label(("[x] " if o.d else "[ ] ") + tr("HUD_OPTIONAL") + ": " + tr(od.title_key), 14, UiTheme.SUCCESS if o.d else UiTheme.TEXT_DIM)
		_optional_box.add_child(l)


func _detail_text(def: ObjectiveData, detail: Dictionary) -> String:
	match def.type:
		ObjectiveData.Type.COLLECT:
			var parts: PackedStringArray = []
			var need: Dictionary = detail.get("need", {})
			var have: Dictionary = detail.get("have", {})
			for item: String in need:
				var data := Content.item(StringName(item))
				parts.append("%s %d/%d" % [tr(data.name_key) if data else item, mini(int(have.get(item, 0)), int(need[item])), int(need[item])])
			var s := ", ".join(parts)
			var rooms: Array = detail.get("hint_rooms", [])
			if not rooms.is_empty():
				var names: PackedStringArray = []
				for r in rooms:
					names.append(tr(mission.facility.room_name_key(StringName(r))))
				s += "\n" + tr("HUD_LOCATED_IN").format({"rooms": ", ".join(names)})
			return s
		ObjectiveData.Type.SURVIVE:
			return tr("HUD_TIME_LEFT").format({"time": _fmt_time(float(detail.get("left", 0.0)))})
		ObjectiveData.Type.EXTRACT:
			return tr("HUD_EXTRACTED_COUNT").format({"n": int(detail.get("extracted", 0))})
		ObjectiveData.Type.REACH_ZONE:
			if def.require_all_players:
				return "%d/%d" % [int(detail.get("inside", 0)), int(detail.get("total", 0))]
	return ""


func _refresh_location() -> void:
	if _local == null:
		return
	var room := mission.facility.room_at_position(_local.global_position)
	_location.text = tr("HUD_LOCATION").format({"room": tr(mission.facility.room_name_key(room))}) if room != &"" else ""


func _spectate() -> void:
	var alive: Array = mission.get_players().filter(func(p: PlayerCharacter) -> bool: return p.is_active())
	if alive.is_empty() or _local.camera == null:
		_spectate_label.text = tr("HUD_SPECTATING_NONE")
		return
	_spectate_index = _spectate_index % alive.size()
	var t: PlayerCharacter = alive[_spectate_index]
	if _local.camera.target != t:
		_local.camera.set_target(t)
	_spectate_label.text = tr("HUD_SPECTATING").format({"name": t.display_name()}) + ("  -  " + tr("STATE_EXTRACTED") if _local.is_extracted() else "")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"pause"):
		if _pause_layer.visible:
			close_pause()
		else:
			open_pause()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed and not Settings.touch_ui_enabled() and not _pause_layer.visible and DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		if _local and (_local.is_dead() or _local.is_extracted()):
			_spectate_index += 1
	elif event is InputEventScreenTouch and event.pressed and _local and (_local.is_dead() or _local.is_extracted()):
		_spectate_index += 1


# --- callbacks from the mission -------------------------------------------------------

func on_player_damaged(p: PlayerCharacter, amount: float, _source: Vector3) -> void:
	if p == mission.local_player():
		_damage_flash = clampf(amount / 50.0, 0.3, 0.9)


func on_player_state_changed(p: PlayerCharacter, new_state: int) -> void:
	if p.is_local:
		return
	match new_state:
		PlayerHealth.State.DOWNED:
			Events.toast(tr("TOAST_PLAYER_DOWNED").format({"name": p.display_name()}), Events.ToastKind.DANGER)
		PlayerHealth.State.DEAD:
			Events.toast(tr("TOAST_PLAYER_DIED").format({"name": p.display_name()}), Events.ToastKind.DANGER)
		PlayerHealth.State.EXTRACTED:
			Events.toast(tr("TOAST_PLAYER_EXTRACTED").format({"name": p.display_name()}), Events.ToastKind.SUCCESS)


func show_event_banner(key: String, duration: float) -> void:
	_banner.text = tr(key)
	_banner_t = clampf(duration, 4.0, 8.0)


func _fade_to(alpha: float, seconds: float) -> void:
	if _fade == null:
		return
	var tw := _fade.create_tween()
	tw.tween_property(_fade, "color:a", alpha, seconds).set_trans(Tween.TRANS_SINE)


func _toggle_chat() -> void:
	_chat_menu.visible = not _chat_menu.visible


# --- pause ----------------------------------------------------------------------------

func open_pause() -> void:
	if _pause_layer.visible:
		return
	_pause_layer.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	GameInput.enabled = false
	GameInput.reset()
	if touch:
		touch.release_all()
	for c in _pause_layer.get_children():
		c.queue_free()
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.65)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pause_layer.add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pause_layer.add_child(center)
	var v := VBoxContainer.new()
	v.custom_minimum_size = Vector2(420, 0)
	v.add_theme_constant_override("separation", 14)
	center.add_child(v)
	v.add_child(UiTheme.label(tr("PAUSE_TITLE"), 40, UiTheme.ACCENT))
	if not Net.is_solo:
		v.add_child(UiTheme.label(tr("PAUSE_ONLINE_NOTE"), 16, UiTheme.TEXT_DIM))
	var resume := UiTheme.primary_button(tr("PAUSE_RESUME"))
	resume.pressed.connect(close_pause)
	v.add_child(resume)
	var settings := UiTheme.button(tr("MENU_SETTINGS"))
	settings.pressed.connect(func() -> void:
		for c in center.get_children():
			c.visible = false
		var sp := SettingsPanel.new()
		center.add_child(sp)
		sp.closed.connect(func() -> void:
			sp.queue_free()
			for c in center.get_children():
				c.visible = true))
	v.add_child(settings)
	var leave := UiTheme.button(tr("PAUSE_LEAVE"))
	leave.pressed.connect(func() -> void:
		Router.confirm("PAUSE_LEAVE", tr("PAUSE_LEAVE_CONFIRM"), func() -> void:
			close_pause()
			mission.leave_mission()))
	v.add_child(leave)
	resume.grab_focus()


func close_pause() -> void:
	_pause_layer.visible = false
	GameInput.enabled = true
	if not Settings.touch_ui_enabled() and not Settings.is_mobile() and DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


static func _fmt_time(sec: float) -> String:
	var s := maxi(0, int(sec))
	return "%d:%02d" % [s / 60, s % 60]
