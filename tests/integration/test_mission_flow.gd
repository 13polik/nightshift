extends MissionTestCase
## End-to-end headless tests on a real mission instance (solo session, real facility,
## real navmesh, real AI). Run with --fixed-fps 60 so simulated time is deterministic.

func test_mission_boots_with_full_facility() -> void:
	check(mission.running, "mission started")
	check(mission.facility.room_info.size() >= 20, "facility rooms built (%d)" % mission.facility.room_info.size())
	check(mission.facility.doors.size() >= 25, "doors built (%d)" % mission.facility.doors.size())
	check(mission.facility.containers.size() >= 10, "searchable containers (%d)" % mission.facility.containers.size())
	check(mission.facility.loot_points.size() >= 10, "loot points (%d)" % mission.facility.loot_points.size())
	var nm := mission.facility.nav_region.navigation_mesh
	check(nm != null and nm.get_polygon_count() > 50, "navmesh baked (%d polys)" % (nm.get_polygon_count() if nm else 0))
	check(player() != null, "local player spawned")
	eq(mission.director.index, 0, "first objective active")
	check(mission.pickups.get_child_count() > 3, "loot spawned (%d)" % mission.pickups.get_child_count())
	check(player().inventory.has_item(&"battery"), "loadout granted")
	eq(mission.state.get_flag(&"power_main"), false, "mission starts unpowered")
	# variation: a different seed must produce a different setup
	var g := MissionGenerator.new(mission.data, mission.facility, seed_value + 1, 1)
	var other := g.generate()
	var differs: bool = other.locked_doors != mission.setup.locked_doors or other.objectives[2].items != mission.setup.objectives[2].items or other.extraction_room != mission.setup.extraction_room or other.objectives[3].targets != mission.setup.objectives[3].targets
	check(differs, "seeded variation changes the mission setup")
	var same := MissionGenerator.new(mission.data, mission.facility, seed_value, 1).generate()
	eq(same.locked_doors, mission.setup.locked_doors, "same seed reproduces locks")


func test_full_objective_chain_to_extraction() -> void:
	await play_objective_chain()
	await wait_until(func() -> bool: return mission.ended, 120)
	check(mission.ended, "mission ended")
	check(bool(mission.last_result.get("success", false)), "mission succeeded: %s" % mission.last_result.get("reason", ""))
	var mine: Dictionary = mission.last_result.get("results", {}).get(1, {})
	check(bool(mine.get("extracted", false)), "player extracted")
	check(bool(mine.get("carried_objective", false)), "sample carried out")
	check(int(mission.last_result.get("summary", {}).get("xp", 0)) > 500, "rewards granted")


