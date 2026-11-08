class_name MissionGenerator
extends RefCounted
## Server-side controlled procedural variation. The facility architecture is authored;
## this decides, from the mission seed:
##  * which candidate devices host each objective, which components are required
##  * which optional objectives are offered
##  * which doors are locked (keycard / jammed) and which underground route is harder
##  * loot placement and container contents, objective item placement
##  * the Hunter's spawn point and initial patrol route
##  * the extraction point
## The result is a plain Dictionary broadcast to clients (no reliance on cross-platform
## RNG determinism for gameplay state).

var mission: MissionData
var facility: FacilityRuntime
var rng: SeededRng
var player_count := 1


func _init(p_mission: MissionData, p_facility: FacilityRuntime, p_seed: int, p_players: int) -> void:
	mission = p_mission
	facility = p_facility
	rng = SeededRng.new(p_seed)
	player_count = maxi(1, p_players)


func generate() -> Dictionary:
	var setup := {
		"seed": rng.seed_value,
		"objectives": [],
		"optional": [],
		"locked_doors": {},
		"route": {},
		"extraction_room": &"",
		"enemy_spawn": Vector3.ZERO,
		"enemy_spawns": [],
		"patrol_route": 0,
	}
	var chosen_items: Dictionary = {} # objective id -> {item: count}
	var r_obj := rng.stream("objectives")
	for i in mission.objectives.size():
		setup.objectives.append(_objective_runtime(mission.objectives[i], i, r_obj, chosen_items))
	var r_opt := rng.stream("optional")
	var pool := mission.optional_objectives.duplicate()
	SeededRng.shuffle(pool, r_opt)
	for i in mini(mission.optional_count, pool.size()):
		var rt := _objective_runtime(pool[i], i, r_opt, chosen_items)
		rt.optional_index = mission.optional_objectives.find(pool[i])
		setup.optional.append(rt)
	_choose_locks(setup)
	_choose_extraction(setup)
	_choose_enemy(setup)
	return setup


func _objective_runtime(def: ObjectiveData, index: int, r: RandomNumberGenerator, chosen_items: Dictionary) -> Dictionary:
	var rt := {"index": index, "id": def.id, "targets": [], "rooms": [], "items": {}, "optional_index": -1}
	match def.type:
		ObjectiveData.Type.REACH_ZONE, ObjectiveData.Type.EXTRACT:
			var rooms := facility.rooms_with_tag(def.target_tag)
			rt.rooms = rooms if def.type == ObjectiveData.Type.REACH_ZONE else []
		ObjectiveData.Type.INTERACT, ObjectiveData.Type.DELIVER:
			var cands := facility.devices_with_tag(def.target_tag)
			var ids: Array = []
			for d in cands:
				ids.append(d.net_id)
			rt.targets = SeededRng.pick_n(ids, maxi(1, def.target_count), r)
			if def.type == ObjectiveData.Type.DELIVER:
				rt.items = _required_items(def, r, chosen_items)
		ObjectiveData.Type.COLLECT:
			rt.items = _required_items(def, r, chosen_items)
	chosen_items[def.id] = rt.items
	return rt


## Items a COLLECT/DELIVER objective needs. `item_pool` entries may reference an earlier
## objective as "@objective_id" to reuse its picks (collect components -> install them).
func _required_items(def: ObjectiveData, r: RandomNumberGenerator, chosen_items: Dictionary) -> Dictionary:
	var out := {}
	if def.item_pool.size() == 1 and def.item_pool[0].begins_with("@"):
		var src := StringName(def.item_pool[0].substr(1))
		return (chosen_items.get(src, {}) as Dictionary).duplicate()
	var pool: Array = Array(def.item_pool)
	var picks: Array = SeededRng.pick_n(pool, def.pick_items, r) if def.pick_items > 0 else pool
	for it in picks:
		out[str(it)] = def.required_count
	return out


func _choose_locks(setup: Dictionary) -> void:
	var r := rng.stream("locks")
	var lockable: Array = []
	for id: StringName in facility.doors:
		var d: Dictionary = {}
		for raw in facility.layout.doors:
			if raw.id == id:
				d = raw
		if d.get("lockable", false) and str(d.get("route_lock", "")).is_empty():
			lockable.append(id)
	lockable.sort()
	var n := r.randi_range(1, mini(3, lockable.size()))
	for id in SeededRng.pick_n(lockable, n, r):
		setup.locked_doors[id] = "keycard" if r.randf() < 0.6 else "jammed"
	# underground access: the stairwell door is keycard-locked or jammed; the elevator
	# always needs power + keycard. Either way players must explore for tools/access.
	for raw in facility.layout.doors:
		if str(raw.get("route_lock", "")) == "underground_access":
			var kind := "keycard" if r.randf() < 0.55 else "jammed"
			setup.locked_doors[raw.id] = kind
			setup.route["stairs"] = kind
	setup.route["elevator_keycard"] = true


