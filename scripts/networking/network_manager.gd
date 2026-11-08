extends Node
## Session + lobby layer (autoload "Net").
##
## Topology: listen server. The host (peer 1) is authoritative for lobby state, mission
## state, enemies, health, inventory, interactions and rewards. Clients own only their
## input/movement, which the server sanity-checks and relays.
## Solo play uses OfflineMultiplayerPeer through the exact same code paths.

const PROTOCOL_VERSION := 1
const DEFAULT_PORT := 24555
const MAX_PLAYERS := 4
const CONNECT_TIMEOUT := 10.0
## a free-tier relay may need ~a minute to wake up from sleep
const ONLINE_CONNECT_TIMEOUT := 75.0
const PING_INTERVAL := 2.0

enum State { OFFLINE, HOSTING, CONNECTING, CONNECTED }
enum Phase { LOBBY, LOADING, IN_MISSION }

signal state_changed(state: int)
signal lobby_updated
signal connection_failed(reason_key: String)
## Our session ended unexpectedly (host lost, kicked, rejected).
signal session_lost(reason_key: String)
signal peer_joined(peer_id: int)
signal peer_left(peer_id: int, info: Dictionary)
signal quick_chat_received(peer_id: int, message_key: String)

var state: State = State.OFFLINE
var phase: Phase = Phase.LOBBY
var transport: NetTransport = ENetTransport.new()
## peer_id -> {name, level, ready, slot, cosmetics, loadout, perk, ping, player_id}
var players: Dictionary = {}
var selected_mission: StringName = &"power_restoration"
## Set right before the mission scene loads: {mission_id, seed, roster}
var pending_mission: Dictionary = {}
var is_solo := false
var port := DEFAULT_PORT
var host_address := ""
var discovery: LobbyDiscovery
var _connect_timer := -1.0
## Internet play through the relay server (server/relay).
var online := false
var online_code := ""
var _pending_relay_host: RelayMultiplayerPeer
var _registration_sent := false
var _ping_timer := 0.0
var _ping_sent: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	discovery = LobbyDiscovery.new()
	discovery.name = "Discovery"
	add_child(discovery)
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	var p := CmdArgs.value("port")
	if not p.is_empty():
		port = int(p)


# --- public API -----------------------------------------------------------------------

func is_online() -> bool:
	return state == State.HOSTING or state == State.CONNECTED


func is_server() -> bool:
	return multiplayer.is_server()


func local_id() -> int:
	return multiplayer.get_unique_id()


## The peer that sent the RPC currently executing (or ourselves for direct local calls).
func sender_id() -> int:
	var s := multiplayer.get_remote_sender_id()
	return s if s != 0 else multiplayer.get_unique_id()


## Calls a server-side method: directly when we are the server, otherwise via RPC to peer 1.
func send_to_server(node: Node, method: StringName, args: Array = []) -> void:
	if multiplayer.is_server():
		node.callv(method, args)
	elif multiplayer.multiplayer_peer and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
		node.callv(&"rpc_id", [1, method] + args)


func start_solo() -> bool:
	leave(false)
	is_solo = true
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	_set_state(State.HOSTING)
	phase = Phase.LOBBY
	players = {1: _local_info(0)}
	players[1].ready = true
	Log.prefix = "S"
	lobby_updated.emit()
	return true


func host_lobby() -> bool:
	leave(false)
	is_solo = false
	var peer := transport.create_host(port, MAX_PLAYERS - 1)
	if peer == null:
		Log.e("net", "host failed: %s" % transport.last_error)
		connection_failed.emit("NET_ERR_HOST_FAILED")
		return false
	multiplayer.multiplayer_peer = peer
	_set_state(State.HOSTING)
	phase = Phase.LOBBY
	players = {1: _local_info(0)}
	players[1].ready = true
	host_address = JoinCode.best_local_ipv4()
	Log.prefix = "H1"
	Log.i("net", "hosting on %s:%d (code %s)" % [host_address, port, join_code()])
	discovery.start_announcing(_announce_payload())
	lobby_updated.emit()
	return true


