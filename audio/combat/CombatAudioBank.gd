extends RefCounted
## Cached resources with three non-repeating takes, usable by existing AudioStream APIs.
static var _cache: Dictionary = {}

static func sound(kind: String) -> AudioStream:
	if _cache.has(kind):
		return _cache[kind]
	var variants := AudioStreamRandomizer.new()
	variants.playback_mode = AudioStreamRandomizer.PLAYBACK_RANDOM_NO_REPEATS
	variants.random_pitch = 1.018
	variants.random_volume_offset_db = 0.4
	for take in 3:
		var sample := load("res://audio/combat/%s_%d.wav" % [kind, take]) as AudioStream
		variants.add_stream(-1, sample)
	_cache[kind] = variants
	return variants
