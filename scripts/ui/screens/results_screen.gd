extends UiScreen
## Mission results: outcome, per-player status, earned XP/currency, level-ups, unlocks.
## Host returns everyone to the lobby; clients wait (or leave).


func build() -> void:
	var r: Dictionary = Router.last_results
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	content.add_child(v)
	var success := bool(r.get("success", false))
	v.add_child(UiTheme.label(tr("RESULT_SUCCESS") if success else tr("RESULT_FAILED"), 48, UiTheme.SUCCESS if success else UiTheme.DANGER))
	v.add_child(UiTheme.label(tr(str(r.get("reason", ""))), 20, UiTheme.TEXT_DIM))
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 30)
	v.add_child(cols)
	var team := PanelContainer.new()
	team.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(team)
	var tv := VBoxContainer.new()
	team.add_child(tv)
	tv.add_child(UiTheme.label(tr("RESULT_TEAM"), 22, UiTheme.ACCENT_2))
	var results: Dictionary = r.get("results", {})
	for peer in results:
		var pr: Dictionary = results[peer]
		var st := tr("STATE_EXTRACTED") if pr.get("extracted", false) else tr("STATE_MIA")
		tv.add_child(UiTheme.label("%s  -  %s  (+%d XP)" % [str(pr.get("name", "?")), st, int(pr.get("reward", {}).get("xp", 0))], 18))
	var mine := PanelContainer.new()
	mine.custom_minimum_size.x = 380
	cols.add_child(mine)
	var mv := VBoxContainer.new()
	mine.add_child(mv)
	var s: Dictionary = r.get("summary", {})
	mv.add_child(UiTheme.label(tr("RESULT_REWARDS"), 22, UiTheme.ACCENT_2))
	mv.add_child(UiTheme.label("+%d XP" % int(s.get("xp", 0)), 30, UiTheme.ACCENT))
	mv.add_child(UiTheme.label(tr("PROFILE_CURRENCY").format({"amount": "+%d" % int(s.get("currency", 0))}), 22))
	if int(s.get("level_after", 1)) > int(s.get("level_before", 1)):
		mv.add_child(UiTheme.label(tr("RESULT_LEVEL_UP").format({"level": int(s.level_after)}), 24, UiTheme.SUCCESS))
	for u in s.get("unlocks", []):
		var c := Content.cosmetic(StringName(str(u)))
		if c:
			mv.add_child(UiTheme.label(tr("RESULT_UNLOCKED").format({"name": tr(c.name_key)}), 18, UiTheme.SUCCESS))
	var li := Profile.level_info()
	var xp := ProgressBar.new()
	xp.custom_minimum_size = Vector2(340, 12)
	xp.max_value = float(li.needed)
	xp.value = float(li.into_level)
	xp.show_percentage = false
	mv.add_child(xp)
	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_END
	v.add_child(actions)
	if Net.state == Net.State.OFFLINE:
		var menu := UiTheme.primary_button(tr("RESULT_MAIN_MENU"))
		menu.pressed.connect(Router.go_main_menu)
		actions.add_child(menu)
	elif Net.is_server():
		var cont := UiTheme.primary_button(tr("RESULT_CONTINUE"))
		cont.custom_minimum_size.x = 300
		cont.pressed.connect(func() -> void:
			Net.server_return_to_lobby())
		actions.add_child(cont)
	else:
		actions.add_child(UiTheme.label(tr("RESULT_WAITING_HOST"), 18, UiTheme.TEXT_DIM))
		var leave := UiTheme.button(tr("LOBBY_LEAVE"))
		leave.pressed.connect(func() -> void:
			Net.leave()
			Router.go_main_menu())
		actions.add_child(leave)


func go_back() -> void:
	pass
