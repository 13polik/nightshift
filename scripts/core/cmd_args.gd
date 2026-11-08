class_name CmdArgs
extends RefCounted
## Development / automation command line flags (after "--" or as user args):
##   --ns-profile=<name>     separate save folder (run several instances on one machine)
##   --ns-host               host a lobby on start
##   --ns-join=<ip>          join a lobby on start
##   --ns-solo=<mission>     start a solo mission immediately
##   --ns-autostart=<n>      host starts the mission when n players are in the lobby
##   --ns-bot                local player is driven by a simple test bot
##   --ns-quit-after=<sec>   quit after N seconds (for automated tests)
##   --ns-seed=<int>         force mission seed
##   --ns-port=<int>         network port


static func all() -> Dictionary:
	var out := {}
	var args := OS.get_cmdline_user_args() + OS.get_cmdline_args()
	for a in args:
		if not a.begins_with("--ns-"):
			continue
		var body := a.substr(5)
		var eq := body.find("=")
		if eq == -1:
			out[body] = "true"
		else:
			out[body.substr(0, eq)] = body.substr(eq + 1)
	return out


static func has(key: String) -> bool:
	return all().has(key)


static func value(key: String, default_value: String = "") -> String:
	return str(all().get(key, default_value))
