extends RefCounted
## Cached runtime sources: no stale WAV override of the layered engine.
const KIT := preload("res://audio/monaliza_review/MonalizaAudioKit.gd")
static var cache := {}
static func stream(kind: String) -> AudioStreamWAV:
	if cache.has(kind): return cache[kind]
	var wav: AudioStreamWAV
	match kind:
		"engine": wav = KIT.generate_engine_stream()
		"turbo_spool": wav = KIT.generate_turbo_spool_stream()
		"turbo_release": wav = KIT.generate_turbo_release_stream()
		"turbo_shift": wav = KIT.generate_turbo_shift_stream()
		"ignition": wav = KIT.generate_ignition_stream()
		_: return null
	cache[kind] = wav
	return wav