func join_lobby(address: String, p_port: int = DEFAULT_PORT) -> bool:
	leave(false)
	is_solo = false
	var peer := transport.create_client(address, p_port)
	if peer == null:
		Log.e("net", "join failed: %s" % transport.last_error)
		connection_failed.emit("NET_ERR_CONNECT_FAILED")
		return false
	multiplayer.multiplayer_peer = peer
	host_address = address
	_set_state(State.CONNECTING)
	_connect_timer = CONNECT_TIMEOUT
	Log.i("net", "connecting to %s:%d" % [address, p_port])
	return true


## Relay server URL: --ns-relay=<url> > player setting > project default.
func relay_url() -> String:
	var cli := CmdArgs.value("relay")
	if not cli.is_empty():
		return cli
	var user := str(Settings.get_value("network", "relay_url")).strip_edges()
	if not user.is_empty():
		return user
	return str(ProjectSettings.get_setting("nightshift/network/relay_url", ""))


## Hosts a lobby reachable from anywhere through the relay (no port forwarding).
## Completes asynchronously: lobby_updated fires once the relay assigned a room code.
func host_online(requested_room: String = "") -> bool:
	leave(false)
	var url := relay_url()
	if url.is_empty():
		connection_failed.emit("NET_ERR_NO_RELAY")
		return false
	var peer := RelayMultiplayerPeer.new()
	if peer.host(url, requested_room if not requested_room.is_empty() else CmdArgs.value("room"), MAX_PLAYERS) != OK:
		connection_failed.emit("NET_ERR_RELAY_UNREACHABLE")
		return false
	# the host peer is only handed to SceneMultiplayer once the room exists
	_pending_relay_host = peer
	online = true
	_set_state(State.CONNECTING)
	_connect_timer = ONLINE_CONNECT_TIMEOUT
	Log.i("net", "opening online lobby via %s" % url)
	return true


func _finish_online_host() -> void:
	var peer := _pending_relay_host
	_pending_relay_host = null
	_connect_timer = -1.0
	multiplayer.multiplayer_peer = peer
	online_code = peer.room
	is_solo = false
	_set_state(State.HOSTING)
	phase = Phase.LOBBY
	players = {1: _local_info(0)}
	players[1].ready = true
	Log.prefix = "H1"
	Log.i("net", "online lobby ready, code %s" % online_code)
	lobby_updated.emit()


## Joins an online lobby by its relay room code (6 characters).
func join_online(code: String) -> bool:
	leave(false)
	var url := relay_url()
	if url.is_empty():
		connection_failed.emit("NET_ERR_NO_RELAY")
		return false
	var peer := RelayMultiplayerPeer.new()
	if peer.join(url, code.strip_edges().to_upper()) != OK:
		connection_failed.emit("NET_ERR_RELAY_UNREACHABLE")
		return false
	peer.relay_error.connect(_on_relay_error)
	multiplayer.multiplayer_peer = peer
	online = true
	online_code = code.strip_edges().to_upper()
	_set_state(State.CONNECTING)
	_connect_timer = ONLINE_CONNECT_TIMEOUT
	Log.i("net", "joining online lobby %s via %s" % [online_code, url])
	return true


static func relay_reason_key(reason: String) -> String:
	match reason:
		"ROOM_NOT_FOUND": return "NET_ERR_ROOM_NOT_FOUND"
		"ROOM_FULL": return "NET_ERR_FULL"
		"BAD_VERSION": return "NET_ERR_VERSION"
		"SERVER_FULL": return "NET_ERR_RELAY_BUSY"
	return "NET_ERR_RELAY_UNREACHABLE"


func _on_relay_error(reason: String) -> void:
	Log.w("net", "relay error: %s -> %s" % [reason, relay_reason_key(reason)])
	if state == State.CONNECTING:
		leave(false)
		connection_failed.emit(relay_reason_key(reason))


## Classifies what the player typed in the join box.
static func classify_join_input(text: String) -> String:
	var t := text.strip_edges().to_upper()
	if t.count(".") == 3:
		return "ip"
	# online relay rooms: 6 letters/digits; LAN codes: XXXXX-XXXXX (10 symbols)
	var alnum := RegEx.create_from_string("^[A-Z0-9]{6}$")
	if alnum.search(t) != null:
		return "online"
	return "lan"


