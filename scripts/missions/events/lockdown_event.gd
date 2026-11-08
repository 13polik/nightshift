class_name LockdownEvent
extends MissionEvent
## Security lockdown: several lockdown-capable doors (preferring ones near players) slam
## shut and lock. Players must route around, or force a door with a crowbar.

var _doors: Array[Door] = []


func start() -> void:
	var count := int(param("doors", 3))
	var cands: Array = []
	var players: Array = mission.get_players()
	for d: Door in mission.facility.doors.values():
		if not d.lockdown_capable or d.broken or d.lock_kind != "":
			continue
		var best := INF
		for p: PlayerCharacter in players:
			if p.is_active():
				best = minf(best, p.global_position.distance_to(d.global_position))
		cands.append([best, d])
	cands.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	for i in mini(count, cands.size()):
		var d: Door = cands[i][1]
		d.set_lock("lockdown")
		_doors.append(d)
	mission.state.set_flag(&"lockdown", true)


func stop() -> void:
	for d in _doors:
		if d.lock_kind == "lockdown":
			d.set_lock("")
	mission.state.set_flag(&"lockdown", false)