func _choose_extraction(setup: Dictionary) -> void:
	var r := rng.stream("extraction")
	var rooms := facility.rooms_with_tag(&"extraction")
	setup.extraction_room = SeededRng.pick(rooms, r) if not rooms.is_empty() else &""


func _choose_enemy(setup: Dictionary) -> void:
	var r := rng.stream("enemy")
	if not facility.enemy_spawns.is_empty():
		setup.enemy_spawn = SeededRng.pick(facility.enemy_spawns, r)
		# one distinct spawn per enemy (wraps when there are fewer spawn points)
		var pool: Array = facility.enemy_spawns.duplicate()
		pool.erase(setup.enemy_spawn)
		var spawns: Array = [setup.enemy_spawn]
		for i in range(1, mission.enemies.size()):
			if pool.is_empty():
				pool = facility.enemy_spawns.duplicate()
			var pick: Vector3 = SeededRng.pick(pool, r)
			pool.erase(pick)
			spawns.append(pick)
		setup.enemy_spawns = spawns
	setup.patrol_route = r.randi_range(0, maxi(0, facility.patrol_routes.size() - 1))


## Places loot and objective items. Server only; returns nothing (spawns directly).
static func populate_loot(mission_data: MissionData, fac: FacilityRuntime, setup: Dictionary, seed_rng: SeededRng, players: int, pickups: PickupManager) -> Dictionary:
	var r := seed_rng.stream("loot")
	var table := mission_data.loot_table if mission_data.loot_table else LootTable.new()
	var stats := {"loose": 0, "containers": 0, "objective_items": 0}
	var containers: Array = fac.containers.duplicate()
	var points: Array = fac.loot_points.duplicate()
	SeededRng.shuffle(containers, r)
	SeededRng.shuffle(points, r)
	var used_containers := {}
	# 1) objective items into containers/points with the objective's spawn tag
	var all_objs: Array = setup.objectives + setup.optional
	for rt: Dictionary in all_objs:
		var def: ObjectiveData = _def_for(mission_data, rt)
		if def == null or def.spawn_items_tag == &"" or (rt.items as Dictionary).is_empty():
			continue
		for item: String in rt.items:
			var total := int(rt.items[item]) + def.spare_items
			for k in total:
				var placed := false
				for c: Searchable in containers:
					if used_containers.has(c) or not String(def.spawn_items_tag) in c.loot_tags:
						continue
					c.contents.append([item, 1])
					used_containers[c] = true
					placed = true
					break
				if not placed:
					for i in points.size():
						var p: Dictionary = points[i]
						if String(def.spawn_items_tag) in (p.tags as PackedStringArray):
							pickups.server_spawn(StringName(item), 1, p.pos)
							points.remove_at(i)
							placed = true
							break
				if placed:
					stats.objective_items += 1
				else:
					Log.w("loot", "no spawn point for objective item %s (tag %s)" % [item, def.spawn_items_tag])
	# 2) guaranteed items
	for item in table.guaranteed:
		for k in int(table.guaranteed[item]):
			if points.is_empty():
				break
			var p: Dictionary = points.pop_back()
			pickups.server_spawn(StringName(item), 1, p.pos)
			stats.loose += 1
	# 3) generic loot in remaining points/containers (scaled by player count)
	var ratio := clampf(table.fill_ratio + table.per_player_bonus * (players - 1), 0.0, 1.0)
	for p: Dictionary in points:
		if r.randf() < ratio:
			var item := table.roll(r)
			if item != &"":
				pickups.server_spawn(item, 1, p.pos)
				stats.loose += 1
	var cratio := clampf(table.container_fill_ratio + table.per_player_bonus * (players - 1), 0.0, 1.0)
	for c: Searchable in containers:
		if used_containers.has(c):
			continue
		if r.randf() < cratio:
			var item := table.roll(r)
			if item != &"":
				c.contents.append([String(item), 1])
				stats.containers += 1
	return stats


static func _def_for(m: MissionData, rt: Dictionary) -> ObjectiveData:
	if int(rt.get("optional_index", -1)) >= 0:
		return m.optional_objectives[int(rt.optional_index)]
	return m.objectives[int(rt.index)]