func join_by_code(code: String) -> bool:
	var d := JoinCode.decode(code)
	if d.is_empty():
		connection_failed.emit("NET_ERR_BAD_CODE")
		return false
	return join_lobby(d.ip, d.port)


func join_code() -> String:
	if online:
		return online_code
	return JoinCode.encode(host_address, port) if state == State.HOSTING and not is_solo else ""


## Leaves the current session. `notify` = emit lobby_updated for UI refresh.
func leave(notify: bool = true) -> void:
	discovery.stop()
	if multiplayer.multiplayer_peer and not multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	if _pending_relay_host:
		_pending_relay_host.close()
		_pending_relay_host = null
	players.clear()
	pending_mission.clear()
	phase = Phase.LOBBY
	is_solo = false
	online = false
	online_code = ""
	_registration_sent = false
	_connect_timer = -1.0
	_set_state(State.OFFLINE)
	Log.prefix = ""
	if notify:
		lobby_updated.emit()


func local_info() -> Dictionary:
	return players.get(local_id(), {})


func player_name(peer_id: int) -> String:
	return str(players.get(peer_id, {}).get("name", "?"))


func set_ready(ready: bool) -> void:
	send_to_server(self, &"_srv_set_ready", [ready])


func set_selected_mission(mission_id: StringName) -> void:
	if not is_server():
		return
	if Content.mission(mission_id) == null:
		return
	selected_mission = mission_id
	_broadcast_lobby()


## Re-sends our profile-derived info (cosmetics / loadout changed in lobby).
func refresh_local_info() -> void:
	if state == State.OFFLINE:
		return
	var info := _local_info(int(local_info().get("slot", 0)))
	send_to_server(self, &"_srv_update_info", [info])


func all_ready() -> bool:
	for id in players:
		if not players[id].get("ready", false):
			return false
	return not players.is_empty()


func can_start() -> bool:
	return is_server() and phase == Phase.LOBBY and all_ready() and Content.mission(selected_mission) != null


func start_mission(seed_override: int = -1) -> bool:
	if not can_start():
		return false
	var mission_seed := seed_override
	if mission_seed < 0:
		var forced := CmdArgs.value("seed")
		mission_seed = int(forced) if not forced.is_empty() else randi()
	phase = Phase.LOADING
	discovery.stop()
	Log.i("net", "starting mission %s seed %d with %d players" % [selected_mission, mission_seed, players.size()])
	_rpc_load_mission.rpc(String(selected_mission), mission_seed, players)
	return true


## Host: mission finished -> everybody back to the lobby with readiness reset.
func server_return_to_lobby() -> void:
	if not is_server():
		return
	_rpc_return_to_lobby.rpc()


func send_quick_chat(message_key: String) -> void:
	send_to_server(self, &"_srv_quick_chat", [message_key])


func kick(peer_id: int, reason_key: String = "NET_ERR_KICKED") -> void:
	if not is_server() or peer_id == 1:
		return
	_rpc_rejected.rpc_id(peer_id, reason_key)
	get_tree().create_timer(0.4).timeout.connect(func() -> void:
		if multiplayer.multiplayer_peer:
			multiplayer.multiplayer_peer.disconnect_peer(peer_id))


# --- internals ------------------------------------------------------------------------

func _process(delta: float) -> void:
	if _pending_relay_host:
		_pending_relay_host.poll()
		match _pending_relay_host.get_connection_status():
			MultiplayerPeer.CONNECTION_CONNECTED:
				_finish_online_host()
			MultiplayerPeer.CONNECTION_DISCONNECTED:
				var reason := relay_reason_key(_pending_relay_host.last_error())
				Log.w("net", "online host failed: %s" % _pending_relay_host.last_error())
				leave(false)
				connection_failed.emit(reason)
				return
	if _connect_timer > 0.0:
		_connect_timer -= delta
		if _connect_timer <= 0.0 and state == State.CONNECTING:
			Log.w("net", "connection timed out")
			leave(false)
			connection_failed.emit("NET_ERR_TIMEOUT")
	if state == State.HOSTING and not is_solo:
		_ping_timer += delta
		if _ping_timer >= PING_INTERVAL:
			_ping_timer = 0.0
			var now := Time.get_ticks_msec()
			for id in multiplayer.get_peers():
				_ping_sent[id] = now
				_rpc_ping.rpc_id(id, now)
			if phase == Phase.LOBBY:
				discovery.announce_payload = _announce_payload()
			_broadcast_lobby()


