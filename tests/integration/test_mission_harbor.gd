extends MissionTestCase
## "Signal Lost" at the Greywater harbour depot: second facility layout, cold-storage room
## kind, harbour notes and its own objective chain (mast repair + radio + boat).


func _init() -> void:
	mission_id = &"signal_lost"
	seed_value = 4242


func test_harbor_depot_builds() -> void:
	check(mission.running, "mission started")
	eq(String(mission.data.id), "signal_lost", "harbour mission loaded")
	eq(mission.facility.room_info.size(), 14, "all harbour rooms built")
	check(mission.facility.doors.size() >= 15, "doors built (%d)" % mission.facility.doors.size())
	check(mission.facility.containers.size() >= 10, "searchable containers (%d)" % mission.facility.containers.size())
	var nm := mission.facility.nav_region.navigation_mesh
	check(nm != null and nm.get_polygon_count() > 50, "navmesh baked (%d polys)" % (nm.get_polygon_count() if nm else 0))
	eq(mission.facility.devices_with_tag(&"team_terminal").size(), 2, "two candidate team terminals")
	check(not mission.facility.devices_with_tag(&"mast_panel").is_empty(), "radio mast panel exists")
	check(not mission.facility.devices_with_tag(&"radio_console").is_empty(), "radio console exists")
	eq(str(mission.setup.extraction_room), "pier", "boat extraction at the pier")
	var notes := mission.find_children("*", "NoteInteractable", true, false)
	check(not notes.is_empty(), "notes placed")
	check(notes.all(func(n: Node) -> bool: return String((n as NoteInteractable).text_key).begins_with("NOTE_H")), "harbour notes, not Kessler ones")
	# the hunter can actually move between the insertion yard and the cold storage
	# (the navigation map syncs asynchronously after the bake: retry for a moment)
	var m := mission.get_world_3d().navigation_map
	var routes := [[&"gate_yard", &"freezer_b", "gate yard connects to cold storage"], [&"radio_room", &"pier", "radio room connects to the pier"]]
	for r: Array in routes:
		var to := room_center(r[1])
		var path := PackedVector3Array()
		for i in 120:
			path = NavigationServer3D.map_get_path(m, room_center(r[0]), to, true)
			if path.size() > 1:
				break
			await wait_frames(1)
		check(path.size() > 1 and path[path.size() - 1].distance_to(to) < 3.0, str(r[2]))


func test_harbor_full_objective_chain() -> void:
	await play_objective_chain()
	check(mission.state.get_flag(&"evac", false), "distress signal started the evacuation finale")
	await wait_until(func() -> bool: return mission.ended, 120)
	check(mission.ended, "mission ended")
	check(bool(mission.last_result.get("success", false)), "mission succeeded: %s" % mission.last_result.get("reason", ""))
	var mine: Dictionary = mission.last_result.get("results", {}).get(1, {})
	check(bool(mine.get("extracted", false)), "player extracted by boat")
