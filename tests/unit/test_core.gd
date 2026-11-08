extends TestCase
## Core systems: RNG determinism, save robustness, progression math, join codes.


func test_seeded_rng_is_deterministic_and_stream_independent() -> void:
	var a := SeededRng.new(42)
	var b := SeededRng.new(42)
	var seq_a: Array = []
	var seq_b: Array = []
	for i in 10:
		seq_a.append(a.stream("loot").randi())
		seq_b.append(b.stream("loot").randi())
	eq(seq_a, seq_b, "same seed + stream must give same sequence")
	var c := SeededRng.new(42)
	c.stream("events").randi()  # consuming another stream must not affect "loot"
	eq(c.stream("loot").randi(), seq_a[0], "streams must be independent")
	check(SeededRng.new(43).stream("loot").randi() != seq_a[0], "different seeds should differ")


func test_save_roundtrip_backup_and_corruption() -> void:
	var backend := LocalSaveBackend.new("user://test_saves")
	backend.remove("doc")
	var old: SaveBackend = SaveManager.backend
	SaveManager.use_backend(backend)
	var defaults := {"a": 1, "b": {"c": "x", "d": 2.5}, "list": []}
	eq(SaveManager.load_document("doc", 1, defaults), defaults, "missing doc returns defaults")
	SaveManager.save_document("doc", 1, {"a": 5, "b": {"c": "y", "d": 1.0}, "list": [1, 2]})
	var loaded := SaveManager.load_document("doc", 1, defaults)
	eq(int(loaded.a), 5, "round trip int")
	eq(typeof(loaded.a), TYPE_INT, "ints restored as ints")
	eq(loaded.b.c, "y", "nested value")
	# second save creates a backup of the first
	SaveManager.save_document("doc", 1, {"a": 7, "b": {"c": "z", "d": 1.0}, "list": []})
	# corrupt the main file -> must fall back to the backup (a == 5)
	var f := FileAccess.open("user://test_saves/doc.json", FileAccess.WRITE)
	f.store_string("{ this is not json")
	f.close()
	var recovered := SaveManager.load_document("doc", 1, defaults)
	eq(int(recovered.a), 5, "corrupt file recovers from backup")
	# tampered checksum + no usable backup -> defaults, never a crash
	backend.remove("doc")
	f = FileAccess.open("user://test_saves/doc.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"format": 1, "doc": "doc", "version": 1, "checksum": "bad", "data": {"a": 99}}))
	f.close()
	eq(int(SaveManager.load_document("doc", 1, defaults).a), 1, "tampered file falls back to defaults")
	backend.remove("doc")
	SaveManager.use_backend(old)


func test_merge_defaults_rejects_wrong_types() -> void:
	var merged := SaveManager.merge_defaults({"vol": 1.0, "name": "x", "n": 3}, {"vol": "loud", "name": "y", "n": 4.0, "extra": true})
	eq(merged.vol, 1.0, "wrong type keeps default")
	eq(merged.name, "y", "valid string kept")
	eq(typeof(merged.n), TYPE_INT, "float coerced back to int")
	check(merged.has("extra"), "unknown keys are preserved for forward compatibility")


func test_progression_curve_and_rewards() -> void:
	var prev := 0
	for lvl in range(1, 20):
		var need := ProgressionRules.xp_to_next(lvl)
		check(need > prev, "xp curve must increase")
		prev = need
	eq(ProgressionRules.level_for_total_xp(0).level, 1, "start at level 1")
	eq(ProgressionRules.level_for_total_xp(ProgressionRules.xp_to_next(1)).level, 2, "exact threshold levels up")
	var rd := RewardData.new()
	var win := ProgressionRules.compute_rewards(rd, {"success": true, "extracted": true, "survived": true, "objectives_xp": 500})
	var lose := ProgressionRules.compute_rewards(rd, {"success": false, "objectives_xp": 500})
	check(win.xp > lose.xp and lose.xp > 0, "failure still grants reduced progress")


func test_join_code_roundtrip() -> void:
	for ip in ["192.168.1.23", "10.0.0.5", "172.16.254.1"]:
		var code := JoinCode.encode(ip, 24555)
		var d := JoinCode.decode(code)
		eq(d.get("ip"), ip, "ip roundtrip for %s" % code)
		eq(d.get("port"), 24555, "port roundtrip")
	eq(JoinCode.decode("not-a-code"), {}, "invalid code rejected")
	eq(JoinCode.decode(JoinCode.encode("192.168.1.23", 24555).to_lower()).get("ip"), "192.168.1.23", "codes are case-insensitive")


func test_sanitize_remote_player_info() -> void:
	var clean := Net.sanitize_info({"name": "x".repeat(80), "level": 9999, "cosmetics": {"0": "does_not_exist", "1": "helmet_cyan"}, "loadout": "hack"}, 2)
	check(str(clean.name).length() <= 20, "name length clamped")
	eq(int(clean.level), ProgressionRules.MAX_LEVEL, "level clamped")
	check(not clean.cosmetics.has("0"), "unknown cosmetic dropped")
	eq(clean.loadout, "standard", "unknown loadout replaced")
	eq(int(clean.slot), 2, "slot assigned by server")
	var garbage := Net.sanitize_info("garbage", 0)
	eq(garbage.name, "Operative", "non-dictionary info handled")
