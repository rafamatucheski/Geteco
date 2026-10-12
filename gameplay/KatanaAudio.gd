extends RefCounted
## Sabre de luz sintetizado; katana de aço usa Foley renderizado offline.
const FOLEY := preload("res://audio/export_compat/ImportedAudioLoader.gd")
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

## Três tomadas próprias, cacheadas; não sintetizar PCM no frame do golpe.
static func swing(variant: int) -> AudioStreamWAV:
	return FOLEY.wav("res://audio/katana/swing_%d.wav" % posmod(variant, 3))

static func cut(variant: int) -> AudioStreamWAV:
	return FOLEY.wav("res://audio/katana/cut_%d.wav" % posmod(variant, 3))
