class_name AutoStarter
extends Node
## Automation helper (--ns-autostart=N): the host marks clients ready and starts the
## mission once N players are in the lobby. Used by the multiplayer smoke test.

var needed := 2


static func attach(p_needed: int) -> void:
	var a := AutoStarter.new()
	a.needed = p_needed
	a.name = "AutoStarter"
	Net.add_child(a)


func _process(_delta: float) -> void:
	if not Net.is_server() or Net.phase != Net.Phase.LOBBY:
		return
	if Net.players.size() >= needed:
		for id in Net.players:
			Net.players[id].ready = true
		if CmdArgs.has("mission"):
			Net.set_selected_mission(StringName(CmdArgs.value("mission")))
		Log.i("auto", "%d players present - starting mission %s" % [Net.players.size(), Net.selected_mission])
		Net.start_mission()
		queue_free()
