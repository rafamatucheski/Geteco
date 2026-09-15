extends RefCounted
## Cached resources with five non-repeating takes, usable by existing AudioStream APIs.
const TAKES := 5
static var _cache: Dictionary = {}

const IMPACT_SAMPLES: Dictionary = {
	"concrete": [
		preload("res://audio/combat/concrete_0.wav"),
		preload("res://audio/combat/concrete_1.wav"),
		preload("res://audio/combat/concrete_2.wav"),
		preload("res://audio/combat/concrete_3.wav"),
		preload("res://audio/combat/concrete_4.wav"),
	],
	"flesh": [
		preload("res://audio/combat/flesh_0.wav"),
		preload("res://audio/combat/flesh_1.wav"),
		preload("res://audio/combat/flesh_2.wav"),
		preload("res://audio/combat/flesh_3.wav"),
		preload("res://audio/combat/flesh_4.wav"),
	],
	"glass": [
		preload("res://audio/combat/glass_0.wav"),
		preload("res://audio/combat/glass_1.wav"),
		preload("res://audio/combat/glass_2.wav"),
		preload("res://audio/combat/glass_3.wav"),
		preload("res://audio/combat/glass_4.wav"),
	],
	"metal": [
		preload("res://audio/combat/metal_0.wav"),
		preload("res://audio/combat/metal_1.wav"),
		preload("res://audio/combat/metal_2.wav"),
		preload("res://audio/combat/metal_3.wav"),
		preload("res://audio/combat/metal_4.wav"),
	],
	"wood": [
		preload("res://audio/combat/wood_0.wav"),
		preload("res://audio/combat/wood_1.wav"),
		preload("res://audio/combat/wood_2.wav"),
		preload("res://audio/combat/wood_3.wav"),
		preload("res://audio/combat/wood_4.wav"),
	],
}

static func prepare_impact_palette() -> void:
	for material: String in IMPACT_SAMPLES.keys():
		sound(material)

static func sound(kind: String) -> AudioStream:
	if _cache.has(kind):
		return _cache[kind]
	var variants := AudioStreamRandomizer.new()
	variants.playback_mode = AudioStreamRandomizer.PLAYBACK_RANDOM_NO_REPEATS
	variants.random_pitch = 1.035
	variants.random_volume_offset_db = 0.65
	if IMPACT_SAMPLES.has(kind):
		var takes: Array = IMPACT_SAMPLES[kind]
		for sample in takes:
			variants.add_stream(-1, sample as AudioStream)
	else:
		for take in TAKES:
			var sample := load("res://audio/combat/%s_%d.wav" % [kind, take]) as AudioStream
			variants.add_stream(-1, sample)
	_cache[kind] = variants
	return variants
