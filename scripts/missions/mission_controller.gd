class_name MissionController
extends Node3D
## Root of a running mission (node name "Mission" on every peer, so RPC paths match).
##
## Start-up handshake:
##   all peers build the facility (deterministic) -> clients report "loaded" ->
##   server generates the setup, bakes navigation, spawns players, sends setup + state
##   snapshot -> server populates loot and starts the mission.
## Players that never finish loading are dropped after LOAD_TIMEOUT so one bad
## connection cannot block everybody.

signal mission_started
signal mission_ended(success: bool)
signal player_spawned(player: PlayerCharacter)
signal player_removed(peer_id: int)
signal ping_received(peer_id: int, position: Vector3)

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const LOAD_TIMEOUT := 30.0
const DEFAULT_MISSION := &"power_restoration"

var data: MissionData
var layout: FacilityLayout
var facility: FacilityRuntime
var setup: Dictionary = {}
var seed_rng: SeededRng
var roster: Dictionary = {}
var running := false
var ended := false
var elapsed := 0.0
## Tests embed the mission and inspect results instead of changing scene.
var auto_route_results := true
var last_result: Dictionary = {}

var state: MissionState
var interactions: InteractionService
var noise: NoiseSystem
var power: PowerGrid
var pickups: PickupManager
var enemies: EnemyManager
var players_root: Node3D
var director: MissionDirector
var events: EventDirector
var environment: EnvironmentController
var ambience: AmbienceController
var hud: Node # MissionHud

var _loaded_peers: Dictionary = {}
var _load_timer := 0.0
var _waiting_for_peers := false
var _enemy_released := false
var _check_t := 0.0


func _ready() -> void:
	name = "Mission"
	var pm: Dictionary = Net.pending_mission
	if pm.is_empty():
		# Started directly (editor F6 / tests): run a solo session.
		Log.w("mission", "no pending mission - starting solo session")
		Net.start_solo()
		pm = {"mission_id": DEFAULT_MISSION, "seed": int(CmdArgs.value("seed", "1234")), "roster": Net.players}
		Net.pending_mission = pm
	data = Content.mission(StringName(pm.mission_id))
	if data == null:
		_abort("ERR_MISSING_ASSET")
		return
	roster = pm.roster
	seed_rng = SeededRng.new(int(pm.seed))
	layout = FacilityLayout.load_json(data.layout_path)
	var problems := layout.validate()
	if not layout.errors.is_empty():
		for p in layout.errors:
			Log.e("mission", p)
		_abort("ERR_MISSING_ASSET")
		return
	for p in problems:
		Log.w("mission", "layout: %s" % p)
	_create_systems()
	facility = FacilityBuilder.build(layout, self, interactions)
	power.setup(self, facility)
	environment.setup(self)
	ambience.setup(self)
	Audio.warm(["step_player", "step_hunter", "door_open", "door_close", "hunter_screech", "hunter_growl", "hunter_click", "amb_hum", "amb_vent", "amb_drone", "music_pulse", "music_tension", "music_chase", "pickup", "interact_done"])
	Net.peer_left.connect(_on_peer_left)
	if multiplayer.is_server():
		_waiting_for_peers = true
		_load_timer = LOAD_TIMEOUT
		_loaded_peers[1] = true
		_check_all_loaded()
	else:
		_srv_client_loaded.rpc_id(1)


func _create_systems() -> void:
	state = _add(MissionState.new(), "State")
	interactions = _add(InteractionService.new(), "Interactions")
	interactions.mission = self
	noise = _add(NoiseSystem.new(), "Noise")
	noise.mission = self
	interactions.noise = noise
	power = _add(PowerGrid.new(), "Power")
	pickups = _add(PickupManager.new(), "Pickups")
	pickups.mission = self
	enemies = _add(EnemyManager.new(), "Enemies")
	enemies.mission = self
	players_root = _add(Node3D.new(), "Players")
	director = _add(MissionDirector.new(), "Director")
	director.setup(self, data)
	events = _add(EventDirector.new(), "Events")
	events.setup(self, data, seed_rng)
	environment = _add(EnvironmentController.new(), "Environment")
	ambience = _add(AmbienceController.new(), "Ambience")
	var hud_scene: PackedScene = load("res://scenes/ui/hud.tscn")
	hud = hud_scene.instantiate()
	hud.name = "Hud"
	add_child(hud)
	hud.call("setup", self)


