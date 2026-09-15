extends RefCounted

# Four cached, short samples: air movement and three dull, textured impacts.
static var _cache: Dictionary = {}

static func swing() -> AudioStreamWAV:
	return _sample(-1)

static func impact(variant: int) -> AudioStreamWAV:
	return _sample(posmod(variant, 3))

static func _sample(kind: int) -> AudioStreamWAV:
	if _cache.has(kind): return _cache[kind]
	var rng := RandomNumberGenerator.new()
	rng.seed = 913 + kind
	var data := PackedByteArray()
	var rate := 22050
	var count := int(rate * (0.10 if kind < 0 else 0.16))
	data.resize(count * 2)
	var low := 0.0
	var soft := 0.0
	for i in count:
		var t := float(i) / rate
		var noise := rng.randf_range(-1.0, 1.0)
		low = lerpf(low, noise, 0.12)
		soft = lerpf(soft, low, 0.12)
		var attack := minf(t / 0.008, 1.0)
		var sample := soft * pow(sin(PI * float(i) / count), 2.0) * 0.75
		if kind >= 0:
			sample = (sin(TAU * (105.0 + kind * 9.0) * t) * 0.42 + soft * 0.8) * exp(-t * 44.0)
			sample *= 1.0 - smoothstep(0.11, 0.16, t)
		data.encode_s16(i * 2, int(clampf(sample * attack, -0.95, 0.95) * 32767))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.data = data
	_cache[kind] = stream
	return stream
