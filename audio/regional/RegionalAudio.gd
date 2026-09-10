extends RefCounted
## Assets compartilhados; nenhum PCM é gerado ao viajar entre regiões.
static var _cache: Dictionary = {}

static func sound(kind: String, variant: int = 0) -> AudioStream:
	var count := 6 if kind == "scrap" else (2 if kind == "wind" else 3)
	var file := "%s_%d.%s" % [kind, posmod(variant, count), "wav" if kind == "scrap" else "ogg"]
	if not _cache.has(file):
		var stream := load("res://audio/regional/" + file) as AudioStream
		if stream is AudioStreamOggVorbis: stream.loop = kind == "wind"
		_cache[file] = stream
	return _cache[file]
