class_name NoiseBurstEvent
extends MissionEvent
## Scripted loud noise at a tagged device (e.g. the generator spinning up). Pulls the
## Hunter toward the players' location - a consequence of their own progress.


func start() -> void:
	var tag := StringName(str(param("device_tag", "generator")))
	var devices: Array[ObjectiveDevice] = mission.facility.devices_with_tag(tag)
	if devices.is_empty():
		finish()
		return
	var pos: Vector3 = devices[0].global_position
	mission.noise.emit_noise(pos, float(param("loudness", 40.0)), &"machine", 0)
	finish()