func _add(n: Node, n_name: String) -> Node:
	n.name = n_name
	add_child(n)
	return n


func _abort(reason_key: String) -> void:
	Log.e("mission", "aborting mission: %s" % reason_key)
	Router.hide_loading()
	if multiplayer.is_server() and not Net.is_solo and Net.is_online():
		Net.server_return_to_lobby()
		Router.go_lobby()
	else:
		Router.go_main_menu()
	Router.show_dialog("DIALOG_ERROR_TITLE", tr(reason_key))


# --- loading handshake ----------------------------------------------------------------

@rpc("any_peer", "call_remote", "reliable")
func _srv_client_loaded() -> void:
	if not multiplayer.is_server():
		return
	var peer := multiplayer.get_remote_sender_id()
	_loaded_peers[peer] = true
	Log.i("mission", "peer %d loaded the facility" % peer)
	_check_all_loaded()


func _check_all_loaded() -> void:
	if not _waiting_for_peers:
		return
	for peer: int in roster:
		if not _loaded_peers.has(peer) and Net.players.has(peer):
			return
	_waiting_for_peers = false
	_server_begin()


func _process(delta: float) -> void:
	if _waiting_for_peers:
		_load_timer -= delta
		if _load_timer <= 0.0:
			for peer: int in roster:
				if not _loaded_peers.has(peer) and Net.players.has(peer):
					Log.w("mission", "peer %d did not finish loading - removing from mission" % peer)
					Net.kick(peer, "NET_ERR_LOAD_TIMEOUT")
			_waiting_for_peers = false
			_server_begin()


func _server_begin() -> void:
	var active_peers: Array = []
	for peer: int in roster:
		if Net.players.has(peer) or peer == 1:
			active_peers.append(peer)
	active_peers.sort()
	var gen := MissionGenerator.new(data, facility, seed_rng.seed_value, active_peers.size())
	setup = gen.generate()
	facility.bake_navigation()
	# initial flags
	state.set_flag(&"power_main", data.start_powered)
	state.set_flag(&"power_underground", data.start_powered)
	state.set_flag(&"power_generator", data.start_powered)
	state.set_flag(&"elevator_online", true)
	state.set_flag(&"threat", 0.0)
	_apply_locks(setup)
	var spawn_list: Array = []
	for i in active_peers.size():
		var peer: int = active_peers[i]
		spawn_list.append([peer, Net.players.get(peer, roster.get(peer, {})), i])
	_rpc_setup.rpc(setup, state.snapshot(), interactions.snapshot())
	_rpc_spawn_players.rpc(spawn_list)
	for p in get_players():
		_give_loadout(p)
	var loot := MissionGenerator.populate_loot(data, facility, setup, seed_rng, active_peers.size(), pickups)
	Log.i("mission", "loot: %s" % loot)
	var spawns: Array = setup.get("enemy_spawns", [])
	for i in data.enemies.size():
		var at: Vector3 = spawns[i] if i < spawns.size() else setup.enemy_spawn
		var e := enemies.server_spawn(data.enemies[i], at)
		if e:
			e.visible = true
	_rpc_begin.rpc()
	director.server_start(setup)


func _apply_locks(s: Dictionary) -> void:
	for id in s.locked_doors:
		var d: Door = facility.doors.get(StringName(id))
		if d:
			d.set_lock(str(s.locked_doors[id]))
	for e: ElevatorPanel in facility.elevators:
		e.needs_keycard = bool(s.route.get("elevator_keycard", true))
		e.mark_dirty()


