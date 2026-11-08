class_name PlayerInteractor
extends Node
## Local-player interaction front end: finds the focused interactable, shows its prompt
## and runs press / hold requests against the server-authoritative InteractionService.

signal focus_changed(target: Interactable)
signal hold_progress(progress: float)
signal denied(reason_key: String)
signal inspect_requested(note: Interactable)

const SCAN_INTERVAL := 0.1

var player: Node3D # PlayerCharacter
var service: InteractionService
var focus: Interactable
var holding: Interactable
var _hold_elapsed := 0.0
var _hold_duration := 0.0
var _scan_t := 0.0
var _pressed := false


func setup(p_player: Node3D, p_service: InteractionService) -> void:
	player = p_player
	service = p_service
	service.local_hold_started.connect(_on_hold_started)
	service.local_hold_finished.connect(_on_hold_finished)
	service.local_denied.connect(func(_i: Interactable, reason: String) -> void:
		denied.emit(reason)
		Audio.play_ui("ui_error", -6.0))
	service.local_inspect.connect(func(i: Interactable) -> void: inspect_requested.emit(i))
	GameInput.action_pressed.connect(_on_action_pressed)
	GameInput.action_released.connect(_on_action_released)


func is_holding() -> bool:
	return holding != null


func prompt_text() -> String:
	if focus == null:
		return ""
	return focus.get_prompt(player)


func can_use_focus() -> bool:
	return focus != null and focus.can_interact(player).is_empty()


func _process(delta: float) -> void:
	if player == null:
		return
	_scan_t -= delta
	if _scan_t <= 0.0 and holding == null:
		_scan_t = SCAN_INTERVAL
		var cam: PlayerCamera = player.camera
		var facing := -player.global_basis.z
		if cam:
			var f := cam.forward()
			facing = Vector3(f.x, 0, f.z).normalized()
		var new_focus: Interactable = null
		if player.can_act() or player.is_downed():
			new_focus = service.find_focus(player, facing, player.stats.interact_range)
			if new_focus and player.is_downed() and not new_focus.allow_while_downed:
				new_focus = null
		if new_focus != focus:
			focus = new_focus
			focus_changed.emit(focus)
	if holding:
		_hold_elapsed += delta
		hold_progress.emit(clampf(_hold_elapsed / maxf(_hold_duration, 0.01), 0.0, 1.0))
		if not is_instance_valid(holding) or player.global_position.distance_to(holding.focus_point()) > holding.interact_range + 1.5:
			cancel()


func _on_action_pressed(action: StringName) -> void:
	if action != &"interact" or player == null or not player.is_local:
		return
	_pressed = true
	if focus == null:
		return
	var reason := focus.can_interact(player)
	if not reason.is_empty():
		denied.emit(reason)
		Audio.play_ui("ui_error", -6.0)
		return
	service.request_begin(focus)


func _on_action_released(action: StringName) -> void:
	if action != &"interact":
		return
	_pressed = false
	if holding:
		cancel()


func cancel() -> void:
	if holding:
		service.request_cancel()
	holding = null
	hold_progress.emit(0.0)


func _on_hold_started(i: Interactable, duration: float) -> void:
	if not _pressed:
		# button released before the server answered
		service.request_cancel()
		return
	holding = i
	_hold_elapsed = 0.0
	_hold_duration = duration
	Audio.play_ui("ui_click", -10.0)


func _on_hold_finished(i: Interactable, completed: bool) -> void:
	if completed:
		Audio.play_ui("ui_confirm", -6.0)
	if holding == i or i == null:
		holding = null
		hold_progress.emit(0.0)
	_scan_t = 0.0
