class_name LobbyDiscovery
extends Node
## LAN lobby discovery via UDP broadcast. Hosts announce once per second; browsing clients
## collect announcements. (iOS needs NSLocalNetworkUsageDescription; Android needs the
## multicast lock permission - see export presets.)

const PORT := 24556
const MAGIC := "NSHIFT"
const STALE_AFTER := 4.0

signal lobbies_changed

var announcing := false
var listening := false
var announce_payload: Dictionary = {}
var lobbies: Dictionary = {} # "ip:port" -> {info..., last_seen}
var _udp := PacketPeerUDP.new()
var _timer := 0.0


func start_announcing(payload: Dictionary) -> void:
	stop()
	announce_payload = payload
	_udp = PacketPeerUDP.new()
	_udp.set_broadcast_enabled(true)
	var err := _udp.set_dest_address("255.255.255.255", PORT)
	if err != OK:
		Log.w("discovery", "broadcast unavailable: %s" % error_string(err))
		return
	announcing = true


func start_listening() -> void:
	stop()
	_udp = PacketPeerUDP.new()
	var err := _udp.bind(PORT)
	if err != OK:
		Log.w("discovery", "cannot listen on %d: %s" % [PORT, error_string(err)])
		return
	listening = true
	lobbies.clear()


func stop() -> void:
	if announcing or listening:
		_udp.close()
	announcing = false
	listening = false


func _process(delta: float) -> void:
	_timer += delta
	if announcing and _timer >= 1.0:
		_timer = 0.0
		var msg := JSON.stringify({"magic": MAGIC, "info": announce_payload})
		_udp.put_packet(msg.to_utf8_buffer())
	if listening:
		var changed := false
		while _udp.get_available_packet_count() > 0:
			var pkt := _udp.get_packet().get_string_from_utf8()
			var ip := _udp.get_packet_ip()
			var parsed: Variant = JSON.parse_string(pkt)
			if parsed is Dictionary and parsed.get("magic") == MAGIC and parsed.get("info") is Dictionary:
				var info: Dictionary = parsed.info
				info["ip"] = ip
				info["last_seen"] = Time.get_ticks_msec() / 1000.0
				lobbies["%s:%s" % [ip, info.get("port", 0)]] = info
				changed = true
		var now := Time.get_ticks_msec() / 1000.0
		for k in lobbies.keys():
			if now - float(lobbies[k].last_seen) > STALE_AFTER:
				lobbies.erase(k)
				changed = true
		if changed:
			lobbies_changed.emit()


func _exit_tree() -> void:
	stop()
