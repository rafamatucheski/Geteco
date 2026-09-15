extends RefCounted

static var _swing: AudioStreamWAV

static func swing() -> AudioStreamWAV:
	if _swing != null: return _swing
	var rng := RandomNumberGenerator.new()
	rng.seed = 914
	var rate := 22050
	var count := int(rate * 0.32)
	var bytes := PackedByteArray()
	bytes.resize(count * 2)
	var low := 0.0
	for i in count:
		var t := float(i) / rate
		low = lerpf(low, rng.randf_range(-1.0, 1.0), 0.18)
		# Air only: the material impact is played only on actual contact.
		var envelope := smoothstep(0.07, 0.22, t) * (1.0 - smoothstep(0.22, 0.32, t))
		bytes.encode_s16(i * 2, int(low * envelope * 29000.0))
	_swing = AudioStreamWAV.new()
	_swing.format = AudioStreamWAV.FORMAT_16_BITS
	_swing.mix_rate = rate
	_swing.data = bytes
	return _swing
