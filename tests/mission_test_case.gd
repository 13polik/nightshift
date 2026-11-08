class_name MissionTestCase
extends TestCase
## Shared setup + helpers for end-to-end tests on a real mission instance (solo session,
## real facility, real navmesh, real AI). Subclasses pick mission_id / seed_value.

var seed_value := 777
var mission_id: StringName = &"power_restoration"

var mission: MissionController


func before_each() -> void:
	Net.start_solo()
	Net.pending_mission = {"mission_id": mission_id, "seed": seed_value, "roster": Net.players}
	mission = load(Router.MISSION).instantiate()
	mission.auto_route_results = false
	runner.add_child(mission)
	var t := 0
	while not mission.running and t < 600:
		await wait_frames(1)
		t += 1


func after_each() -> void:
	if is_instance_valid(mission):
		mission.queue_free()
	await wait_frames(2)
	Net.leave(false)


func player() -> PlayerCharacter:
	return mission.local_player()


func teleport(pos: Vector3) -> void:
	var p := player()
	p.global_position = pos + Vector3.UP * 0.1
	p.velocity = Vector3.ZERO


func room_center(id: StringName) -> Vector3:
	var aabb: AABB = mission.facility.room_info[id].aabb
	var c := aabb.get_center()
	return Vector3(c.x, aabb.position.y + 0.1, c.z)


## A navigable point 3-6 m in front of the enemy with clear line of sight to its eyes.
func visible_spot(e: EnemyBase) -> Vector3:
	var space := e.get_world_3d().direct_space_state
	var fwd := -e.global_basis.z
	for dist in [4.0, 3.0, 5.0, 6.0, 2.5]:
		for ang in [0.0, 20.0, -20.0, 40.0, -40.0]:
			var dir := fwd.rotated(Vector3.UP, deg_to_rad(ang))
			var cand := e.reachable_point(e.global_position + dir * dist)
			if absf(cand.y - e.global_position.y) > 1.0 or cand.distance_to(e.global_position) < 2.0:
				continue
			var q := PhysicsRayQueryParameters3D.create(e.global_position + Vector3.UP * 2.0, cand + Vector3.UP * 1.1, 1 | 32)
			q.exclude = [e.get_rid()]
			if space.intersect_ray(q).is_empty():
				return cand
	return Vector3.INF


func freeze_enemies() -> void:
	for e: EnemyBase in mission.enemies.all():
		e.active = false
		e.stop()


func wait_until(cond: Callable, max_frames: int) -> bool:
	for i in max_frames:
		if cond.call():
			return true
		await wait_frames(1)
	return bool(cond.call())


## Uses a device like a player would: request -> hold -> complete (server validated).
func use_device(dev: Interactable, max_frames: int = 900) -> bool:
	var front := dev.global_transform * Vector3(0, 0, 1.3)
	if dev is ObjectiveDevice and (dev as ObjectiveDevice).kind == "generator":
		front = dev.global_transform * Vector3(0, 0, 2.0)
	teleport(front)
	await wait_frames(2)
	# behave like a held interact button so the local interactor keeps the hold
	player().interactor._pressed = true
	for attempt in 6:
		var before_done := dev is ObjectiveDevice and (dev as ObjectiveDevice).done
		mission.interactions._srv_begin(dev.net_id)
		var ok := await wait_until(func() -> bool: return not mission.interactions._holds.has(1), max_frames)
		if not ok:
			return false
		if dev is ObjectiveDevice:
			if (dev as ObjectiveDevice).done and not before_done:
				return true
			if (dev as ObjectiveDevice).missing_items().is_empty() and (dev as ObjectiveDevice).done:
				return true
		else:
			return true
	return dev is ObjectiveDevice and (dev as ObjectiveDevice).done


## Plays every objective in order like a (teleporting) player would, enemies frozen.
func play_objective_chain() -> void:
	var d := mission.director
	var guard := 0
	while not d.finished and guard < 20 and not mission.ended:
		guard += 1
		var h := d.current()
		var def := h.def
		var idx := d.index
		freeze_enemies()
		match def.type:
			ObjectiveData.Type.REACH_ZONE:
				teleport(room_center(StringName(h.rt.rooms[0])))
			ObjectiveData.Type.COLLECT:
				for item: String in h.rt.items:
					if not (item == "sample_case" and player().inventory.has_item(&"sample_case")):
						player().inventory.server_add(StringName(item), int(h.rt.items[item]))
			ObjectiveData.Type.INTERACT, ObjectiveData.Type.DELIVER:
				var dev := mission.interactions.get_interactable(int(h.rt.targets[0]))
				check(dev != null and dev.objective_active, "%s target active" % def.id)
				var ok := await use_device(dev)
				check(ok, "%s device completed (missing %s)" % [def.id, (dev as ObjectiveDevice).missing_items()])
				if def.grants_item != &"":
					await wait_frames(3)
					var granted := false
					for c in mission.pickups.get_children():
						if c is ItemPickup and c.item_id == def.grants_item:
							granted = true
							teleport(c.global_position + Vector3(0.6, 0, 0))
							await wait_frames(2)
							mission.interactions._srv_begin(c.net_id)
					check(granted, "%s granted %s" % [def.id, def.grants_item])
			ObjectiveData.Type.SURVIVE:
				teleport(room_center(StringName(str(mission.setup.extraction_room))) + Vector3(0, 0, -3))
			ObjectiveData.Type.EXTRACT:
				teleport(room_center(StringName(str(mission.setup.extraction_room))))
		var advanced := await wait_until(func() -> bool: return d.index != idx or d.finished or mission.ended, 6000)
		check(advanced, "objective %d (%s) completed" % [idx, def.id])
		if not advanced:
			break
		if def.id == &"restore_power":
			eq(mission.state.get_flag(&"power_main"), true, "power restored")
		if def.id == &"start_generator":
			check(mission.events.history.has(&"generator_noise"), "generator startup made noise")
		if def.id == &"call_evac":
			eq(mission.state.get_flag(&"evac"), true, "evacuation active")
