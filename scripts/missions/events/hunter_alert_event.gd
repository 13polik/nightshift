class_name HunterAlertEvent
extends MissionEvent
## The Hunter becomes more aggressive and gets a rough fix on the team's location.

var _bonus := 0.5


func start() -> void:
	_bonus = float(param("aggression", 0.5))
	mission.events.aggression_bonus += _bonus
	mission.state.set_flag(&"hunter_alert", true)
	var players: Array = mission.get_players().filter(func(p: PlayerCharacter) -> bool: return p.can_act())
	if players.is_empty():
		return
	var p: PlayerCharacter = players[randi() % players.size()]
	var jitter := Vector3(randf_range(-6, 6), 0, randf_range(-6, 6))
	for e: EnemyBase in mission.enemies.all():
		if e.active and e.brain:
			e.brain.force_investigate(e.reachable_point(p.global_position + jitter))


func stop() -> void:
	mission.events.aggression_bonus = maxf(0.0, mission.events.aggression_bonus - _bonus)
	mission.state.set_flag(&"hunter_alert", false)