func test_hunter_ai_detects_chases_loses_and_searches() -> void:
	mission._release_enemies()
	var e: EnemyBase = mission.enemies.all()[0]
	check(e.active, "hunter released")
	var hunted := await wait_until(func() -> bool: return e.brain.state_name() in [EnemyBrain.PATROL, EnemyBrain.IDLE], 120)
	check(hunted, "hunter starts patrolling (%s)" % e.brain.state_name())
	await wait_frames(90)
	# noise -> investigate
	mission.noise.emit_noise(e.global_position + Vector3(2.0, 0.2, 0.0), 20.0, &"test", 0)
	await wait_frames(2)
	eq(e.brain.state_name(), EnemyBrain.INVESTIGATE, "noise triggers investigation")
	# visible player in front -> alert -> chase -> attack
	var p := player()
	p.flashlight.set_on(true)
	# the hunter keeps turning while it investigates, so re-place the player in its
	# current field of view until it reacts (each placement gets ~1.3 s)
	var chased := false
	for attempt in 6:
		var spot := visible_spot(e)
		if spot == Vector3.INF:
			await wait_frames(20)
			continue
		teleport(spot)
		chased = await wait_until(func() -> bool: return e.brain.state_name() in [EnemyBrain.CHASE, EnemyBrain.ATTACK], 80)
		if chased:
			break
	check(chased, "hunter chases a visible player (%s)" % e.brain.state_name())
	var hist := e.brain.history
	check(hist.find(EnemyBrain.ALERT) != -1 and hist.find(EnemyBrain.ALERT) < hist.rfind(EnemyBrain.CHASE), "alert telegraph precedes chase")
	var downed := await wait_until(func() -> bool: return p.is_downed(), 900)
	check(downed, "repeated attacks down the player (health %.0f)" % p.health.health)
	await wait_frames(30)
	check(e.brain.state_name() in [EnemyBrain.SEARCH, EnemyBrain.RETURN_TO_PATROL, EnemyBrain.CHASE, EnemyBrain.ATTACK, EnemyBrain.LOST_TARGET], "hunter lingers after downing (%s)" % e.brain.state_name())
	check(not e.target_valid(p), "downed players are not valid targets")
	# revive, then break line of sight far away -> lost target -> search
	p.health.server_revive(1)
	check(p.can_act(), "player revived")
	p.flashlight.set_on(true)
	var reacquired := false
	for attempt in 8:
		var spot2 := visible_spot(e)
		if spot2 == Vector3.INF:
			await wait_frames(20)
			continue
		teleport(spot2)
		reacquired = await wait_until(func() -> bool: return e.brain.state_name() == EnemyBrain.CHASE, 90)
		if reacquired:
			break
	check(reacquired, "hunter re-acquires the revived player (%s)" % e.brain.state_name())
	p.flashlight.set_on(false)
	# hide in the room farthest from the hunter (must be genuinely out of sight)
	var far_room: StringName = &"yard"
	var far_d := 0.0
	for rid: StringName in mission.facility.room_info:
		var d := room_center(rid).distance_to(e.global_position)
		if d > far_d:
			far_d = d
			far_room = rid
	teleport(room_center(far_room))
	var lost := await wait_until(func() -> bool: return EnemyBrain.LOST_TARGET in e.brain.history.slice(e.brain.history.rfind(EnemyBrain.CHASE)), 900)
	check(lost, "hunter loses a player who breaks line of sight (history %s, dist %.1f, seen %s)" % [e.brain.history.slice(-8), e.global_position.distance_to(p.global_position), e.perception.can_see(p)])
	var searched := await wait_until(func() -> bool: return e.brain.state_name() == EnemyBrain.SEARCH, 1800)
	check(searched, "hunter searches the last known position (%s)" % e.brain.state_name())
	var returned := await wait_until(func() -> bool: return e.brain.state_name() in [EnemyBrain.RETURN_TO_PATROL, EnemyBrain.PATROL, EnemyBrain.IDLE], 3000)
	check(returned, "hunter eventually returns to patrol (%s)" % e.brain.state_name())
	# stun
	e.server_stun(2.0)
	eq(e.brain.state_name(), EnemyBrain.STUNNED, "arc stun works")


