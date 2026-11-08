class_name CustomizePanel
extends HBoxContainer
## Cosmetic customisation: slot tabs, item list (owned / buy with earned currency /
## locked by level), live 3D preview. Cosmetics are visual only (no pay-to-win).

const SLOTS := [CosmeticData.Slot.SUIT_COLOR, CosmeticData.Slot.HELMET, CosmeticData.Slot.FLASHLIGHT, CosmeticData.Slot.TOOL, CosmeticData.Slot.PROFILE_ICON]
const SLOT_KEYS := {
	CosmeticData.Slot.SUIT_COLOR: "SLOT_SUIT", CosmeticData.Slot.HELMET: "SLOT_HELMET",
	CosmeticData.Slot.FLASHLIGHT: "SLOT_FLASHLIGHT", CosmeticData.Slot.TOOL: "SLOT_TOOL",
	CosmeticData.Slot.PROFILE_ICON: "SLOT_PROFILE_ICON", CosmeticData.Slot.OUTFIT: "SLOT_OUTFIT",
	CosmeticData.Slot.PROFILE_BANNER: "SLOT_BANNER",
}

var _slot := CosmeticData.Slot.SUIT_COLOR
var _list: VBoxContainer
var _preview: CharacterPreview
var _currency: Label


func _ready() -> void:
	add_theme_constant_override("separation", 24)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(left)
	var head := HBoxContainer.new()
	left.add_child(head)
	var t := UiTheme.label(tr("MENU_CUSTOMIZE"), 30, UiTheme.ACCENT)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	_currency = UiTheme.label("", 20, UiTheme.TEXT_DIM)
	head.add_child(_currency)
	var tabs := HBoxContainer.new()
	left.add_child(tabs)
	for s in SLOTS:
		var b := UiTheme.button(tr(SLOT_KEYS[s]), 52)
		var slot: int = s
		b.pressed.connect(func() -> void:
			_slot = slot
			_refresh())
		tabs.add_child(b)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)
	_preview = CharacterPreview.new()
	add_child(_preview)
	_refresh()


func _refresh() -> void:
	_currency.text = tr("PROFILE_CURRENCY").format({"amount": Profile.currency()})
	for c in _list.get_children():
		c.queue_free()
	var equipped := Profile.equipped_id(_slot)
	var items := Content.cosmetics_for_slot(_slot)
	if items.is_empty():
		_list.add_child(UiTheme.label(tr("CUSTOMIZE_EMPTY"), 18, UiTheme.TEXT_DIM))
	for c in items:
		var row := HBoxContainer.new()
		_list.add_child(row)
		var swatch := ColorRect.new()
		swatch.color = c.primary_color if _slot == CosmeticData.Slot.SUIT_COLOR else c.accent_color
		swatch.custom_minimum_size = Vector2(44, 44)
		row.add_child(swatch)
		var name_l := UiTheme.label("%s  %s" % [c.icon_glyph, tr(c.name_key)])
		name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_l)
		var b: Button
		if Profile.is_unlocked(c):
			b = UiTheme.button(tr("CUSTOMIZE_EQUIPPED") if c.id == equipped else tr("CUSTOMIZE_EQUIP"), 52)
			b.disabled = c.id == equipped
			b.pressed.connect(func() -> void:
				Profile.equip(c)
				Net.refresh_local_info()
				_refresh())
		elif c.source == CosmeticData.Source.CURRENCY and Profile.level() >= c.unlock_level:
			b = UiTheme.button(tr("CUSTOMIZE_BUY").format({"price": c.price}), 52)
			b.disabled = not Profile.can_purchase(c)
			b.pressed.connect(func() -> void:
				if Profile.purchase(c):
					Audio.play_ui("ui_confirm")
					Profile.equip(c)
					_refresh())
		else:
			b = UiTheme.button(tr("CUSTOMIZE_LOCKED").format({"level": c.unlock_level}), 52)
			b.disabled = true
		b.custom_minimum_size.x = 200
		row.add_child(b)
	_preview.show_cosmetics(Profile.cosmetic_payload())
