extends UiScreen
## Main menu with pages: home, play, customize, loadout ("inventory"), settings, profile.

enum Page { HOME, PLAY, CUSTOMIZE, LOADOUT, SETTINGS, PROFILE }

var page: Page = Page.HOME
var _lan_list: VBoxContainer
var _backdrop: MenuBackdrop
var _shade: TextureRect


func _ready() -> void:
	super._ready()
	# live 3D scene behind the menu + a left-side gradient so text stays readable
	if DisplayServer.get_name() != "headless":
		_backdrop = MenuBackdrop.new()
		add_child(_backdrop)
		move_child(_backdrop, 1)
		_shade = TextureRect.new()
		var g := Gradient.new()
		g.set_color(0, Color(0.0, 0.0, 0.0, 0.92))
		g.set_color(1, Color(0.0, 0.0, 0.0, 0.05))
		var gt := GradientTexture2D.new()
		gt.gradient = g
		gt.fill_from = Vector2(0, 0)
		gt.fill_to = Vector2(1, 0)
		_shade.texture = gt
		_shade.stretch_mode = TextureRect.STRETCH_SCALE
		_shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_shade)
		move_child(_shade, 2)
	if Router.after_intro_page == "play":
		Router.after_intro_page = ""
		show_page.call_deferred(Page.PLAY)


func build() -> void:
	match page:
		Page.HOME: _home()
		Page.PLAY: _play()
		Page.CUSTOMIZE: content.add_child(_wrap(CustomizePanel.new()))
		Page.LOADOUT: content.add_child(_wrap(LoadoutPanel.new()))
		Page.SETTINGS:
			var sp := SettingsPanel.new()
			sp.closed.connect(func() -> void: show_page(Page.HOME))
			var c := CenterContainer.new()
			c.add_child(sp)
			content.add_child(c)
		Page.PROFILE: content.add_child(_wrap(ProfilePanel.new()))


func show_page(p: Page) -> void:
	page = p
	# sub-pages need a calmer background behind dense UI
	if _backdrop:
		_backdrop.modulate = Color(1, 1, 1) if p == Page.HOME else Color(0.35, 0.35, 0.35)
	if p != Page.PLAY:
		Net.discovery.stop()
	rebuild()


func go_back() -> void:
	if page != Page.HOME:
		Audio.play_ui("ui_back")
		show_page(Page.HOME)


func _wrap(panel: Control) -> Control:
	var v := VBoxContainer.new()
	var back := UiTheme.button(tr("UI_BACK"), 56)
	back.custom_minimum_size.x = 160
	back.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	back.pressed.connect(go_back)
	v.add_child(back)
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(panel)
	return v


func _home() -> void:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 40)
	content.add_child(h)
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 420
	left.alignment = BoxContainer.ALIGNMENT_CENTER
	left.add_theme_constant_override("separation", 12)
	h.add_child(left)
	left.add_child(title("NIGHT SHIFT"))
	left.add_child(UiTheme.label(tr("MENU_TAGLINE"), 18, UiTheme.TEXT_DIM))
	var spacer := Control.new()
	spacer.custom_minimum_size.y = 20
	left.add_child(spacer)
	var play := UiTheme.primary_button(tr("MENU_PLAY"), 80)
	play.pressed.connect(func() -> void:
		# the story intro plays once, right before the very first game
		if not bool(Profile.data.get("seen_intro", false)):
			Router.after_intro_page = "play"
			Router.go_intro()
		else:
			show_page(Page.PLAY))
	left.add_child(play)
	for entry in [["MENU_CUSTOMIZE", Page.CUSTOMIZE], ["MENU_INVENTORY", Page.LOADOUT], ["MENU_SETTINGS", Page.SETTINGS], ["MENU_PROFILE", Page.PROFILE]]:
		var b := UiTheme.button(tr(entry[0]))
		var target: Page = entry[1]
		b.pressed.connect(func() -> void: show_page(target))
		left.add_child(b)
	var intro := UiTheme.button(tr("MENU_INTRO"))
	intro.pressed.connect(Router.go_intro)
	left.add_child(intro)
	if OS.get_name() != "iOS":
		var exit := UiTheme.button(tr("MENU_EXIT"))
		exit.pressed.connect(func() -> void:
			Router.confirm("MENU_EXIT", tr("MENU_EXIT_CONFIRM"), func() -> void: get_tree().quit()))
		left.add_child(exit)
	play.grab_focus.call_deferred()
	# profile summary card
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.alignment = BoxContainer.ALIGNMENT_END
	h.add_child(right)
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_SHRINK_END
	right.add_child(card)
	var cv := VBoxContainer.new()
	card.add_child(cv)
	var li := Profile.level_info()
	cv.add_child(UiTheme.label(Profile.display_name(), 26, UiTheme.ACCENT))
	cv.add_child(UiTheme.label(tr("PROFILE_LEVEL").format({"level": li.level}), 18))
	var xp := ProgressBar.new()
	xp.custom_minimum_size = Vector2(280, 10)
	xp.max_value = float(li.needed)
	xp.value = float(li.into_level)
	xp.show_percentage = false
	cv.add_child(xp)
	cv.add_child(UiTheme.label(tr("PROFILE_CURRENCY").format({"amount": Profile.currency()}), 18, UiTheme.TEXT_DIM))
	if SaveManager.last_recovery.has("profile"):
		cv.add_child(UiTheme.label(tr("SAVE_RECOVERED"), 14, UiTheme.ACCENT))
	right.add_child(UiTheme.label("v%s" % ProjectSettings.get_setting("application/config/version"), 13, UiTheme.TEXT_DIM))


