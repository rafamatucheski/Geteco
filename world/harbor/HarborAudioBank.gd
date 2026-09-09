extends RefCounted
## Small deterministic PCM palette. Built once per session, never per frame.
static var cache: Dictionary = {}
const RATE := 22050

static func sound(kind: String) -> AudioStreamWAV:
	if cache.has(kind):
		return cache[kind]
	var looped := kind in ["water", "terminal", "workshop"]
	var duration := 6.0 if looped else 2.6
	var count := int(RATE * duration)
	var bytes := PackedByteArray()
	bytes.resize(count * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(kind)
	var low := 0.0
	for i in count:
		var t := float(i) / RATE
		var noise := rng.randf_range(-1.0, 1.0)
		low = lerpf(low, noise, 0.035)
		var value := 0.0
		match kind:
			"voice_dante", "voice_maciota":
				# Stylized syllables, deliberately not intelligible speech/dubbing.
				var syllable := fmod(t, 0.23) / 0.23
				var gate := pow(sin(PI * syllable), 2.0)
				var pitch := 155.0 if kind == "voice_dante" else 112.0
				value = (sin(TAU * pitch * t + 0.5 * sin(t * 19.0)) * 0.13 + sin(TAU * pitch * 3.0 * t) * 0.035 + sin(TAU * pitch * 5.0 * t) * 0.018) * gate
			"logo":
				value = sin(TAU * 110.0 * t) * exp(-t * 1.8) * 0.35
				for note in 3:
					var age := t - 0.3 - note * 0.19
					if age > 0.0:
						value += sin(TAU * [440.0, 659.25, 880.0][note] * age) * exp(-age * 3.2) * minf(age * 45.0, 1.0) * 0.15
			"water":
				value = low * (0.45 + 0.25 * sin(TAU * t / 3.0)) + noise * 0.018
			"terminal":
				# Indistinct crowd texture, not invented intelligible announcements.
				value = low * 0.32
				for voice in 4:
					value += sin(TAU * (127.0 + voice * 43.0) * t + sin(TAU * t / 2.0)) * pow(maxf(0.0, sin(TAU * t * (voice + 1) / 6.0)), 4.0) * 0.012
			"workshop":
				value = (sin(TAU * 60.0 * t) + sin(TAU * 120.0 * t) * 0.3) * 0.065 + low * 0.1
			"gull":
				var age := fmod(t, 0.85)
				value = sin(TAU * (760.0 * age + 150.0 * sin(age * 3.0))) * sin(PI * clampf(age / 0.7, 0.0, 1.0)) * 0.17
			"metal":
				value = (sin(TAU * 430.0 * t) + sin(TAU * 731.0 * t) * 0.4) * exp(-t * 7.0) * 0.3
			"air":
				value = (noise * 0.14 + low * 0.6) * exp(-t * 2.8)
		# Both ends meet at silence, including loop boundaries (no DC click).
		var envelope := minf(t / 0.04, 1.0) * minf((duration - t) / 0.12, 1.0)
		bytes.encode_s16(i * 2, int(clampf(value * envelope, -0.9, 0.9) * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.data = bytes
	if looped:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_end = count
	cache[kind] = stream
	return stream
