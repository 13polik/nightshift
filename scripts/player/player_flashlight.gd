class_name PlayerFlashlight
extends Node3D
## Flashlight with a limited battery. The owner toggles it (replicated in the movement
## state flags); the server drains the battery authoritatively and pushes corrections.
## Only the local player's light casts shadows (mobile budget).

signal battery_changed(value: float, max_value: float)
signal toggled(on: bool)

var player: Node3D # PlayerCharacter
var on := false
var battery := 180.0
var battery_max := 180.0
var light: SpotLight3D
var _flicker_t := 0.0
var _sync_t := 0.0
var _dust: GPUParticles3D


func setup(p_player: Node3D, stats: PlayerStatsData, local: bool) -> void:
	player = p_player
	battery_max = stats.flashlight_battery_seconds
	battery = battery_max
	light = SpotLight3D.new()
	light.spot_range = 20.0
	light.spot_angle = 26.0
	light.spot_angle_attenuation = 0.6
	light.spot_attenuation = 1.1
	light.light_energy = 3.0
	light.light_color = Color(1.0, 0.95, 0.85)
	var skin: CosmeticData = Content.cosmetic(StringName(str(player.info.get("cosmetics", {}).get(str(CosmeticData.Slot.FLASHLIGHT), ""))))
	if skin:
		light.light_color = skin.accent_color.lerp(Color.WHITE, 0.35)
	light.light_specular = 0.5
	light.shadow_enabled = local and bool(Settings.preset().flashlight_shadows)
	light.shadow_bias = 0.06
	# projected cookie: hot core, soft spill and reflector rings like a real torch
	if ResourceLoader.exists("res://assets/effects/textures/flashlight_cookie.png"):
		light.light_projector = load("res://assets/effects/textures/flashlight_cookie.png")
		light.spot_angle = 30.0
		light.spot_angle_attenuation = 0.35
	light.distance_fade_enabled = not local
	light.distance_fade_begin = 30.0
	light.distance_fade_length = 8.0
	light.visible = false
	add_child(light)
	if local:
		_dust = Effects.beam_dust(self)
	Events.graphics_quality_changed.connect(func(_q: int) -> void:
		if is_instance_valid(light):
			light.shadow_enabled = player.is_local and bool(Settings.preset().flashlight_shadows))


func set_on(v: bool) -> void:
	if v and battery <= 0.0:
		v = false
	if on == v:
		return
	on = v
	Audio.play_3d("flashlight", global_position, -8.0, 6.0)
	toggled.emit(on)


func server_recharge() -> void:
	battery = battery_max
	_push()


func set_aim(origin: Vector3, direction: Vector3) -> void:
	global_position = origin
	if direction.length_squared() > 0.001:
		look_at(origin + direction, Vector3.UP if absf(direction.normalized().y) < 0.98 else Vector3.FORWARD)


func _process(delta: float) -> void:
	if light == null:
		return
	# battery drain: server authoritative, owner predicts for the HUD
	if on and (multiplayer.is_server() or player.is_local):
		battery = maxf(0.0, battery - delta)
		if battery <= 0.0:
			set_on(false)
	if multiplayer.is_server():
		_sync_t += delta
		if _sync_t >= 2.0:
			_sync_t = 0.0
			_push()
	var visible_now := on
	var energy := 3.0
	if on and battery < battery_max * 0.12:
		_flicker_t -= delta
		if _flicker_t <= 0.0:
			_flicker_t = randf_range(0.05, 0.4)
		energy = 3.0 * (0.25 if _flicker_t < 0.08 else 0.8)
	light.visible = visible_now
	light.light_energy = energy
	if _dust:
		_dust.emitting = visible_now
	battery_changed.emit(battery, battery_max)


func _push() -> void:
	if not multiplayer.is_server():
		return
	if player.peer_id == multiplayer.get_unique_id():
		return
	_rpc_battery.rpc_id(player.peer_id, battery)


@rpc("authority", "call_remote", "reliable")
func _rpc_battery(value: float) -> void:
	battery = value
	if battery <= 0.0:
		set_on(false)
