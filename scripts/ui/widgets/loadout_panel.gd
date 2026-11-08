class_name LoadoutPanel
extends VBoxContainer
## "Inventory" menu: choose the starting equipment kit and one perk (sidegrades unlocked
## by level). Shows the items the kit contains.


func _ready() -> void:
	add_theme_constant_override("separation", 14)
	_build()


func _build() -> void:
	for c in get_children():
		c.queue_free()
	add_child(UiTheme.label(tr("MENU_INVENTORY"), 30, UiTheme.ACCENT))
	add_child(UiTheme.label(tr("LOADOUT_KITS"), 20, UiTheme.ACCENT_2))
	var kits := HBoxContainer.new()
	kits.add_theme_constant_override("separation", 12)
	add_child(kits)
	var ids := Content.loadouts.keys()
	ids.sort_custom(func(a: StringName, b: StringName) -> bool: return Content.loadouts[a].unlock_level < Content.loadouts[b].unlock_level)
	for id: StringName in ids:
		var l: LoadoutOptionData = Content.loadouts[id]
		kits.add_child(_card(tr(l.name_key), _kit_text(l), String(l.id) == str(Profile.data.loadout), Profile.is_loadout_unlocked(l), l.unlock_level,
			func() -> void:
				Profile.set_loadout(l.id)
				Net.refresh_local_info()
				_build()))
	add_child(UiTheme.label(tr("LOADOUT_PERKS"), 20, UiTheme.ACCENT_2))
	var perks := HBoxContainer.new()
	perks.add_theme_constant_override("separation", 12)
	add_child(perks)
	perks.add_child(_card(tr("PERK_NONE"), tr("PERK_NONE_DESC"), str(Profile.data.perk).is_empty(), true, 1,
		func() -> void:
			Profile.set_perk(&"")
			Net.refresh_local_info()
			_build()))
	var pids := Content.perks.keys()
	pids.sort()
	for id: StringName in pids:
		var p: PerkData = Content.perks[id]
		perks.add_child(_card("%s %s" % [p.icon_glyph, tr(p.name_key)], tr(p.description_key), String(p.id) == str(Profile.data.perk), Profile.is_perk_unlocked(p), p.unlock_level,
			func() -> void:
				Profile.set_perk(p.id)
				Net.refresh_local_info()
				_build()))


func _kit_text(l: LoadoutOptionData) -> String:
	var parts: PackedStringArray = [tr(l.description_key)]
	for item in l.items:
		var d := Content.item(StringName(item))
		parts.append("- %s x%d" % [tr(d.name_key) if d else str(item), int(l.items[item])])
	return "\n".join(parts)


func _card(title_text: String, body: String, selected: bool, unlocked: bool, level: int, on_pick: Callable) -> Control:
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(250, 200)
	if selected:
		p.add_theme_stylebox_override("panel", UiTheme.box(UiTheme.PANEL_LIGHT, UiTheme.ACCENT, 2, 8))
	var v := VBoxContainer.new()
	p.add_child(v)
	v.add_child(UiTheme.label(title_text, 20, UiTheme.ACCENT if selected else UiTheme.TEXT))
	var b := UiTheme.label(body, 15, UiTheme.TEXT_DIM)
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.custom_minimum_size.x = 220
	b.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(b)
	var btn := UiTheme.button(tr("CUSTOMIZE_EQUIPPED") if selected else (tr("CUSTOMIZE_EQUIP") if unlocked else tr("CUSTOMIZE_LOCKED").format({"level": level})), 50)
	btn.disabled = selected or not unlocked
	btn.pressed.connect(on_pick)
	v.add_child(btn)
	return p
