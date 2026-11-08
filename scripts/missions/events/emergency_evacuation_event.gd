class_name EmergencyEvacuationEvent
extends MissionEvent
## Scripted finale: evacuation called. Alarm, maximum aggression, a lockdown wave and a
## visible countdown. Runs until the mission ends.

var _lockdown: LockdownEvent


func start() -> void:
	duration = 0.0 # runs until mission end
	mission.state.set_flag(&"evac", true)
	mission.state.set_flag(&"alarm", true)
	mission.events.aggression_bonus += 0.6
	var ld_data := EventData.new()
	ld_data.duration = float(param("lockdown_time", 25.0))
	ld_data.params = {"doors": int(param("lockdown_doors", 2))}
	_lockdown = LockdownEvent.new()
	_lockdown.setup(ld_data, mission)
	_lockdown.start()
	for e: EnemyBase in mission.enemies.all():
		if e.active and e.brain:
			var players: Array = mission.get_players().filter(func(p: PlayerCharacter) -> bool: return p.can_act())
			if not players.is_empty():
				e.brain.force_investigate(e.reachable_point((players[0] as PlayerCharacter).global_position))
	Audio.play_2d("evac_horn", 0.0)


func update(delta: float) -> void:
	elapsed += delta
	if _lockdown and not _lockdown.finished:
		_lockdown.update(delta)


func stop() -> void:
	if _lockdown and not _lockdown.finished:
		_lockdown.finish()
