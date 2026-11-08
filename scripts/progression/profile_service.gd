extends Node
## Persistent player profile (autoload "Profile"): identity, progression, currency,
## unlocks, equipped cosmetics, loadout and lifetime statistics.

const DOC := "profile"
const VERSION := 1

const DEFAULTS := {
	"player_id": "",
	"display_name": "",
	"total_xp": 0,
	"currency": 0,
	"unlocked": [],
	"equipped": {},
	"loadout": "standard",
	"perk": "",
	"profile_icon": "icon_default",
	"stats": {
		"missions_played": 0,
		"missions_won": 0,
		"extractions": 0,
		"deaths": 0,
		"revives": 0,
		"objectives": 0,
		"play_seconds": 0,
	},
	"seen_tutorial": false,
	"seen_intro": false,
}

var data: Dictionary = {}
var entitlements: EntitlementProvider = EntitlementProvider.new()


func _ready() -> void:
	data = SaveManager.load_document(DOC, VERSION, DEFAULTS)
	var dirty := false
	if str(data.player_id).is_empty():
		data.player_id = _generate_id()
		dirty = true
	if str(data.display_name).is_empty():
		data.display_name = "Operative-%s" % str(data.player_id).substr(0, 4).to_upper()
		dirty = true
	if _grant_default_and_level_unlocks():
		dirty = true
	_ensure_equipped_defaults()
	if dirty:
		save()


func save() -> void:
	SaveManager.save_document(DOC, VERSION, data)
	Events.profile_changed.emit()


func display_name() -> String:
	return str(data.display_name)


func set_display_name(n: String) -> void:
	n = n.strip_edges().substr(0, 20)
	if n.length() < 2:
		return
	data.display_name = n
	save()


func level_info() -> Dictionary:
	return ProgressionRules.level_for_total_xp(int(data.total_xp))


func level() -> int:
	return int(level_info().level)


func currency() -> int:
	return int(data.currency)


func is_unlocked(c: CosmeticData) -> bool:
	if c == null:
		return false
	if c.is_default():
		return true
	if not c.store_sku.is_empty() and entitlements.owns_sku(c.store_sku):
		return true
	return String(c.id) in data.unlocked


func can_purchase(c: CosmeticData) -> bool:
	return c != null and c.source == CosmeticData.Source.CURRENCY and not is_unlocked(c) \
		and level() >= c.unlock_level and currency() >= c.price


func purchase(c: CosmeticData) -> bool:
	if not can_purchase(c):
		return false
	data.currency = currency() - c.price
	(data.unlocked as Array).append(String(c.id))
	save()
	return true


func equip(c: CosmeticData) -> bool:
	if not is_unlocked(c):
		return false
	data.equipped[str(c.slot)] = String(c.id)
	save()
	return true


func equipped_id(slot: int) -> StringName:
	return StringName(str(data.equipped.get(str(slot), "")))


## Cosmetic loadout shared with other players in the lobby (ids only, validated remotely).
func cosmetic_payload() -> Dictionary:
	var out := {}
	for slot in CosmeticData.Slot.values():
		var cid := equipped_id(slot)
		if cid != &"":
			out[str(slot)] = String(cid)
	return out


func is_perk_unlocked(p: PerkData) -> bool:
	return p != null and level() >= p.unlock_level


func is_loadout_unlocked(l: LoadoutOptionData) -> bool:
	return l != null and level() >= l.unlock_level


func set_loadout(id: StringName) -> void:
	var l := Content.loadout(id)
	if is_loadout_unlocked(l):
		data.loadout = String(id)
		save()


func set_perk(id: StringName) -> void:
	if id == &"":
		data.perk = ""
		save()
		return
	var p := Content.perk(id)
	if is_perk_unlocked(p):
		data.perk = String(id)
		save()


## Applies host-computed rewards. Returns a summary for the results screen.
func apply_mission_rewards(reward: Dictionary, result: Dictionary) -> Dictionary:
	var before := level_info()
	data.total_xp = int(data.total_xp) + int(reward.get("xp", 0))
	data.currency = currency() + int(reward.get("currency", 0))
	var s: Dictionary = data.stats
	s.missions_played = int(s.missions_played) + 1
	if result.get("success", false):
		s.missions_won = int(s.missions_won) + 1
	if result.get("extracted", false):
		s.extractions = int(s.extractions) + 1
	if result.get("died", false):
		s.deaths = int(s.deaths) + 1
	s.revives = int(s.revives) + int(result.get("revives", 0))
	s.objectives = int(s.objectives) + int(result.get("objectives_completed", 0))
	s.play_seconds = int(s.play_seconds) + int(result.get("duration", 0))
	var newly := _grant_default_and_level_unlocks_list()
	save()
	var after := level_info()
	return {"level_before": before.level, "level_after": after.level, "unlocks": newly,
		"xp": reward.get("xp", 0), "currency": reward.get("currency", 0)}


func _grant_default_and_level_unlocks() -> bool:
	return not _grant_default_and_level_unlocks_list().is_empty()


func _grant_default_and_level_unlocks_list() -> Array[String]:
	var granted: Array[String] = []
	var lvl := level()
	for c: CosmeticData in Content.cosmetics.values():
		if c.source == CosmeticData.Source.LEVEL and lvl >= c.unlock_level and not String(c.id) in data.unlocked:
			(data.unlocked as Array).append(String(c.id))
			granted.append(String(c.id))
	return granted


func _ensure_equipped_defaults() -> void:
	for slot in CosmeticData.Slot.values():
		var cur := Content.cosmetic(equipped_id(slot))
		if cur != null and is_unlocked(cur):
			continue
		for c in Content.cosmetics_for_slot(slot):
			if c.is_default():
				data.equipped[str(slot)] = String(c.id)
				break


static func _generate_id() -> String:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var s := ""
	for i in 16:
		s += "%02x" % rng.randi_range(0, 255)
	return s
