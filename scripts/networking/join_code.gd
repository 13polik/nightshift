class_name JoinCode
extends RefCounted
## Short shareable lobby codes. The current code encodes the host's IPv4 address + port
## (works on LAN / VPN / port-forwarded hosts). When a matchmaking backend is added the code
## becomes an opaque lobby id resolved by the backend - callers only use encode/decode.

const ALPHABET := "0123456789ABCDEFGHJKMNPQRSTVWXYZ" # Crockford base32 (no I L O U)


static func encode(ip: String, port: int) -> String:
	var parts := ip.split(".")
	if parts.size() != 4:
		return ""
	var v := 0
	for p in parts:
		v = (v << 8) | (int(p) & 255)
	v = (v << 16) | (port & 0xFFFF)
	var s := ""
	for i in 10:
		s = ALPHABET[v & 31] + s
		v >>= 5
	return s.substr(0, 5) + "-" + s.substr(5)


static func decode(code: String) -> Dictionary:
	var clean := code.to_upper().replace("-", "").replace(" ", "").replace("O", "0").replace("I", "1").replace("L", "1")
	if clean.length() != 10:
		return {}
	var v := 0
	for ch in clean:
		var idx := ALPHABET.find(ch)
		if idx == -1:
			return {}
		v = (v << 5) | idx
	var port := v & 0xFFFF
	var ipv := v >> 16
	var ip := "%d.%d.%d.%d" % [(ipv >> 24) & 255, (ipv >> 16) & 255, (ipv >> 8) & 255, ipv & 255]
	if port == 0:
		return {}
	return {"ip": ip, "port": port}


static func best_local_ipv4() -> String:
	var candidates: Array[String] = []
	for a in IP.get_local_addresses():
		if a.count(".") != 3 or a.begins_with("127.") or a.begins_with("169.254."):
			continue
		candidates.append(a)
	for prefix in ["192.168.", "10.", "172."]:
		for c in candidates:
			if c.begins_with(prefix):
				return c
	return candidates[0] if not candidates.is_empty() else "127.0.0.1"
