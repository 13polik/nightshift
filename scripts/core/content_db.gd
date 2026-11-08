extends Node
## Content database (autoload "Content"). Scans data folders for Resource definitions and
## indexes them by id, so adding an item/cosmetic/mission is just adding a .tres file.

const FOLDERS := {
	"items": "res://data/items",
	"enemies": "res://data/enemies",
	"missions": "res://data/missions",
	"cosmetics": "res://data/cosmetics",
	"perks": "res://data/perks",
	"loadouts": "res://data/loadouts",
	"events": "res://data/events",
}

var items: Dictionary = {}
var enemies: Dictionary = {}
var missions: Dictionary = {}
var cosmetics: Dictionary = {}
var perks: Dictionary = {}
var loadouts: Dictionary = {}
var events: Dictionary = {}
var player_stats: PlayerStatsData
var errors: PackedStringArray = PackedStringArray()


func _ready() -> void:
	reload()


func reload() -> void:
	errors.clear()
	for kind: String in FOLDERS:
		var dict: Dictionary = get(kind)
		dict.clear()
		for res in _load_folder(FOLDERS[kind]):
			var rid: StringName = res.get("id")
			if rid == &"":
				errors.append("%s without id: %s" % [kind, res.resource_path])
				continue
			if dict.has(rid):
				errors.append("duplicate %s id %s" % [kind, rid])
			dict[rid] = res
	var stats_path := "res://data/player/default_stats.tres"
	player_stats = load(stats_path) if ResourceLoader.exists(stats_path) else PlayerStatsData.new()
	for it: ItemData in items.values():
		errors.append_array(it.validate())
	for m: MissionData in missions.values():
		errors.append_array(m.validate())
	for err in errors:
		Log.e("content", err)
	Log.i("content", "loaded %d items, %d enemies, %d missions, %d cosmetics, %d perks, %d loadouts, %d events" % [
		items.size(), enemies.size(), missions.size(), cosmetics.size(), perks.size(), loadouts.size(), events.size()])


func item(id: StringName) -> ItemData:
	return items.get(id)


func mission(id: StringName) -> MissionData:
	return missions.get(id)


func cosmetic(id: StringName) -> CosmeticData:
	return cosmetics.get(id)


func perk(id: StringName) -> PerkData:
	return perks.get(id)


func loadout(id: StringName) -> LoadoutOptionData:
	return loadouts.get(id)


func cosmetics_for_slot(slot: int) -> Array[CosmeticData]:
	var out: Array[CosmeticData] = []
	for c: CosmeticData in cosmetics.values():
		if c.slot == slot:
			out.append(c)
	out.sort_custom(func(a: CosmeticData, b: CosmeticData) -> bool:
		return a.unlock_level < b.unlock_level if a.unlock_level != b.unlock_level else String(a.id) < String(b.id))
	return out


func sorted_missions() -> Array[MissionData]:
	var out: Array[MissionData] = []
	for m: MissionData in missions.values():
		out.append(m)
	out.sort_custom(func(a: MissionData, b: MissionData) -> bool: return a.unlock_level < b.unlock_level)
	return out


func _load_folder(path: String) -> Array[Resource]:
	var out: Array[Resource] = []
	var dir := DirAccess.open(path)
	if dir == null:
		return out
	var files := dir.get_files()
	files.sort()
	for f in files:
		# Exported builds list converted resources with a .remap suffix.
		var fname := f.trim_suffix(".remap")
		if not (fname.ends_with(".tres") or fname.ends_with(".res")):
			continue
		var res := load(path.path_join(fname))
		if res == null:
			errors.append("failed to load %s" % path.path_join(fname))
			continue
		out.append(res)
	return out
