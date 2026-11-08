extends Node
## Content bootstrap: writes the initial data resources (items, enemy, mission, events,
## cosmetics, perks, loadouts, player stats) with ResourceSaver so the .tres files are
## always valid. After bootstrapping, designers edit the .tres files in the editor; run
## this again only to reset the defaults:
##   godot --headless --path . res://tools/generate_content.tscn

var _written := 0


func _ready() -> void:
	_stats()
	_items()
	_enemies()
	_events()
	_mission()
	_cosmetics()
	_perks()
	_loadouts()
	print("generate_content: wrote %d resources" % _written)
	get_tree().quit(0)


func _save(res: Resource, path: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var err := ResourceSaver.save(res, path)
	if err != OK:
		push_error("failed to save %s: %s" % [path, error_string(err)])
	else:
		res.take_over_path(path)
		_written += 1


func _stats() -> void:
	_save(PlayerStatsData.new(), "res://data/player/default_stats.tres")


func _item(id: String, cat: int, glyph: String, color: Color, stack: int, effect: int = ItemData.UseEffect.NONE, amount: float = 0.0, use_time: float = 0.0, extra: Dictionary = {}) -> void:
	var it := ItemData.new()
	it.id = StringName(id)
	it.name_key = "ITEM_%s" % id.to_upper()
	it.description_key = "ITEM_%s_DESC" % id.to_upper()
	it.category = cat as ItemData.Category
	it.icon_glyph = glyph
	it.color = color
	it.max_stack = stack
	it.use_effect = effect as ItemData.UseEffect
	it.effect_amount = amount
	it.use_time = use_time
	for k in extra:
		it.set(k, extra[k])
	_save(it, "res://data/items/%s.tres" % id)


func _items() -> void:
	var C := ItemData.Category
	var E := ItemData.UseEffect
	_item("battery", C.CONSUMABLE, "B", Color(0.5, 1.0, 0.5), 3, E.RECHARGE_BATTERY, 0.0, 1.2)
	_item("medkit", C.CONSUMABLE, "+", Color(1.0, 0.35, 0.3), 1, E.HEAL, 65.0, 4.0)
	_item("bandage", C.CONSUMABLE, "b", Color(0.95, 0.9, 0.85), 3, E.HEAL, 22.0, 1.8)
	_item("keycard", C.KEY, "K", Color(0.3, 0.9, 1.0), 1, E.NONE, 0.0, 0.0, {"consumed_on_use": false})
	_item("fuse", C.COMPONENT, "F", Color(1.0, 0.7, 0.2), 2)
	_item("circuit_board", C.COMPONENT, "C", Color(0.3, 1.0, 0.45), 2)
	_item("capacitor", C.COMPONENT, "Q", Color(0.4, 0.7, 1.0), 2)
	_item("access_decoder", C.TOOL, "D", Color(0.3, 0.95, 0.9), 1, E.NONE, 0.0, 0.0, {"consumed_on_use": false})
	_item("sample_case", C.OBJECTIVE, "S", Color(1.0, 0.75, 0.2), 1)
	_item("crowbar", C.TOOL, "/", Color(0.9, 0.6, 0.1), 1, E.NONE, 0.0, 0.0, {"consumed_on_use": false})
	_item("arc_emitter", C.TOOL, "Z", Color(0.4, 0.9, 1.0), 1, E.STUN_PULSE, 4.0, 0.0, {"consumed_on_use": false, "requires_ammo": &"arc_cell"})
	_item("arc_cell", C.AMMO, "z", Color(0.4, 0.9, 1.0), 3)
	_item("data_drive", C.OBJECTIVE, "d", Color(0.4, 0.85, 1.0), 3)


func _enemies() -> void:
	var h := EnemyData.new()
	h.id = &"hunter"
	h.name_key = "ENEMY_HUNTER"
	h.brain_script = load("res://scripts/enemies/hunter_brain.gd")
	if ResourceLoader.exists("res://assets/creatures/hunter/hunter_visual.tscn"):
		h.scene = load("res://assets/creatures/hunter/hunter_visual.tscn")
	_save(h, "res://data/enemies/hunter.tres")


func _event(id: String, script_path: String, weight: float, min_threat: float, cooldown: float, duration: float, random: bool, params: Dictionary = {}) -> EventData:
	var e := EventData.new()
	e.id = StringName(id)
	e.name_key = "EVENT_%s" % id.to_upper()
	e.banner_key = "EVENT_%s_BANNER" % id.to_upper()
	e.event_script = load(script_path)
	e.weight = weight
	e.min_threat = min_threat
	e.cooldown = cooldown
	e.duration = duration
	e.random = random
	e.params = params
	_save(e, "res://data/events/%s.tres" % id)
	return e


var _events_list: Array[EventData] = []


func _events() -> void:
	var dir := "res://scripts/missions/events/"
	_events_list = [
		_event("power_failure", dir + "power_failure_event.gd", 1.0, 0.25, 150.0, 35.0, true),
		_event("lockdown", dir + "lockdown_event.gd", 1.2, 0.15, 120.0, 40.0, true, {"doors": 3}),
		_event("alarm", dir + "alarm_event.gd", 0.9, 0.3, 160.0, 45.0, true),
		_event("system_failure", dir + "system_failure_event.gd", 0.8, 0.2, 140.0, 60.0, true),
		_event("hunter_alert", dir + "hunter_alert_event.gd", 1.0, 0.1, 100.0, 30.0, true, {"aggression": 0.5}),
		_event("emergency_evacuation", dir + "emergency_evacuation_event.gd", 0.0, 0.0, 9999.0, 0.0, false, {"lockdown_doors": 2, "lockdown_time": 25.0}),
		_event("generator_noise", dir + "noise_burst_event.gd", 0.0, 0.0, 30.0, 0.0, false, {"device_tag": "generator", "loudness": 45.0}),
	]


func _obj(id: String, type: int, tag: String, extra: Dictionary = {}) -> ObjectiveData:
	var o := ObjectiveData.new()
	o.id = StringName(id)
	o.title_key = "OBJ_%s" % id.to_upper()
	o.hint_key = "OBJ_%s_HINT" % id.to_upper()
	o.type = type as ObjectiveData.Type
	o.target_tag = StringName(tag)
	for k in extra:
		o.set(k, extra[k])
	return o


func _mission() -> void:
	var T := ObjectiveData.Type
	var m := MissionData.new()
	m.id = &"power_restoration"
	m.name_key = "MISSION_POWER_RESTORATION"
	m.description_key = "MISSION_POWER_RESTORATION_DESC"
	m.location_key = "LOC_RESEARCH_FACILITY"
	m.layout_path = "res://data/facilities/research_facility.json"
	m.target_duration_minutes = 15.0
	m.objectives = [
		_obj("enter_facility", T.REACH_ZONE, "security_checkpoint", {"reward_xp": 30, "threat_on_complete": 0.02}),
		_obj("locate_maintenance", T.REACH_ZONE, "maintenance", {"reward_xp": 40}),
		_obj("find_components", T.COLLECT, "", {"item_pool": PackedStringArray(["fuse", "circuit_board", "capacitor"]), "pick_items": 2, "required_count": 1, "spawn_items_tag": &"component_spawn", "spare_items": 1, "reward_xp": 80}),
		_obj("repair_panel", T.DELIVER, "electrical_panel", {"item_pool": PackedStringArray(["@find_components"]), "duration": 5.0, "work_noise": 9.0, "reward_xp": 80, "threat_on_complete": 0.05}),
		_obj("start_generator", T.INTERACT, "generator", {"duration": 4.0, "work_noise": 16.0, "sets_flag": &"power_generator", "events_on_complete": PackedStringArray(["generator_noise"]), "reward_xp": 80, "threat_on_complete": 0.08}),
		_obj("restore_power", T.INTERACT, "power_breaker", {"duration": 2.0, "sets_flag": &"power_main,power_underground", "reward_xp": 80, "threat_on_complete": 0.08}),
		_obj("access_security", T.INTERACT, "security_terminal", {"duration": 6.0, "work_noise": 3.0, "reward_xp": 70}),
		_obj("obtain_access", T.COLLECT, "", {"item_pool": PackedStringArray(["keycard"]), "required_count": 1, "spawn_items_tag": &"keycard_spawn", "spare_items": 0, "reveal_item_location": true, "reward_xp": 70}),
		_obj("reach_underground", T.REACH_ZONE, "underground", {"reward_xp": 80, "threat_on_complete": 0.06}),
		_obj("containment", T.INTERACT, "containment_console", {"duration": 8.0, "work_noise": 12.0, "events_on_start": PackedStringArray(["hunter_alert"]), "grants_item": &"sample_case", "reward_xp": 150, "threat_on_complete": 0.1}),
		_obj("secure_sample", T.COLLECT, "", {"item_pool": PackedStringArray(["sample_case"]), "required_count": 1, "reward_xp": 40}),
		_obj("call_evac", T.INTERACT, "evac_console", {"duration": 3.0, "events_on_complete": PackedStringArray(["emergency_evacuation"]), "reward_xp": 60}),
		_obj("survive_evac", T.SURVIVE, "", {"duration": 75.0, "reward_xp": 120}),
		_obj("extract", T.EXTRACT, "extraction", {"duration": 90.0, "reward_xp": 0}),
	]
	m.optional_objectives = [
		_obj("opt_research", T.COLLECT, "", {"item_pool": PackedStringArray(["data_drive"]), "required_count": 2, "spawn_items_tag": &"research", "spare_items": 1, "optional": true, "reward_xp": 120, "reward_currency": 30}),
		_obj("opt_server", T.INTERACT, "server_terminal", {"duration": 8.0, "work_noise": 4.0, "optional": true, "reward_xp": 100, "reward_currency": 25}),
	]
	m.optional_count = 1
	m.events = _events_list
	var loot := LootTable.new()
	loot.weights = {"battery": 3.0, "bandage": 3.0, "medkit": 1.0, "arc_cell": 1.0, "crowbar": 0.6, "access_decoder": 0.5, "arc_emitter": 0.4}
	loot.guaranteed = {"crowbar": 1, "battery": 2, "arc_emitter": 1}
	loot.fill_ratio = 0.4
	loot.container_fill_ratio = 0.55
	m.loot_table = loot
	m.rewards = RewardData.new()
	m.enemies = [load("res://data/enemies/hunter.tres")]
	m.enemy_release_time = 90.0
	m.enemy_release_objective = 2
	_save(m, "res://data/missions/power_restoration.tres")


func _cos(id: String, slot: int, source: int, price: int, level: int, primary: Color, secondary: Color, accent: Color, glyph: String = "*", sku: String = "", rarity: int = 0) -> void:
	var c := CosmeticData.new()
	c.id = StringName(id)
	c.name_key = "COS_%s" % id.to_upper()
	c.slot = slot as CosmeticData.Slot
	c.source = source as CosmeticData.Source
	c.price = price
	c.unlock_level = level
	c.primary_color = primary
	c.secondary_color = secondary
	c.accent_color = accent
	c.icon_glyph = glyph
	c.store_sku = sku
	c.rarity = rarity as CosmeticData.Rarity
	_save(c, "res://data/cosmetics/%s.tres" % id)


func _cosmetics() -> void:
	var S := CosmeticData.Slot
	var R := CosmeticData.Source
	var dark := Color(0.1, 0.11, 0.12)
	_cos("suit_standard", S.SUIT_COLOR, R.DEFAULT, 0, 1, Color(0.32, 0.36, 0.34), dark, Color.WHITE)
	_cos("suit_hazard", S.SUIT_COLOR, R.LEVEL, 0, 2, Color(0.75, 0.55, 0.12), dark, Color.WHITE, "*", "", 1)
	_cos("suit_night", S.SUIT_COLOR, R.CURRENCY, 150, 1, Color(0.12, 0.14, 0.18), Color(0.05, 0.05, 0.06), Color.WHITE, "*", "", 1)
	_cos("suit_medic", S.SUIT_COLOR, R.CURRENCY, 250, 3, Color(0.8, 0.82, 0.82), Color(0.6, 0.12, 0.1), Color.WHITE, "*", "", 2)
	_cos("suit_crimson", S.SUIT_COLOR, R.LEVEL, 0, 5, Color(0.45, 0.08, 0.07), dark, Color.WHITE, "*", "", 3)
	_cos("suit_arctic", S.SUIT_COLOR, R.STORE, 0, 1, Color(0.85, 0.9, 0.95), Color(0.3, 0.4, 0.5), Color.WHITE, "*", "cosmetic.suit_arctic", 3)
	_cos("helmet_amber", S.HELMET, R.DEFAULT, 0, 1, Color.WHITE, dark, Color(1.0, 0.62, 0.18))
	_cos("helmet_cyan", S.HELMET, R.LEVEL, 0, 2, Color.WHITE, dark, Color(0.25, 0.9, 1.0), "*", "", 1)
	_cos("helmet_red", S.HELMET, R.CURRENCY, 120, 1, Color.WHITE, dark, Color(1.0, 0.15, 0.1), "*", "", 1)
	_cos("helmet_green", S.HELMET, R.CURRENCY, 200, 4, Color.WHITE, dark, Color(0.3, 1.0, 0.4), "*", "", 2)
	_cos("flashlight_standard", S.FLASHLIGHT, R.DEFAULT, 0, 1, Color.WHITE, dark, Color(1.0, 0.95, 0.85))
	_cos("flashlight_warm", S.FLASHLIGHT, R.CURRENCY, 100, 1, Color.WHITE, dark, Color(1.0, 0.8, 0.55), "*", "", 1)
	_cos("flashlight_cold", S.FLASHLIGHT, R.LEVEL, 0, 3, Color.WHITE, dark, Color(0.8, 0.9, 1.0), "*", "", 1)
	_cos("tool_standard", S.TOOL, R.DEFAULT, 0, 1, Color(0.3, 0.34, 0.33), dark, Color(0.4, 0.9, 1.0))
	_cos("tool_hazard", S.TOOL, R.LEVEL, 0, 3, Color(0.8, 0.6, 0.1), dark, Color(1.0, 0.5, 0.1), "*", "", 1)
	_cos("icon_default", S.PROFILE_ICON, R.DEFAULT, 0, 1, Color.WHITE, dark, Color.WHITE, "O")
	_cos("icon_eye", S.PROFILE_ICON, R.CURRENCY, 80, 1, Color.WHITE, dark, Color(1.0, 0.3, 0.2), "@", "", 1)
	_cos("icon_hunter", S.PROFILE_ICON, R.LEVEL, 0, 4, Color.WHITE, dark, Color(0.9, 0.95, 1.0), "Y", "", 2)


func _perk(id: String, level: int, glyph: String, mults: Dictionary) -> void:
	var p := PerkData.new()
	p.id = StringName(id)
	p.name_key = "PERK_%s" % id.to_upper()
	p.description_key = "PERK_%s_DESC" % id.to_upper()
	p.unlock_level = level
	p.icon_glyph = glyph
	p.stat_multipliers = mults
	_save(p, "res://data/perks/%s.tres" % id)


func _perks() -> void:
	_perk("quiet_steps", 2, "~", {"noise_walk": 0.8, "noise_sprint": 0.85, "sprint_speed": 0.95})
	_perk("field_medic", 3, "+", {"revive_time": 0.7, "max_health": 0.9})
	_perk("long_battery", 4, "*", {"flashlight_battery_seconds": 1.4, "stamina_max": 0.9})
	_perk("marathon", 6, ">", {"stamina_max": 1.3, "stamina_regen": 1.1, "noise_sprint": 1.15})


func _loadout(id: String, level: int, items: Dictionary) -> void:
	var l := LoadoutOptionData.new()
	l.id = StringName(id)
	l.name_key = "KIT_%s" % id.to_upper()
	l.description_key = "KIT_%s_DESC" % id.to_upper()
	l.unlock_level = level
	l.items = items
	_save(l, "res://data/loadouts/%s.tres" % id)


func _loadouts() -> void:
	_loadout("standard", 1, {"bandage": 1})
	_loadout("medic", 2, {"medkit": 1})
	_loadout("technician", 3, {"crowbar": 1})
	_loadout("defender", 5, {"arc_emitter": 1, "arc_cell": 1})
