extends Control
## Boot: shows the title card while autoloads finish, validates content, applies dev /
## automation command line flags, then routes to the main menu.

var _quit_after := -1.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UiTheme.get_theme()
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.02, 0.025) # == boot_splash/bg_color
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	# same art as the engine boot splash, so the hand-over is seamless
	var splash := TextureRect.new()
	splash.texture = load("res://assets/ui/splash/splash.png")
	splash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	splash.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	splash.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	add_child(splash)
	var loading := UiTheme.label("...", 18, UiTheme.TEXT_DIM)
	loading.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	loading.position = Vector2(-120, -56)
	loading.name = "Loading"
	add_child(loading)
	var tw := create_tween().set_loops()
	tw.tween_property(loading, "modulate:a", 0.25, 0.6)
	tw.tween_property(loading, "modulate:a", 1.0, 0.6)
	var qa := CmdArgs.value("quit-after")
	if not qa.is_empty():
		_quit_after = float(qa)
	if not Content.errors.is_empty():
		Log.e("boot", "content has %d errors" % Content.errors.size())
	Log.i("boot", "NIGHT SHIFT %s | %s | renderer %s | quality %s" % [ProjectSettings.get_setting("application/config/version"),
		OS.get_name(), RenderingServer.get_current_rendering_method(), Settings.Quality.keys()[Settings.quality()]])
	if _quit_after > 0.0:
		# owned by the Router autoload: this boot screen is freed on the first scene change
		Router.schedule_quit(_quit_after)
	if CmdArgs.has("screenshot"):
		Router.schedule_screenshots(CmdArgs.value("screenshot"))
	_route.call_deferred()


func _route() -> void:
	var args := CmdArgs.all()
	if args.has("solo"):
		Net.start_solo()
		var mid := StringName(str(args.solo)) if str(args.solo) != "true" else &"power_restoration"
		Net.set_selected_mission(mid)
		Net.start_mission(int(args.get("seed", "-1")))
		return
	if args.has("host"):
		if Net.host_lobby():
			var needed := int(args.get("autostart", "0"))
			if needed > 0:
				AutoStarter.attach(needed)
			Router.go_lobby()
			return
	if args.has("host-online"):
		if Net.host_online():
			var needed_o := int(args.get("autostart", "0"))
			Net.lobby_updated.connect(func() -> void:
				if Net.state == Net.State.HOSTING and get_tree().current_scene == self:
					if needed_o > 0:
						AutoStarter.attach(needed_o)
					Router.go_lobby(), CONNECT_ONE_SHOT)
			return
	if args.has("join-online"):
		if Net.join_online(str(args["join-online"])):
			Net.lobby_updated.connect(func() -> void:
				if Net.state == Net.State.CONNECTED and get_tree().current_scene == self:
					Router.go_lobby(), CONNECT_ONE_SHOT)
			Net.connection_failed.connect(func(_r: String) -> void: Router.go_main_menu(), CONNECT_ONE_SHOT)
			return
	if args.has("join"):
		var addr := str(args.join)
		if Net.join_lobby(addr if addr != "true" else "127.0.0.1", Net.port):
			Router.show_loading("LOADING_CONNECTING")
			Net.lobby_updated.connect(func() -> void:
				if Net.state == Net.State.CONNECTED and get_tree().current_scene == self:
					Router.hide_loading()
					Router.go_lobby(), CONNECT_ONE_SHOT)
			Net.connection_failed.connect(func(_r: String) -> void: Router.go_main_menu(), CONNECT_ONE_SHOT)
			return
	await get_tree().create_timer(0.6).timeout
	# story intro on demand (it normally plays before the first game, see main menu)
	if args.has("intro"):
		Router.go_intro()
		return
	Router.go_main_menu()