func _set_state(s: State) -> void:
	if state == s:
		return
	state = s
	state_changed.emit(s)


func _local_info(slot: int) -> Dictionary:
	return {
		"name": Profile.display_name(),
		"player_id": str(Profile.data.player_id),
		"level": Profile.level(),
		"ready": false,
		"slot": slot,
		"cosmetics": Profile.cosmetic_payload(),
		"loadout": str(Profile.data.loadout),
		"perk": str(Profile.data.perk),
		"ping": 0,
	}


func _announce_payload() -> Dictionary:
	return {"name": Profile.display_name(), "players": players.size(), "max": MAX_PLAYERS,
		"port": port, "v": PROTOCOL_VERSION, "mission": String(selected_mission), "phase": phase}


## Validates and normalises client-provided info (never trust remote data).
static func sanitize_info(raw: Variant, slot: int) -> Dictionary:
	var d: Dictionary = raw if raw is Dictionary else {}
	var n := str(d.get("name", "Operative")).strip_edges().substr(0, 20)
	if n.length() < 2:
		n = "Operative"
	var cos: Dictionary = {}
	var raw_cos: Variant = d.get("cosmetics", {})
	if raw_cos is Dictionary:
		for k in raw_cos:
			var cid := StringName(str(raw_cos[k]))
			if Content.cosmetic(cid) != null:
				cos[str(k)] = String(cid)
	var loadout := str(d.get("loadout", "standard"))
	if Content.loadout(StringName(loadout)) == null:
		loadout = "standard"
	var perk := str(d.get("perk", ""))
	if not perk.is_empty() and Content.perk(StringName(perk)) == null:
		perk = ""
	return {
		"name": n,
		"player_id": str(d.get("player_id", "")).substr(0, 64),
		"level": clampi(int(d.get("level", 1)), 1, ProgressionRules.MAX_LEVEL),
		"ready": false,
		"slot": slot,
		"cosmetics": cos,
		"loadout": loadout,
		"perk": perk,
		"ping": 0,
	}


func _free_slot() -> int:
	var used: Array[int] = []
	for id in players:
		used.append(int(players[id].slot))
	for s in MAX_PLAYERS:
		if not s in used:
			return s
	return -1


func _broadcast_lobby() -> void:
	if not is_server():
		return
	_rpc_lobby_state.rpc(players, String(selected_mission), phase)


func _on_peer_connected(id: int) -> void:
	if is_server():
		ENetTransport.configure_peer_timeouts(multiplayer.multiplayer_peer, id)
		Log.i("net", "peer %d connected, awaiting registration" % id)


func _on_peer_disconnected(id: int) -> void:
	if not is_server():
		return
	var info: Dictionary = players.get(id, {})
	players.erase(id)
	_ping_sent.erase(id)
	if not info.is_empty():
		Log.i("net", "peer %d (%s) left" % [id, info.get("name", "?")])
		peer_left.emit(id, info)
	_broadcast_lobby()
	lobby_updated.emit()


func _on_connected_to_server() -> void:
	if _registration_sent:
		return
	_registration_sent = true
	_connect_timer = -1.0
	Log.prefix = "C%d" % local_id()
	Log.i("net", "connected as peer %d, registering" % local_id())
	_srv_register.rpc_id(1, PROTOCOL_VERSION, _local_info(0))


func _on_connection_failed() -> void:
	var reason := "NET_ERR_CONNECT_FAILED"
	if multiplayer.multiplayer_peer is RelayMultiplayerPeer:
		reason = relay_reason_key((multiplayer.multiplayer_peer as RelayMultiplayerPeer).last_error())
	Log.w("net", "connection failed (%s)" % reason)
	if state == State.OFFLINE:
		return # already handled (relay error)
	leave(false)
	connection_failed.emit(reason)


func _on_server_disconnected() -> void:
	Log.w("net", "lost connection to host")
	leave(false)
	session_lost.emit("NET_ERR_HOST_LOST")