func _give_loadout(p: PlayerCharacter) -> void:
	p.inventory.server_add(&"battery", 1)
	var l := Content.loadout(StringName(str(p.info.get("loadout", "standard"))))
	if l:
		for item in l.items:
			p.inventory.server_add(StringName(item), int(l.items[item]))


@rpc("authority", "call_local", "reliable")
func _rpc_setup(p_setup: Dictionary, flags: Dictionary, inter_snapshot: Dictionary) -> void:
	setup = p_setup
	if not multiplayer.is_server():
		state.apply_snapshot(flags)
		interactions.apply_snapshot(inter_snapshot)


@rpc("authority", "call_local", "reliable")
func _rpc_spawn_players(list: Array) -> void:
	for entry: Array in list:
		var peer: int = entry[0]
		if players_root.has_node(str(peer)):
			continue
		var p: PlayerCharacter = PLAYER_SCENE.instantiate()
		p.setup(peer, entry[1], self)
		var spawns := facility.spawn_points
		var sp: Vector3 = spawns[int(entry[2]) % spawns.size()] if not spawns.is_empty() else Vector3(0, 1, 0)
		p.position = sp
		p.rotation.y = 0.0 # face north, toward the facility entrance
		players_root.add_child(p)
		interactions.register_dynamic(p.revive_point, 90000 + peer)
		player_spawned.emit(p)
	Log.i("mission", "spawned %d players" % list.size())


@rpc("authority", "call_local", "reliable")
func _rpc_begin() -> void:
	running = true
	Router.hide_loading()
	GameInput.reset()
	var me := local_player()
	if me:
		me.flashlight.set_on(true) # insertion at night: start with the torch on
	Log.i("mission", "MISSION_STARTED %s seed=%d players=%d" % [data.id, seed_rng.seed_value, get_players().size()])
	mission_started.emit()


# --- queries --------------------------------------------------------------------------

func get_players() -> Array:
	var out: Array = []
	if players_root == null:
		return out
	for c in players_root.get_children():
		if c is PlayerCharacter and not c.is_queued_for_deletion():
			out.append(c)
	return out


func get_player(peer: int) -> PlayerCharacter:
	if players_root == null:
		return null
	var n := players_root.get_node_or_null(str(peer))
	return n as PlayerCharacter


func local_player() -> PlayerCharacter:
	return get_player(multiplayer.get_unique_id())


func is_powered(zone: StringName) -> bool:
	return power.is_zone_powered(zone) if power else true


func is_position_lit(pos: Vector3) -> bool:
	var room := facility.room_at_position(pos)
	return room != &"" and power.is_room_lit(room)


func enemy_routes() -> Array:
	var out: Array = []
	for r: Dictionary in facility.patrol_routes:
		out.append(r.points)
	return out


func safe_respawn_point() -> Vector3:
	return facility.spawn_points[0] if not facility.spawn_points.is_empty() else Vector3.UP


# --- runtime --------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if not running or ended:
		return
	elapsed += delta
	if _netstat_enabled and int(elapsed / 5.0) != int((elapsed - delta) / 5.0):
		_log_netstat()
	if not multiplayer.is_server():
		return
	if not _enemy_released and (elapsed >= (float(CmdArgs.value("release")) if CmdArgs.has("release") else data.enemy_release_time) or director.index >= data.enemy_release_objective):
		_release_enemies()
	_check_t -= delta
	if _check_t <= 0.0:
		_check_t = 0.5
		_check_end_conditions()


var _netstat_enabled := CmdArgs.has("bot") or CmdArgs.has("netstat")


