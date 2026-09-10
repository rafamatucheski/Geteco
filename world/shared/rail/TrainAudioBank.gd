extends RefCounted
## Loops PCM compartilhados: não sintetizar milhares de amostras a cada frame.
var _cache: Dictionary = {}

func sound(kind: String) -> AudioStreamWAV:
	if _cache.has(kind): return _cache[kind]
	var rate := 22050
	var duration := 2.0
	var count := int(duration * rate)
	var bytes := PackedByteArray()
	bytes.resize(count * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 73521
	var filtered := 0.0
	for i in count:
		var t := float(i) / rate
		filtered = lerpf(filtered, rng.randf_range(-1.0, 1.0), 0.19)
		var sample := 0.0
		match kind:
			"diesel":
				var firing := 0.72 + 0.28 * sin(TAU * 12.0 * t)
				sample = firing * (sin(TAU * 38.0 * t) * 0.32 + sin(TAU * 76.0 * t) * 0.15 + sin(TAU * 114.0 * t) * 0.07) + filtered * 0.10
			"rail", "bridge":
				var phase := fposmod(t, 0.5)
				for strike in [0.035, 0.105, 0.29, 0.36]:
					var age := phase - float(strike)
					if age >= 0.0:
						if kind == "rail":
							sample += exp(-age * 95.0) * (filtered * 1.5 + sin(TAU * 840.0 * age) * 0.4)
						else:
							sample += exp(-age * 23.0) * (sin(TAU * 145.0 * age) * 0.30 + sin(TAU * 293.0 * age) * 0.13)
				if kind == "rail": sample += filtered * 0.07
			"curve":
				sample = sin(TAU * 1380.0 * t + sin(TAU * 3.0 * t) * 1.8) * 0.18 + sin(TAU * 2070.0 * t) * 0.05
			"horn":
				var envelope := smoothstep(0.0, 0.12, t) * (1.0 - smoothstep(1.35, 1.95, t))
				for frequency in [311.0, 370.0, 415.0]:
					sample += envelope * (sin(TAU * frequency * t) * 0.15 + sin(TAU * frequency * 2.0 * t) * 0.045)
		# Uma curta janela evita estalos na emenda dos componentes de ruído.
		if kind != "horn": sample *= minf(1.0, minf(t, duration - t) / 0.006)
		bytes.encode_s16(i * 2, int(clampf(sample, -0.98, 0.98) * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.data = bytes
	if kind != "horn":
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_end = count
	_cache[kind] = stream
	return stream