func _play() -> void:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 16)
	content.add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	var back := UiTheme.button(tr("UI_BACK"), 56)
	back.custom_minimum_size.x = 160
	back.pressed.connect(go_back)
	head.add_child(back)
	head.add_child(UiTheme.label(tr("MENU_PLAY"), 34, UiTheme.ACCENT))
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 24)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(cols)
	# left: start options
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 420
	left.add_theme_constant_override("separation", 12)
	cols.add_child(left)
	var solo := UiTheme.primary_button(tr("PLAY_SOLO"))
	solo.pressed.connect(func() -> void:
		Net.start_solo()
		Router.go_lobby())
	left.add_child(solo)
	var online := UiTheme.button(tr("PLAY_HOST_ONLINE"), 72)
	online.pressed.connect(func() -> void:
		if Net.host_online():
			_await_online_host())
	left.add_child(online)
	var host := UiTheme.button(tr("PLAY_HOST"), 60)
	host.pressed.connect(func() -> void:
		if Net.host_lobby():
			Router.go_lobby())
	left.add_child(host)
	left.add_child(UiTheme.label(tr("PLAY_JOIN_CODE"), 18, UiTheme.TEXT_DIM))
	var code_row := HBoxContainer.new()
	left.add_child(code_row)
	var code := LineEdit.new()
	code.placeholder_text = "ABC123"
	code.custom_minimum_size = Vector2(260, 60)
	code.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	code_row.add_child(code)
	var join_code := UiTheme.button(tr("PLAY_JOIN"), 60)
	join_code.custom_minimum_size.x = 130
	join_code.pressed.connect(func() -> void:
		var txt := code.text.strip_edges()
		var ok := false
		match Net.classify_join_input(txt):
			"online": ok = Net.join_online(txt)
			"ip": ok = Net.join_lobby(txt, Net.DEFAULT_PORT)
			_: ok = Net.join_by_code(txt)
		if ok:
			_await_join())
	code_row.add_child(join_code)
	left.add_child(UiTheme.label(tr("PLAY_JOIN_HINT"), 14, UiTheme.TEXT_DIM))
	# right: LAN lobbies
	var right := PanelContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(right)
	var rv := VBoxContainer.new()
	right.add_child(rv)
	rv.add_child(UiTheme.label(tr("PLAY_LAN_LOBBIES"), 22, UiTheme.ACCENT_2))
	_lan_list = VBoxContainer.new()
	rv.add_child(_lan_list)
	Net.discovery.start_listening()
	if not Net.discovery.lobbies_changed.is_connected(_refresh_lan):
		Net.discovery.lobbies_changed.connect(_refresh_lan)
	_refresh_lan()


func _refresh_lan() -> void:
	if _lan_list == null or not is_instance_valid(_lan_list):
		return
	for c in _lan_list.get_children():
		c.queue_free()
	if Net.discovery.lobbies.is_empty():
		_lan_list.add_child(UiTheme.label(tr("PLAY_SEARCHING"), 16, UiTheme.TEXT_DIM))
		return
	for key: String in Net.discovery.lobbies:
		var info: Dictionary = Net.discovery.lobbies[key]
		var b := UiTheme.button("%s   %d/%d" % [str(info.get("name", "?")), int(info.get("players", 0)), int(info.get("max", 4))], 60)
		var ip := str(info.ip)
		var port := int(info.get("port", Net.DEFAULT_PORT))
		b.pressed.connect(func() -> void:
			if Net.join_lobby(ip, port):
				_await_join())
		_lan_list.add_child(b)


func _await_online_host() -> void:
	Router.show_loading("LOADING_ONLINE_LOBBY")
	var on_update := func() -> void:
		if Net.state == Net.State.HOSTING:
			Router.hide_loading()
			Router.go_lobby()
	Net.lobby_updated.connect(on_update, CONNECT_ONE_SHOT)
	Net.connection_failed.connect(func(_r: String) -> void:
		Router.hide_loading()
		if Net.lobby_updated.is_connected(on_update):
			Net.lobby_updated.disconnect(on_update), CONNECT_ONE_SHOT)


func _await_join() -> void:
	Router.show_loading("LOADING_CONNECTING")
	var on_update := func() -> void:
		if Net.state == Net.State.CONNECTED:
			Router.hide_loading()
			Router.go_lobby()
	Net.lobby_updated.connect(on_update, CONNECT_ONE_SHOT)
	Net.connection_failed.connect(func(_r: String) -> void:
		Router.hide_loading()
		if Net.lobby_updated.is_connected(on_update):
			Net.lobby_updated.disconnect(on_update), CONNECT_ONE_SHOT)
	Net.session_lost.connect(func(_r: String) -> void: Router.hide_loading(), CONNECT_ONE_SHOT)


func _exit_tree() -> void:
	if Net.discovery and Net.discovery.listening:
		Net.discovery.stop()