## Automation: replicated state as seen by this peer (compared across processes).
func _log_netstat() -> void:
	var parts: PackedStringArray = []
	for p: PlayerCharacter in get_players():
		var held: Variant = p.visual.get("_held_id") if p.visual else &""
		parts.append("%d@(%.1f,%.1f,%.1f)%s hp=%d inv=%d held=%s" % [p.peer_id, p.global_position.x, p.global_position.y, p.global_position.z,
			PlayerHealth.State.keys()[p.health.state], int(p.health.health), p.inventory.item_ids().size(), str(held) if held else "none"])
	var en: PackedStringArray = []
	for e: EnemyBase in enemies.all():
		en.append("%s@(%.1f,%.1f,%.1f)%s" % [e.name, e.global_position.x, e.global_position.y, e.global_position.z, e.replicated_state])
	var vp := get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp, true)
	Log.i("perf", "process=%.1fms physics=%.1fms render_cpu=%.1fms render_gpu=%.1fms draws=%d prims=%dk nodes=%d" % [
		Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
		RenderingServer.viewport_get_measured_render_time_cpu(vp), RenderingServer.viewport_get_measured_render_time_gpu(vp),
		RenderingServer.viewport_get_render_info(vp, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME),
		RenderingServer.viewport_get_render_info(vp, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME) / 1000,
		int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))])
	Log.i("netstat", "fps=%d t=%d obj=%d players=[%s] enemies=[%s] pickups=%d power=%s" % [Engine.get_frames_per_second(), int(elapsed),
		director.client_index if not multiplayer.is_server() else director.index, " | ".join(parts), " | ".join(en),
		pickups.get_child_count(), state.get_flag(&"power_main")])


func _release_enemies() -> void:
	_enemy_released = true
	var routes := enemy_routes()
	var n := 0
	for e: EnemyBase in enemies.all():
		# each hunter walks a different patrol route so they spread out
		var route: PackedVector3Array = routes[(int(setup.patrol_route) + n) % routes.size()] if not routes.is_empty() else PackedVector3Array()
		enemies.server_activate(e.enemy_id, route)
		n += 1


func _check_end_conditions() -> void:
	var players := get_players()
	if players.is_empty():
		server_end_mission(false, "RESULT_ALL_LOST")
		return
	var alive := 0
	var extracted := 0
	for p: PlayerCharacter in players:
		if p.can_act():
			alive += 1
		elif p.is_extracted():
			extracted += 1
	if director.finished:
		server_end_mission(extracted > 0, "RESULT_EXTRACTED" if extracted > 0 else "RESULT_MISSED_EVAC")
	elif alive == 0:
		if extracted > 0:
			server_end_mission(true, "RESULT_EXTRACTED")
		else:
			server_end_mission(false, "RESULT_ALL_LOST")


func server_end_mission(success: bool, reason_key: String) -> void:
	if ended or not multiplayer.is_server():
		return
	ended = true
	running = false
	events.stop_all()
	var earned := director.earned()
	var results := {}
	for p: PlayerCharacter in get_players():
		var r := earned.duplicate()
		r.success = success
		r.extracted = p.is_extracted()
		r.survived = p.is_extracted()
		r.died = not p.is_extracted()
		r.revives = p.health.revives_given
		r.carried_objective = p.is_extracted() and p.inventory.has_item(&"sample_case")
		r.duration = int(elapsed)
		r.reward = ProgressionRules.compute_rewards(data.rewards, r)
		r.name = p.display_name()
		results[p.peer_id] = r
	Log.i("mission", "MISSION_ENDED success=%s reason=%s duration=%ds" % [success, reason_key, int(elapsed)])
	_rpc_mission_ended.rpc(success, reason_key, results)


@rpc("authority", "call_local", "reliable")
func _rpc_mission_ended(success: bool, reason_key: String, results: Dictionary) -> void:
	ended = true
	running = false
	mission_ended.emit(success)
	var mine: Dictionary = results.get(multiplayer.get_unique_id(), {})
	var summary := {}
	if not mine.is_empty():
		summary = Profile.apply_mission_rewards(mine.get("reward", {}), mine)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	GameInput.reset()
	var payload := {"success": success, "reason": reason_key, "results": results, "summary": summary,
		"mission": String(data.id), "local_peer": multiplayer.get_unique_id()}
	last_result = payload
	if auto_route_results:
		get_tree().create_timer(2.5).timeout.connect(func() -> void: Router.go_results(payload))


