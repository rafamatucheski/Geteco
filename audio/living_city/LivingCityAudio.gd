extends RefCounted
## Recursos gravados: carregados uma vez, sem sintetizar PCM ao entrar na cidade.
const ROOT := "res://audio/living_city/"
static var _cache: Dictionary = {}

static func bed(kind: String, variant: int = 0) -> AudioStream:
	return _stream("%s_%d.ogg" % [kind, posmod(variant, 2)], true)

static func detail(kind: String, variant: int) -> AudioStream:
	return _stream("%s_detail_%d.wav" % [kind, posmod(variant, 3)], false)

static func stations() -> Array:
	var day := _stream("porto_fm.ogg", true)
	var night := _stream("porto_noite.ogg", true)
	day.resource_name = "PORTO FM · Empty Stretch"
	night.resource_name = "PORTO NOITE · Fusion Jazz"
	if not _cache.has("off"):
		var off := AudioStreamWAV.new()
		off.format = AudioStreamWAV.FORMAT_16_BITS
		off.mix_rate = 8000
		var silence := PackedByteArray()
		silence.resize(16000)
		off.data = silence
		off.loop_mode = AudioStreamWAV.LOOP_FORWARD
		off.loop_end = 8000
		off.resource_name = "RADIO OFF"
		_cache.off = off
	return [day, night, _cache.off]

static func _stream(file: String, looped: bool) -> AudioStream:
	if not _cache.has(file):
		var stream := load(ROOT + file) as AudioStream
		if stream is AudioStreamOggVorbis:
			stream.loop = looped
		_cache[file] = stream
	return _cache[file]
