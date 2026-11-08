extends MissionTestCase
## Every mission in data/missions: the facility builds, every objective target exists and
## the navmesh connects insertion and extraction. With --ns-full (or --ns-test=all_missions)
## each mission is also played through its whole objective chain to a successful extraction
## (slow: about a minute per mission).


func before_each() -> void:
	pass # each test spins up its own missions


func _start(id: StringName, s: int) -> void:
	mission_id = id
	seed_value = s
	await super.before_each()


func _stop() -> void:
	await after_each()


func _full() -> bool:
	return CmdArgs.has("full") or CmdArgs.value("test").contains("all_missions")


func test_every_mission_builds_and_is_completable() -> void:
	var ids: Array = Content.sorted_missions().map(func(m: MissionData) -> StringName: return m.id)
	check(ids.size() >= 15, "15 missions available (%d)" % ids.size())
	# --ns-only=a,b limits the run to some missions (debugging)
	var only := CmdArgs.value("only")
	if not only.is_empty():
		ids = ids.filter(func(x: StringName) -> bool: return String(x) in only.split(","))
	var seen_layouts := {}
	for id: StringName in ids:
		await _start(id, 1000 + ids.find(id))
		check(mission.running, "%s: mission started" % id)
		if not mission.running:
			await _stop()
			continue
		seen_layouts[mission.data.layout_path] = true
		check(Content.mission(id).validate().is_empty(), "%s: data valid %s" % [id, Content.mission(id).validate()])
		check(mission.facility.room_info.size() >= 10, "%s: rooms built (%d)" % [id, mission.facility.room_info.size()])
		check(mission.enemies.all().size() == mission.data.enemies.size(), "%s: %d hunters spawned" % [id, mission.data.enemies.size()])
		# every objective has something to act on
		for h: ObjectiveHandler in mission.director.main + mission.director.optional:
			var def := h.def
			var rt: Dictionary = h.rt
			match def.type:
				ObjectiveData.Type.INTERACT, ObjectiveData.Type.DELIVER:
					check(not (rt.get("targets", []) as Array).is_empty(), "%s/%s: has a target device" % [id, def.id])
				ObjectiveData.Type.REACH_ZONE:
					check(not (rt.get("rooms", []) as Array).is_empty(), "%s/%s: has a target room" % [id, def.id])
		# insertion and extraction are connected for the AI / players
		await wait_frames(4)
		var spawn: Vector3 = mission.facility.spawn_points[0]
		var ex := room_center(StringName(str(mission.setup.extraction_room)))
		var m := mission.get_world_3d().navigation_map
		# the navigation map syncs asynchronously after the bake
		var path := PackedVector3Array()
		for i in 120:
			path = NavigationServer3D.map_get_path(m, spawn, ex, true)
			if path.size() > 1:
				break
			await wait_frames(1)
		var end_d := path[path.size() - 1].distance_to(ex) if path.size() > 0 else -1.0
		check(path.size() > 1 and end_d < 3.0, "%s: spawn connects to extraction (path %d pts, ends %.1f m from %s %s)" % [id, path.size(), end_d, mission.setup.extraction_room, ex])
		if _full():
			await play_objective_chain()
			await wait_until(func() -> bool: return mission.ended, 120)
			check(mission.ended and bool(mission.last_result.get("success", false)), "%s: completed (%s)" % [id, mission.last_result.get("reason", "")])
			Log.i("test", "MISSION_OK %s" % id)
		await _stop()
	check(not only.is_empty() or seen_layouts.size() == ids.size(), "every mission has its own map (%d/%d)" % [seen_layouts.size(), ids.size()])
