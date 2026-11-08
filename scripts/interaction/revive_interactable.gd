class_name ReviveInteractable
extends Interactable
## Attached to every player. Visible to teammates only while that player is downed.
## Hold time comes from the reviver's stats (perks can change it).

var owner_player: Node3D


func _ready() -> void:
	prompt_key = "PROMPT_REVIVE"
	interact_range = 2.0
	focus_height = 0.4
	noise_radius = 2.5
	tag = &"revive"


func is_visible_to(player: Node) -> bool:
	return player != owner_player and owner_player != null and owner_player.call("is_downed")


func can_interact(player: Node) -> String:
	if owner_player == null or not owner_player.call("is_downed"):
		return "REASON_UNAVAILABLE"
	if player == owner_player:
		return "REASON_UNAVAILABLE"
	return ""


func get_prompt(_player: Node) -> String:
	return tr("PROMPT_REVIVE").format({"name": owner_player.call("display_name")})


func get_hold_time(player: Node) -> float:
	var stats: PlayerStatsData = player.get("stats")
	return stats.revive_time if stats else 4.5


func server_hold_tick(player: Node, progress: float) -> void:
	owner_player.health.server_set_revive_progress(progress, int(player.peer_id))


func server_interact(player: Node) -> void:
	owner_player.health.server_revive(int(player.peer_id))
	super.server_interact(player)
