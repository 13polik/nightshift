class_name SeededRng
extends RefCounted
## Deterministic random streams derived from one mission seed. Each subsystem asks for its
## own named stream, so adding randomness in one system never changes the results of another
## (important for reproducing a run from its seed).

var seed_value: int = 0
var _streams: Dictionary = {}


func _init(p_seed: int = 0) -> void:
	seed_value = p_seed


func stream(stream_name: String) -> RandomNumberGenerator:
	if not _streams.has(stream_name):
		var r := RandomNumberGenerator.new()
		r.seed = hash("%d:%s" % [seed_value, stream_name])
		r.state = r.seed
		_streams[stream_name] = r
	return _streams[stream_name]


static func shuffle(arr: Array, rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp: Variant = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp


static func pick(arr: Array, rng: RandomNumberGenerator) -> Variant:
	if arr.is_empty():
		return null
	return arr[rng.randi_range(0, arr.size() - 1)]


static func pick_n(arr: Array, n: int, rng: RandomNumberGenerator) -> Array:
	var copy := arr.duplicate()
	shuffle(copy, rng)
	return copy.slice(0, mini(n, copy.size()))
