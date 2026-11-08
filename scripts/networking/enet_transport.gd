class_name ENetTransport
extends NetTransport
## UDP transport using ENet (listen server: the host is the authoritative server).

const CHANNELS := 4
const TIMEOUT_LIMIT_MS := 8000
const TIMEOUT_MIN_MS := 3000
const TIMEOUT_MAX_MS := 12000


func create_host(port: int, max_clients: int) -> MultiplayerPeer:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, max_clients, CHANNELS)
	if err != OK:
		last_error = "create_server(%d): %s" % [port, error_string(err)]
		return null
	peer.host.compress(ENetConnection.COMPRESS_RANGE_CODER)
	return peer


func create_client(address: String, port: int) -> MultiplayerPeer:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port, CHANNELS)
	if err != OK:
		last_error = "create_client(%s:%d): %s" % [address, port, error_string(err)]
		return null
	peer.host.compress(ENetConnection.COMPRESS_RANGE_CODER)
	return peer


static func configure_peer_timeouts(peer: MultiplayerPeer, peer_id: int) -> void:
	if peer is ENetMultiplayerPeer:
		var p := (peer as ENetMultiplayerPeer).get_peer(peer_id)
		if p:
			p.set_timeout(TIMEOUT_LIMIT_MS, TIMEOUT_MIN_MS, TIMEOUT_MAX_MS)


func kick(peer: MultiplayerPeer, peer_id: int) -> void:
	if peer is ENetMultiplayerPeer:
		peer.disconnect_peer(peer_id)


func describe() -> String:
	return "enet"
