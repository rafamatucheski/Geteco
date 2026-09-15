extends RefCounted
const MATERIALS := ["concrete", "wet", "grass", "grass_wet", "metal", "metal_wet", "tile", "wood"]
static var _cache: Dictionary = {}

static func sound(surface: String, variation: int) -> AudioStreamWAV:
	if surface == "water":
		var key := "water_%d" % posmod(variation, 4)
		if not _cache.has(key): _cache[key] = _water_step(posmod(variation, 4))
		return _cache[key]
	if surface in ["rain", "puddle"]: surface = "wet"
	if surface not in MATERIALS and surface in ["asphalt", "asphalt_wet", "dirt", "dirt_wet", "gravel", "gravel_wet", "snow", "snow_wet", "wood_wet", "tile_wet"]:
		return preload("res://audio/SurfaceContactAudio.gd").sound(surface, false, variation)
	if surface not in MATERIALS: surface = "concrete"
	var key := "%s_%d" % [surface, posmod(variation, 4)]
	if not _cache.has(key):
		_cache[key] = load("res://audio/footsteps/%s.wav" % key) as AudioStreamWAV
	return _cache[key]

static func _water_step(variation: int) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 9137 + variation * 101
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = 22050
	var samples := 6615
	var bytes := PackedByteArray()
	bytes.resize(samples * 2)
	var low := 0.0
	for i in samples:
		var time := float(i) / stream.mix_rate
		var noise := rng.randf_range(-1.0, 1.0)
		low = lerpf(low, noise, 0.23)
		var splash := (low * 0.8 + noise * 0.2) * (1.0-exp(-time*180.0)) * exp(-time*18.0)
		var droplets := sin(TAU * (260.0*time - 250.0*time*time)) * exp(-time*28.0) * 0.14
		var second := maxf(0.0, time-0.075)
		if time > 0.075: splash += low * sin(minf(second*35.0, PI)) * exp(-second*24.0) * 0.4
		bytes.encode_s16(i*2, int(clampf(splash+droplets, -1.0, 1.0)*28000))
	stream.data = bytes
	return stream
