extends RefCounted
## Original synthesized energy hum and swing: cached PCM, no external recordings.
static var _cache := {}

static func stream(kind: String) -> AudioStreamWAV:
	if _cache.has(kind): return _cache[kind]
	var rate := 22050
	var duration := 1.0 if kind == "hum" else 0.34
	var count := int(rate * duration)
	var pcm := PackedByteArray()
	pcm.resize(count * 2)
	for i in count:
		var t := float(i) / rate
		var envelope := 0.35 if kind == "hum" else sin(PI * t / duration)
		var frequency := 90.0 if kind == "hum" else 180.0 + 700.0 * pow(1.0 - t / duration, 2.0)
		var wave := sin(TAU * frequency * t) * 0.55 + sin(TAU * frequency * 2.0 * t) * 0.25 + sin(TAU * 37.0 * t) * 0.1
		pcm.encode_s16(i * 2, int(clampf(wave * envelope, -1.0, 1.0) * 32767.0))
	var result := AudioStreamWAV.new()
	result.format = AudioStreamWAV.FORMAT_16_BITS
	result.mix_rate = rate
	result.data = pcm
	if kind == "hum":
		result.loop_mode = AudioStreamWAV.LOOP_FORWARD
		result.loop_end = count
	_cache[kind] = result
	return result

## Corte em carne: chiado curto da lâmina, baque grave e úmido e um estalo molhado logo depois.
## Sintetizado como o resto da katana; cada variante tem semente própria para os golpes não soarem iguais.
static func cut(variant: int) -> AudioStreamWAV:
	var key := "cut_%d" % variant
	if _cache.has(key): return _cache[key]
	var rate := 22050
	var duration := 0.42
	var count := int(rate * duration)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7919 + variant * 104729
	var thud_base: float = [55.0, 62.0, 49.0][posmod(variant, 3)]
	var pcm := PackedByteArray()
	pcm.resize(count * 2)
	var low := 0.0
	var band_a := 0.0
	var band_b := 0.0
	var previous := 0.0
	for i in count:
		var t := float(i) / rate
		var noise := rng.randf_range(-1.0, 1.0)
		# Chiado: ruído com passa-alta simples (diferença entre amostras), some em ~70 ms.
		var hiss := (noise - previous) * 0.5 * exp(-t / 0.028)
		previous = noise
		# Baque: tom que cai até a base mais ruído grave filtrado.
		low = lerpf(low, noise, 0.06)
		var thud_frequency: float = thud_base + 85.0 * exp(-t / 0.05)
		var thud := (sin(TAU * thud_frequency * t) * 0.7 + low * 1.6) * exp(-t / 0.09) * smoothstep(0.0, 0.006, t)
		# Estalo molhado: ruído em banda (~900 Hz) com leve tremor, 25 ms depois do contato.
		band_a = lerpf(band_a, noise, 0.25)
		band_b = lerpf(band_b, band_a, 0.25)
		var wet := 0.0
		if t >= 0.025: wet = (band_a - band_b) * 2.5 * exp(-(t - 0.025) / 0.06) * (0.6 + 0.4 * sin(TAU * 38.0 * t))
		var wave := hiss * 0.55 + thud * 0.65 + wet * 0.5
		pcm.encode_s16(i * 2, int(clampf(wave, -1.0, 1.0) * 32767.0))
	var result := AudioStreamWAV.new()
	result.format = AudioStreamWAV.FORMAT_16_BITS
	result.mix_rate = rate
	result.data = pcm
	_cache[key] = result
	return result