# --- RPCs: client -> server -----------------------------------------------------------

@rpc("any_peer", "call_remote", "reliable")
func _srv_register(protocol: int, info: Variant) -> void:
	if not is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	var reject := ""
	if protocol != PROTOCOL_VERSION:
		reject = "NET_ERR_VERSION"
	elif phase != Phase.LOBBY:
		reject = "NET_ERR_IN_PROGRESS"
	elif players.size() >= MAX_PLAYERS or _free_slot() == -1:
		reject = "NET_ERR_FULL"
	if not reject.is_empty():
		Log.i("net", "rejecting peer %d: %s" % [id, reject])
		kick(id, reject)
		return
	players[id] = sanitize_info(info, _free_slot())
	Log.i("net", "peer %d registered as '%s' (slot %d)" % [id, players[id].name, players[id].slot])
	_rpc_welcome.rpc_id(id, id)
	_broadcast_lobby()
	peer_joined.emit(id)
	lobby_updated.emit()


@rpc("any_peer", "call_remote", "reliable")
func _srv_set_ready(ready: bool) -> void:
	var id := sender_id()
	if not players.has(id) or phase != Phase.LOBBY:
		return
	players[id].ready = ready if id != 1 else true
	_broadcast_lobby()
	lobby_updated.emit()


@rpc("any_peer", "call_remote", "reliable")
func _srv_update_info(info: Variant) -> void:
	var id := sender_id()
	if not players.has(id):
		return
	var keep_ready: bool = players[id].ready
	var clean := sanitize_info(info, int(players[id].slot))
	clean.ready = keep_ready
	clean.ping = players[id].get("ping", 0)
	players[id] = clean
	_broadcast_lobby()
	lobby_updated.emit()


@rpc("any_peer", "call_remote", "reliable")
func _srv_quick_chat(message_key: String) -> void:
	var id := sender_id()
	if not players.has(id) or not message_key.begins_with("QC_"):
		return
	_rpc_quick_chat.rpc(id, message_key.substr(0, 32))


@rpc("any_peer", "call_remote", "unreliable")
func _srv_pong(sent_ms: int) -> void:
	var id := multiplayer.get_remote_sender_id()
	if players.has(id) and _ping_sent.get(id, -1) == sent_ms:
		players[id].ping = Time.get_ticks_msec() - sent_ms


# --- RPCs: server -> clients ----------------------------------------------------------

@rpc("authority", "call_remote", "reliable")
func _rpc_welcome(_assigned_id: int) -> void:
	_set_state(State.CONNECTED)
	Log.i("net", "joined lobby")


@rpc("authority", "call_remote", "reliable")
func _rpc_rejected(reason_key: String) -> void:
	Log.w("net", "rejected by host: %s" % reason_key)
	leave(false)
	session_lost.emit(reason_key)


@rpc("authority", "call_local", "reliable")
func _rpc_lobby_state(p_players: Dictionary, mission_id: String, p_phase: int) -> void:
	if is_server():
		lobby_updated.emit()
		return
	players = p_players
	selected_mission = StringName(mission_id)
	phase = p_phase as Phase
	lobby_updated.emit()


@rpc("authority", "call_local", "reliable")
func _rpc_load_mission(mission_id: String, mission_seed: int, roster: Dictionary) -> void:
	phase = Phase.LOADING
	pending_mission = {"mission_id": StringName(mission_id), "seed": mission_seed, "roster": roster}
	Log.i("net", "loading mission %s (seed %d)" % [mission_id, mission_seed])
	Router.go_mission()


@rpc("authority", "call_local", "reliable")
func _rpc_return_to_lobby() -> void:
	phase = Phase.LOBBY
	pending_mission.clear()
	for id in players:
		players[id].ready = (id == 1)
	if is_server() and not is_solo:
		discovery.start_announcing(_announce_payload())
	lobby_updated.emit()
	Router.go_lobby()


@rpc("authority", "call_local", "reliable")
func _rpc_quick_chat(peer_id: int, message_key: String) -> void:
	quick_chat_received.emit(peer_id, message_key)


@rpc("authority", "call_remote", "unreliable")
func _rpc_ping(sent_ms: int) -> void:
	_srv_pong.rpc_id(1, sent_ms)
