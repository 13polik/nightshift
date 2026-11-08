extends UiScreen
## Lobby: 4 player slots (name, level, ready, ping, host), mission selection (host),
## ready toggle, start (host, when all ready), invite code + copy, quick status, leave.

var _slots_box: HBoxContainer
var _start: Button
var _ready_btn: Button
var _mission_box: VBoxContainer
var _code_label: Label


func _ready() -> void:
	super._ready()
	Net.lobby_updated.connect(_refresh)
	Net.quick_chat_received.connect(func(peer: int, key: String) -> void:
		Events.toast("%s: %s" % [Net.player_name(peer), tr(key)]))
	if Net.state == Net.State.OFFLINE:
		Router.go_main_menu.call_deferred()


func build() -> void:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 16)
	content.add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	var leave := UiTheme.button(tr("LOBBY_LEAVE"), 56)
	leave.custom_minimum_size.x = 160
	leave.pressed.connect(go_back)
	head.add_child(leave)
	var t := UiTheme.label(tr("LOBBY_SOLO") if Net.is_solo else tr("LOBBY_TITLE"), 34, UiTheme.ACCENT)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	_code_label = UiTheme.label("", 20, UiTheme.ACCENT_2)
	head.add_child(_code_label)
	if Net.is_server() and not Net.is_solo:
		var copy := UiTheme.button(tr("LOBBY_COPY_CODE"), 56)
		copy.pressed.connect(func() -> void:
			DisplayServer.clipboard_set(Net.join_code())
			Events.toast("TOAST_CODE_COPIED", Events.ToastKind.SUCCESS))
		head.add_child(copy)
	_slots_box = HBoxContainer.new()
	_slots_box.add_theme_constant_override("separation", 12)
	v.add_child(_slots_box)
	var lower := HBoxContainer.new()
	lower.add_theme_constant_override("separation", 20)
	lower.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(lower)
	var mission_panel := PanelContainer.new()
	mission_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lower.add_child(mission_panel)
	var mission_scroll := ScrollContainer.new()
	mission_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	mission_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mission_panel.add_child(mission_scroll)
	_mission_box = VBoxContainer.new()
	_mission_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mission_scroll.add_child(_mission_box)
	var actions := VBoxContainer.new()
	actions.custom_minimum_size.x = 340
	actions.alignment = BoxContainer.ALIGNMENT_END
	actions.add_theme_constant_override("separation", 10)
	lower.add_child(actions)
	if not Net.is_solo:
		var chat := HBoxContainer.new()
		actions.add_child(chat)
		for key in ["QC_READY_UP", "QC_WAIT", "QC_GO"]:
			var b := UiTheme.button(tr(key), 52)
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			b.pressed.connect(func() -> void: Net.send_quick_chat(key))
			chat.add_child(b)
	_ready_btn = UiTheme.button(tr("LOBBY_READY"), 72)
	_ready_btn.toggle_mode = true
	_ready_btn.toggled.connect(func(on: bool) -> void: Net.set_ready(on))
	_ready_btn.visible = not Net.is_server()
	actions.add_child(_ready_btn)
	_start = UiTheme.primary_button(tr("LOBBY_START"), 80)
	_start.pressed.connect(func() -> void:
		if not Net.start_mission():
			Events.toast("LOBBY_NOT_READY", Events.ToastKind.WARNING))
	_start.visible = Net.is_server()
	actions.add_child(_start)
	_refresh()


func _refresh() -> void:
	if _slots_box == null or not is_instance_valid(_slots_box):
		return
	if Net.state == Net.State.OFFLINE:
		return
	_code_label.text = (tr("LOBBY_CODE") + " " + Net.join_code()) if Net.is_server() and not Net.is_solo else ""
	for c in _slots_box.get_children():
		c.queue_free()
	var by_slot := {}
	for id: int in Net.players:
		by_slot[int(Net.players[id].slot)] = id
	var count := 1 if Net.is_solo else Net.MAX_PLAYERS
	for s in count:
		var p := PanelContainer.new()
		p.custom_minimum_size = Vector2(250, 190)
		_slots_box.add_child(p)
		var v := VBoxContainer.new()
		p.add_child(v)
		if by_slot.has(s):
			var id: int = by_slot[s]
			var info: Dictionary = Net.players[id]
			var me := id == Net.local_id()
			v.add_child(UiTheme.label(("[H] " if id == 1 else "") + str(info.name) + (" " + tr("LOBBY_YOU") if me else ""), 22, UiTheme.ACCENT if me else UiTheme.TEXT))
			v.add_child(UiTheme.label(tr("PROFILE_LEVEL").format({"level": int(info.level)}), 16, UiTheme.TEXT_DIM))
			var kit := Content.loadout(StringName(str(info.get("loadout", ""))))
			if kit:
				v.add_child(UiTheme.label(tr(kit.name_key), 15, UiTheme.TEXT_DIM))
			var ready := bool(info.ready)
			v.add_child(UiTheme.label(tr("LOBBY_READY_STATE") if ready else tr("LOBBY_NOT_READY_STATE"), 18, UiTheme.SUCCESS if ready else UiTheme.ACCENT))
			if not Net.is_solo and id != 1:
				v.add_child(UiTheme.label("%d ms" % int(info.get("ping", 0)), 14, UiTheme.TEXT_DIM))
			if Net.is_server() and id != 1:
				var kick := UiTheme.button(tr("LOBBY_KICK"), 44)
				kick.pressed.connect(func() -> void: Net.kick(id))
				v.add_child(kick)
		else:
			v.add_child(UiTheme.label(tr("LOBBY_EMPTY_SLOT"), 18, UiTheme.TEXT_DIM))
			v.add_child(UiTheme.label(tr("LOBBY_INVITE_HINT"), 14, UiTheme.TEXT_DIM))
	_build_missions()
	if _start:
		_start.disabled = not Net.can_start()
	if _ready_btn and Net.players.has(Net.local_id()):
		_ready_btn.set_pressed_no_signal(bool(Net.players[Net.local_id()].ready))
		_ready_btn.text = tr("LOBBY_UNREADY") if _ready_btn.button_pressed else tr("LOBBY_READY")


func _build_missions() -> void:
	for c in _mission_box.get_children():
		c.queue_free()
	_mission_box.add_child(UiTheme.label(tr("LOBBY_MISSION"), 20, UiTheme.ACCENT_2))
	for m in Content.sorted_missions():
		var selected := m.id == Net.selected_mission
		var row := VBoxContainer.new()
		_mission_box.add_child(row)
		var locked := Profile.level() < m.unlock_level
		var label := ("> " if selected else "") + tr(m.name_key)
		if locked:
			label += "   " + tr("LOBBY_MISSION_LOCKED").format({"level": m.unlock_level})
		var b := UiTheme.button(label, 52)
		b.disabled = not Net.is_server() or locked
		b.pressed.connect(func() -> void: Net.set_selected_mission(m.id))
		row.add_child(b)
		if selected:
			var d := UiTheme.label("%s  |  %s" % [tr(m.location_key), tr("LOBBY_DURATION").format({"min": int(m.target_duration_minutes)})], 15, UiTheme.TEXT_DIM)
			row.add_child(d)
			var desc := UiTheme.label(tr(m.description_key), 15, UiTheme.TEXT_DIM)
			desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			desc.custom_minimum_size.x = 400
			row.add_child(desc)


func go_back() -> void:
	Router.confirm("LOBBY_LEAVE", tr("LOBBY_LEAVE_CONFIRM"), func() -> void:
		Net.leave()
		Router.go_main_menu())
