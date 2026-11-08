class_name ProfilePanel
extends VBoxContainer
## Player profile: editable name, level/XP, currency, lifetime statistics.


func _ready() -> void:
	add_theme_constant_override("separation", 14)
	add_child(UiTheme.label(tr("MENU_PROFILE"), 30, UiTheme.ACCENT))
	var name_row := HBoxContainer.new()
	add_child(name_row)
	var l := UiTheme.label(tr("PROFILE_NAME"))
	l.custom_minimum_size.x = 220
	name_row.add_child(l)
	var edit := LineEdit.new()
	edit.text = Profile.display_name()
	edit.max_length = 20
	edit.custom_minimum_size = Vector2(320, 56)
	name_row.add_child(edit)
	var save := UiTheme.button(tr("UI_SAVE"), 56)
	save.custom_minimum_size.x = 140
	save.pressed.connect(func() -> void:
		Profile.set_display_name(edit.text)
		edit.text = Profile.display_name()
		Net.refresh_local_info()
		Events.toast("TOAST_SAVED", Events.ToastKind.SUCCESS))
	name_row.add_child(save)
	var li := Profile.level_info()
	add_child(UiTheme.label(tr("PROFILE_LEVEL").format({"level": li.level}), 24))
	var xp := ProgressBar.new()
	xp.custom_minimum_size = Vector2(500, 14)
	xp.max_value = float(li.needed)
	xp.value = float(li.into_level)
	xp.show_percentage = false
	add_child(xp)
	add_child(UiTheme.label(tr("PROFILE_XP").format({"xp": li.into_level, "needed": li.needed}), 16, UiTheme.TEXT_DIM))
	add_child(UiTheme.label(tr("PROFILE_CURRENCY").format({"amount": Profile.currency()}), 20))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 40)
	add_child(grid)
	var s: Dictionary = Profile.data.stats
	for key in ["missions_played", "missions_won", "extractions", "deaths", "revives", "objectives"]:
		grid.add_child(UiTheme.label(tr("STAT_" + key.to_upper()), 18, UiTheme.TEXT_DIM))
		grid.add_child(UiTheme.label(str(int(s.get(key, 0))), 18))
	grid.add_child(UiTheme.label(tr("STAT_PLAY_TIME"), 18, UiTheme.TEXT_DIM))
	grid.add_child(UiTheme.label("%dh %02dm" % [int(s.play_seconds) / 3600, (int(s.play_seconds) / 60) % 60], 18))
