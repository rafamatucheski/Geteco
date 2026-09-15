extends RefCounted
## Cached contact textures: separate continuous tire noise and individual impacts.
static var _cache: Dictionary = {}
const PROFILES := {
	"concrete": [0.22, 0.12, 95.0], "asphalt": [0.16, 0.28, 70.0],
	"dirt": [0.08, 0.08, 55.0], "gravel": [0.48, 0.65, 160.0],
	"grass": [0.12, 0.16, 45.0], "snow": [0.06, 0.38, 35.0],
	"metal": [0.35, 0.12, 640.0], "wood": [0.14, 0.06, 180.0],
	"tile": [0.4, 0.1, 320.0], "water": [0.25, 0.4, 85.0]
}

static func sound(surface: String, rolling: bool, variation: int = 0) -> AudioStreamWAV:
	var key := "%s_%s_%d" % [surface, rolling, posmod(variation, 4)]
	if _cache.has(key): return _cache[key]
	var wet := surface == "wet" or surface.ends_with("_wet") or surface == "water"
	var base := surface.trim_suffix("_wet")
	var profile: Array = PROFILES.get(base, PROFILES.concrete)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key)
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = 22050
	var count := 22050 if rolling else 6615
	var bytes := PackedByteArray()
	bytes.resize((count + 8) * 2)
	var low := 0.0
	for i in count:
		var t := float(i) / 22050.0
		var noise := rng.randf_range(-1.0, 1.0)
		low = lerpf(low, noise, float(profile[0]))
		var grit := noise * float(profile[1]) * pow(maxf(0.0, sin(t * TAU * 37.0)), 8)
		var value := low * 0.65 + grit
		if base in ["metal", "wood", "tile"]:
			value += sin(TAU * float(profile[2]) * t) * (0.12 if rolling else 0.3)
		if wet: value = value * 0.65 + noise * 0.22 + low * 0.3
		var envelope := 1.0
		if not rolling: envelope = (1.0 - exp(-t * 450.0)) * exp(-t * 22.0)
		# Short fade at both boundaries prevents discontinuities in the loop.
		var edge := minf(1.0, minf(float(i), float(count - 1 - i)) / 110.0)
		bytes.encode_s16(i * 2, int(clampf(value * envelope * edge, -1.0, 1.0) * 28000.0))
	if rolling:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_end = count
		for i in 8: bytes.encode_s16((count + i) * 2, bytes.decode_s16(i * 2))
	stream.data = bytes
	_cache[key] = stream
	return stream
