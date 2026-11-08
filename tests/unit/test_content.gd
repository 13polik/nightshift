extends TestCase
## Data integrity: content database, mission definition, facility layout, localization.


func test_content_database_has_no_errors() -> void:
	eq(Content.errors.size(), 0, "content errors: %s" % ", ".join(Content.errors))
	check(Content.items.size() >= 9, "at least the core items exist")
	check(Content.mission(&"power_restoration") != null, "first mission exists")
	check(Content.enemies.has(&"hunter"), "the Hunter exists")


func test_mission_definition_is_consistent() -> void:
	var m := Content.mission(&"power_restoration")
	eq(m.validate().size(), 0, "mission validate()")
	var ids := {}
	for o in m.objectives + m.optional_objectives:
		check(not ids.has(o.id), "duplicate objective id %s" % o.id)
		ids[o.id] = true
		for item in o.item_pool:
			if item.begins_with("@"):
				check(ids.has(StringName(item.substr(1))), "%s references earlier objective %s" % [o.id, item])
			else:
				check(Content.item(StringName(item)) != null, "%s uses unknown item %s" % [o.id, item])
		for ev in o.events_on_start + o.events_on_complete:
			check(m.events.any(func(e: EventData) -> bool: return e.id == StringName(ev)), "%s triggers unknown event %s" % [o.id, ev])
	for e in m.events:
		check(e.event_script != null, "event %s has a script" % e.id)
		var inst: Variant = e.event_script.new()
		check(inst is MissionEvent, "event %s script extends MissionEvent" % e.id)


func test_facility_layout_is_valid_and_connected() -> void:
	var l := FacilityLayout.load_json("res://data/facilities/research_facility.json")
	var problems := l.validate()
	eq(problems.size(), 0, "layout problems: %s" % "; ".join(problems))
	check(l.rooms.size() >= 13, "facility has all required areas")
	for tag in ["entrance", "security_checkpoint", "maintenance", "generator_room", "server_room", "medical", "offices", "laboratory", "storage", "underground", "elevator", "emergency_exit", "extraction"]:
		check(not l.rooms_with_tag(tag).is_empty(), "facility has area tagged %s" % tag)
	# multiple routes: removing any single door must not disconnect the core loop
	var adj := l.adjacency()
	var corridor_links: int = (adj[&"corridor_main"] as Array).size()
	check(corridor_links >= 6, "main corridor connects to many areas (%d)" % corridor_links)


func test_every_objective_tag_has_targets() -> void:
	var l := FacilityLayout.load_json("res://data/facilities/research_facility.json")
	var device_tags := {}
	for r in l.rooms:
		for f: Dictionary in r.features:
			if f.get("type") == "interactable":
				device_tags[str(f.get("tag", f.kind))] = int(device_tags.get(str(f.get("tag", f.kind)), 0)) + 1
	var m := Content.mission(&"power_restoration")
	for o in m.objectives + m.optional_objectives:
		match o.type:
			ObjectiveData.Type.INTERACT, ObjectiveData.Type.DELIVER:
				check(device_tags.has(String(o.target_tag)), "objective %s has device candidates for %s" % [o.id, o.target_tag])
			ObjectiveData.Type.REACH_ZONE, ObjectiveData.Type.EXTRACT:
				check(not l.rooms_with_tag(String(o.target_tag)).is_empty(), "objective %s has rooms for %s" % [o.id, o.target_tag])
		if o.spawn_items_tag != &"":
			check(l.rooms.any(func(r: Dictionary) -> bool: return String(o.spawn_items_tag) in r.loot_tags), "objective %s has spawn rooms for %s" % [o.id, o.spawn_items_tag])
	check(int(device_tags.get("electrical_panel", 0)) >= 2, "panel location varies between runs")


func test_localization_tables_match() -> void:
	var en := Loc.table("en")
	var pl := Loc.table("pl")
	check(en.size() > 200, "english table loaded")
	for k in en:
		check(pl.has(k), "pl missing %s" % k)
		var ph_en := _placeholders(str(en[k]))
		var ph_pl := _placeholders(str(pl.get(k, "")))
		eq(ph_pl, ph_en, "placeholders differ for %s" % k)
	for k in pl:
		check(en.has(k), "en missing %s" % k)


func test_all_data_keys_are_translated() -> void:
	var en := Loc.table("en")
	for it: ItemData in Content.items.values():
		check(en.has(it.name_key) and en.has(it.description_key), "item %s keys" % it.id)
	for c: CosmeticData in Content.cosmetics.values():
		check(en.has(c.name_key), "cosmetic %s key" % c.id)
	for p: PerkData in Content.perks.values():
		check(en.has(p.name_key) and en.has(p.description_key), "perk %s keys" % p.id)
	for l: LoadoutOptionData in Content.loadouts.values():
		check(en.has(l.name_key), "loadout %s key" % l.id)
	var m := Content.mission(&"power_restoration")
	for o in m.objectives + m.optional_objectives:
		check(en.has(o.title_key) and en.has(o.hint_key), "objective %s keys" % o.id)
	for e in m.events:
		check(en.has(e.banner_key), "event %s banner" % e.id)
	var layout := FacilityLayout.load_json(m.layout_path)
	for r in layout.rooms:
		check(en.has(str(r.name_key)), "room %s name" % r.id)
	Loc.set_language("pl", false)
	check(tr("MENU_PLAY") == "GRAJ", "switching language at runtime works")
	Loc.set_language("en", false)


func _placeholders(s: String) -> Array:
	var out: Array = []
	var re := RegEx.create_from_string("\\{([a-z_]+)\\}")
	for m in re.search_all(s):
		out.append(m.get_string(1))
	out.sort()
	return out