func _on_peer_left(peer: int, _info: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	_loaded_peers.erase(peer)
	if _waiting_for_peers:
		_check_all_loaded()
		return
	var p := get_player(peer)
	if p:
		Log.i("mission", "player %d disconnected - dropping their items" % peer)
		interactions.cancel_holds_for(peer)
		p.inventory.server_drop_all()
	_rpc_remove_player.rpc(peer)


@rpc("authority", "call_local", "reliable")
func _rpc_remove_player(peer: int) -> void:
	var p := get_player(peer)
	if p:
		var n := p.display_name()
		interactions.registry.erase(90000 + peer)
		p.queue_free()
		Events.toast(tr("TOAST_PLAYER_LEFT").format({"name": n}), Events.ToastKind.WARNING)
	player_removed.emit(peer)


# --- player hooks ---------------------------------------------------------------------

func on_player_damaged(p: PlayerCharacter, amount: float, source: Vector3) -> void:
	if hud:
		hud.call("on_player_damaged", p, amount, source)


func on_player_state_changed(p: PlayerCharacter, new_state: int) -> void:
	if hud:
		hud.call("on_player_state_changed", p, new_state)
	if multiplayer.is_server() and new_state == PlayerHealth.State.DEAD:
		p.inventory.server_drop_all()


func on_player_extracted(p: PlayerCharacter) -> void:
	Log.i("mission", "%s extracted" % p.display_name())


## Arc emitter: stuns enemies in a short cone in front of the player.
func server_stun_pulse(p: PlayerCharacter, duration: float) -> void:
	var fwd := p.aim_direction()
	fwd.y = 0
	fwd = fwd.normalized()
	for e: EnemyBase in enemies.all():
		var to := e.global_position - p.global_position
		to.y = 0
		if to.length() <= 7.0 and (to.length() < 1.5 or fwd.dot(to.normalized()) > 0.5):
			e.server_stun(duration)
	noise.emit_noise(p.global_position, 12.0, &"stun", p.peer_id)


func request_ping(p: PlayerCharacter) -> void:
	var cam := p.camera
	var origin := cam.camera.global_position if cam else p.global_position + Vector3.UP * 1.5
	var dir := cam.aim_direction() if cam else -p.global_basis.z
	var q := PhysicsRayQueryParameters3D.create(origin, origin + dir * 40.0, 1 | 32)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	var pos: Vector3 = hit.position if not hit.is_empty() else origin + dir * 10.0
	Net.send_to_server(self, &"_srv_ping", [pos])


@rpc("any_peer", "call_remote", "reliable")
func _srv_ping(pos: Vector3) -> void:
	var peer := Net.sender_id()
	if get_player(peer) == null or not pos.is_finite():
		return
	_rpc_ping.rpc(peer, pos)


@rpc("authority", "call_local", "reliable")
func _rpc_ping(peer: int, pos: Vector3) -> void:
	Audio.play_ui("ping", -4.0)
	ping_received.emit(peer, pos)


func hud_event_banner(key: String, duration: float) -> void:
	if hud:
		hud.call("show_event_banner", key, duration)


## Leave the mission voluntarily (pause menu).
func leave_mission() -> void:
	if multiplayer.is_server() and not Net.is_solo and get_players().size() > 1:
		# host leaving ends the session for everyone (no host migration yet)
		Net.leave()
		Router.go_main_menu()
		return
	if Net.is_solo:
		if not ended:
			server_end_mission(false, "RESULT_ABANDONED")
		return
	Net.leave()
	Router.go_main_menu()


func _exit_tree() -> void:
	GameInput.reset()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
