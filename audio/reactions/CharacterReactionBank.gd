extends RefCounted
## Human voice recordings; small variation preserves the recorded performance.
static var _cache: Dictionary = {}

static func sound(kind: String) -> AudioStream:
	if _cache.has(kind): return _cache[kind]
	var variants := AudioStreamRandomizer.new()
	variants.playback_mode = AudioStreamRandomizer.PLAYBACK_RANDOM_NO_REPEATS
	variants.random_pitch = 1.02
	variants.random_volume_offset_db = 0.5
	for take in 5:
		variants.add_stream(-1, load("res://audio/reactions/%s_%d.wav" % [kind, take]))
	_cache[kind] = variants
	return variants
