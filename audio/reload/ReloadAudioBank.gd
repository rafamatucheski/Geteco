extends RefCounted
## Small, cached Foley palette shared by manual and automatic reloads.
const WEAPONS := ["pistol", "magnum", "smg", "shotgun", "sawed_off", "ak47", "m4a1", "hunting_rifle", "rpg", "flamethrower", "grenade"]
const TAKES := 3
static var _cache: Dictionary = {}
static var _last_take: Dictionary = {}

static func next_sample(weapon_id: String) -> AudioStream:
	var variants := sound(weapon_id) as AudioStreamRandomizer
	if variants == null: return null
	var last := int(_last_take.get(weapon_id, -1))
	var take := randi_range(0, TAKES - 1) if last < 0 else (last + randi_range(1, TAKES - 1)) % TAKES
	_last_take[weapon_id] = take
	# Select the actual WAV before starting: its duration drives the reload pose.
	return variants.get_stream(take)

static func sound(weapon_id: String) -> AudioStream:
	if weapon_id not in WEAPONS: return null
	if _cache.has(weapon_id): return _cache[weapon_id]
	var variants := AudioStreamRandomizer.new()
	variants.playback_mode = AudioStreamRandomizer.PLAYBACK_RANDOM_NO_REPEATS
	variants.random_pitch = 1.02
	variants.random_volume_offset_db = 0.4
	for take in TAKES:
		var sample := load("res://audio/reload/%s_%d.wav" % [weapon_id, take]) as AudioStream
		variants.add_stream(-1, sample)
	_cache[weapon_id] = variants
	return variants
