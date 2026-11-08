class_name RelayMultiplayerPeer
extends MultiplayerPeerExtension
## MultiplayerPeer that tunnels Godot's high-level multiplayer through the NIGHT SHIFT relay
## server (server/relay). Every player connects OUT over WebSocket (wss:// on the
## internet), so it works across home routers, mobile carriers and firewalls without port
## forwarding. The host is still the authoritative server (peer 1); the relay only
## forwards bytes. See server/relay/relay_server.gd for the wire protocol.

signal room_ready(code: String)
signal relay_error(reason: String)

const PROTOCOL := 1
const HEADER := 6
const KEEPALIVE := 15.0

var ws := WebSocketPeer.new()
var url := ""
var hosting := false
var room := ""
var _unique_id := 0
var _status := MultiplayerPeer.CONNECTION_DISCONNECTED
var _target := 0
var _channel := 0
var _mode := MultiplayerPeer.TRANSFER_MODE_RELIABLE
var _refuse := false
var _incoming: Array = [] # [{from, channel, mode, data}]
var _sent_hello := false
var _peers: Dictionary = {}
var _keepalive_t := 0.0
var _last_error := ""
var _hello: Dictionary = {}


## Starts hosting a room. `requested_room` may be empty (server picks a code).
func host(relay_url: String, requested_room: String = "", max_players: int = 4) -> Error:
	hosting = true
	return _open(relay_url, {"op": "host", "v": PROTOCOL, "room": requested_room, "max": max_players})


func join(relay_url: String, code: String) -> Error:
	hosting = false
	return _open(relay_url, {"op": "join", "v": PROTOCOL, "room": code})


func _open(relay_url: String, hello: Dictionary) -> Error:
	url = relay_url
	_hello = hello
	ws.inbound_buffer_size = 2 * 1024 * 1024
	ws.outbound_buffer_size = 2 * 1024 * 1024
	ws.max_queued_packets = 8192
	var tls: TLSOptions = TLSOptions.client() if url.begins_with("wss://") else null
	var err := ws.connect_to_url(url, tls)
	if err != OK:
		_last_error = "CONNECT_FAILED"
		return err
	_status = MultiplayerPeer.CONNECTION_CONNECTING
	return OK


func last_error() -> String:
	return _last_error


# --- MultiplayerPeerExtension ---------------------------------------------------------

func _poll() -> void:
	ws.poll()
	var st := ws.get_ready_state()
	if st == WebSocketPeer.STATE_OPEN and not _sent_hello:
		_sent_hello = true
		ws.send_text(JSON.stringify(_hello))
	if st == WebSocketPeer.STATE_CLOSED:
		if _status != MultiplayerPeer.CONNECTION_DISCONNECTED:
			# the relay puts the failure reason in the close frame (always delivered)
			if _last_error.is_empty() and not ws.get_close_reason().is_empty() and ws.get_close_code() >= 4000:
				_last_error = ws.get_close_reason()
				relay_error.emit(_last_error)
			if _last_error.is_empty():
				_last_error = "CONNECTION_LOST" if _status == MultiplayerPeer.CONNECTION_CONNECTED else "CONNECT_FAILED"
			_shutdown()
		return
	while ws.get_available_packet_count() > 0:
		var pkt := ws.get_packet()
		if ws.was_string_packet():
			_control(pkt.get_string_from_utf8())
		elif pkt.size() >= HEADER and _status == MultiplayerPeer.CONNECTION_CONNECTED:
			_incoming.append({"from": pkt.decode_s32(0), "channel": pkt[4], "mode": pkt[5], "data": pkt.slice(HEADER)})
	if _status == MultiplayerPeer.CONNECTION_CONNECTED:
		var t := Time.get_ticks_msec() / 1000.0
		if t - _keepalive_t >= KEEPALIVE:
			_keepalive_t = t
			ws.send_text(JSON.stringify({"op": "ping", "t": Time.get_ticks_msec()}))


func _control(text: String) -> void:
	var msg: Variant = JSON.parse_string(text)
	if not msg is Dictionary:
		return
	match str(msg.get("op", "")):
		"hosted", "joined":
			_unique_id = int(msg.get("id", 0))
			room = str(msg.get("room", ""))
			_status = MultiplayerPeer.CONNECTION_CONNECTED
			room_ready.emit(room)
		"peer_connected":
			var id := int(msg.get("id", 0))
			if id > 0 and not _peers.has(id):
				_peers[id] = true
				peer_connected.emit(id)
		"peer_disconnected":
			var id := int(msg.get("id", 0))
			if _peers.erase(id):
				peer_disconnected.emit(id)
		"error":
			_last_error = str(msg.get("reason", "RELAY_ERROR"))
			relay_error.emit(_last_error)


func _shutdown() -> void:
	var was := _peers.keys()
	_peers.clear()
	_incoming.clear()
	_status = MultiplayerPeer.CONNECTION_DISCONNECTED
	for id in was:
		peer_disconnected.emit(id)


func _get_available_packet_count() -> int:
	return _incoming.size()


func _get_max_packet_size() -> int:
	return 1 << 20


func _get_packet_script() -> PackedByteArray:
	if _incoming.is_empty():
		return PackedByteArray()
	return (_incoming.pop_front() as Dictionary).data


func _put_packet_script(p_buffer: PackedByteArray) -> Error:
	if _status != MultiplayerPeer.CONNECTION_CONNECTED:
		return ERR_UNCONFIGURED
	var pkt := PackedByteArray()
	pkt.resize(HEADER)
	pkt.encode_s32(0, _target)
	pkt[4] = _channel
	pkt[5] = _mode
	pkt.append_array(p_buffer)
	return ws.send(pkt)


func _get_packet_peer() -> int:
	return int(_incoming[0].from) if not _incoming.is_empty() else 0


func _get_packet_channel() -> int:
	return int(_incoming[0].channel) if not _incoming.is_empty() else 0


func _get_packet_mode() -> MultiplayerPeer.TransferMode:
	return (int(_incoming[0].mode) if not _incoming.is_empty() else 0) as MultiplayerPeer.TransferMode


func _set_transfer_channel(p_channel: int) -> void:
	_channel = p_channel


func _get_transfer_channel() -> int:
	return _channel


func _set_transfer_mode(p_mode: MultiplayerPeer.TransferMode) -> void:
	_mode = p_mode


func _get_transfer_mode() -> MultiplayerPeer.TransferMode:
	return _mode


func _set_target_peer(p_peer: int) -> void:
	_target = p_peer


func _is_server() -> bool:
	return hosting


func _is_server_relay_supported() -> bool:
	return true


func _get_unique_id() -> int:
	return _unique_id


func _get_connection_status() -> MultiplayerPeer.ConnectionStatus:
	return _status


func _set_refuse_new_connections(p_enable: bool) -> void:
	_refuse = p_enable


func _is_refusing_new_connections() -> bool:
	return _refuse


func _disconnect_peer(p_peer: int, _p_force: bool) -> void:
	if hosting and _status == MultiplayerPeer.CONNECTION_CONNECTED:
		ws.send_text(JSON.stringify({"op": "kick", "id": p_peer}))


func _close() -> void:
	ws.close()
	_shutdown()