func test_health_items_doors_and_bleed_out() -> void:
	freeze_enemies()
	var p := player()
	# damage + medkit
	p.health.server_damage(60.0, Vector3.ZERO)
	eq(int(p.health.health), 40, "damage applied")
	p.inventory.server_add(&"medkit", 1)
	var slot := -1
	for i in p.inventory.slots.size():
		if str(p.inventory.slots[i].id) == "medkit":
			slot = i
	p.inventory._srv_use(slot)
	await wait_until(func() -> bool: return p.inventory.using_slot == -1, 400)
	check(p.health.health > 99.0, "medkit heals (%.0f)" % p.health.health)
	check(not p.inventory.has_item(&"medkit"), "medkit consumed")
	# drop + pick up through the interaction system
	var before := mission.pickups.get_child_count()
	p.inventory._srv_drop(0)
	await wait_frames(2)
	eq(mission.pickups.get_child_count(), before + 1, "drop spawns a pickup")
	# searchable container
	var cont: Searchable = null
	for c in mission.facility.containers:
		if not c.contents.is_empty():
			cont = c
			break
	check(cont != null, "a container holds loot")
	if cont:
		var n := mission.pickups.get_child_count()
		teleport(cont.global_transform * Vector3(0, 0, 1.0))
		await wait_frames(2)
		p.interactor._pressed = true
		mission.interactions._srv_begin(cont.net_id)
		await wait_until(func() -> bool: return cont.searched, 200)
		check(cont.searched and mission.pickups.get_child_count() > n, "searching spawns its loot")
	# door + lockdown + crowbar
	var door: Door = mission.facility.doors[&"door_entrance"]
	var was := door.is_open
	await use_device(door)
	check(door.is_open != was, "door toggles")
	mission.events.trigger(&"lockdown")
	var locked := mission.facility.doors.values().filter(func(dd: Door) -> bool: return dd.lock_kind == "lockdown")
	check(not locked.is_empty(), "lockdown locks doors")
	if not locked.is_empty():
		var ld: Door = locked[0]
		check(not ld.can_interact(p).is_empty(), "locked door refuses without crowbar")
		p.inventory.server_add(&"crowbar", 1)
		await use_device(ld)
		check(ld.is_open and ld.broken, "crowbar forces a locked door")
	# power failure event + breaker
	mission.state.set_flag(&"power_main", true)
	mission.events.trigger(&"power_failure")
	eq(mission.state.get_flag(&"power_main"), false, "power failure cuts power")
	var br := mission.facility.devices_with_tag(&"power_breaker")[0]
	check(br.is_visible_to(p), "breaker usable during blackout")
	await use_device(br)
	eq(mission.state.get_flag(&"power_main"), true, "breaker restores power")
	# downed -> bleed out -> dead -> mission fails (solo)
	p.health.server_damage(500.0, Vector3.ZERO)
	check(p.is_downed(), "lethal damage downs instead of killing")
	var dead := await wait_until(func() -> bool: return p.is_dead(), int(p.stats.bleed_out_time * 60) + 120)
	check(dead, "bleed-out kills the player")
	await wait_until(func() -> bool: return mission.ended, 120)
	check(mission.ended and not bool(mission.last_result.get("success", true)), "mission fails when nobody can act")


func test_all_events_run_cleanly() -> void:
	freeze_enemies()
	mission.state.set_flag(&"power_main", true)
	for ev: EventData in mission.data.events:
		var ok := mission.events.trigger(ev.id)
		check(ok or ev.id == &"power_failure", "event %s starts" % ev.id)
		await wait_frames(30)
	check(mission.state.get_flag(&"evac", false), "evacuation flag set")
	mission.events.stop_all()
	await wait_frames(5)
	eq(mission.state.get_flag(&"lockdown", false), false, "lockdown cleared after stop")


## A hunted player can be freed mid-attack (disconnect). The AI must drop the reference
## instead of raising "previously freed" errors every tick.
func test_hunter_survives_target_disconnect() -> void:
	mission._release_enemies()
	var e: EnemyBase = mission.enemies.all()[0]
	var ghost := Node3D.new() # stands in for a player node that is about to be freed
	mission.add_child(ghost)
	e.brain.target = ghost
	e.perception._players[999] = ghost
	e.perception.awareness[999] = 1.0
	e.brain.transition(EnemyBrain.ATTACK)
	ghost.free()
	check(e.perception.most_aware_target() == null, "perception skips a disconnected player (no error)")
	check(not e.perception.awareness.has(999), "perception forgets the disconnected player")
	check(not e.target_valid(e.brain.target), "freed target is not valid (no error)")
	await wait_frames(2)
	check(e.brain.target == null, "brain forgot the freed target")
	var left := await wait_until(func() -> bool: return e.brain.state_name() != EnemyBrain.ATTACK, 600)
	check(left, "hunter left the attack state (%s)" % e.brain.state_name())
