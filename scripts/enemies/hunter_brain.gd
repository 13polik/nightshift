class_name HunterBrain
extends EnemyBrain
## THE HUNTER's behaviour set. Uses the standard states; tuned reactions on top:
##  * flashlight beams pointed at it are treated as an immediate strong stimulus
##  * loud mechanical noises (generator, alarms) pull it across the facility


func on_noise(stimulus: Dictionary) -> void:
	# Extremely loud noises override searching with a direct investigation.
	if float(stimulus.get("loudness", 0.0)) >= 14.0 and state_name() in [SEARCH, LOST_TARGET, PATROL, IDLE, RETURN_TO_PATROL]:
		transition(INVESTIGATE, {"position": stimulus.position})
		return
	super.on_noise(stimulus)
