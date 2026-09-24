extends RefCounted
## Recorded V1 ambience and activity cues, cached for the native V2 world.
const LIVING_ROOT := "res://audio/living_city/"
const REGIONAL_ROOT := "res://audio/regional/"
const FOOTSTEP_ROOT := "res://audio/footsteps/"
const ACTIVITY_ROOT := "res://audio/v1_ambience/activity/"
const FOOTSTEP_FILES := {
	"concrete":"concrete", "asphalt":"concrete", "dirt":"grass",
	"gravel":"concrete", "grass":"grass", "snow":"grass",
	"metal":"metal", "tile":"tile", "wood":"wood",
	"wet":"wet", "asphalt_wet":"wet", "dirt_wet":"grass_wet",
	"gravel_wet":"wet", "grass_wet":"grass_wet", "metal_wet":"metal_wet",
	"snow_wet":"grass_wet", "tile_wet":"tile", "wood_wet":"wood",
}
static var _cache: Dictionary = {}

static func bed(kind: String, variant: int = 0) -> AudioStream:
	var file := "%s_%d.ogg" % [kind,posmod(variant,2)]
	return _stream(LIVING_ROOT+file,true)

static func regional(kind: String, variant: int = 0) -> AudioStream:
	var count := 6 if kind == "scrap" else (2 if kind == "wind" else 3)
	var extension := "wav" if kind == "scrap" else "ogg"
	return _stream(REGIONAL_ROOT+"%s_%d.%s"%[kind,posmod(variant,count),extension],kind=="wind")

static func detail(kind: String, variant: int = 0) -> AudioStream:
	return _stream(LIVING_ROOT+"%s_detail_%d.wav"%[kind,posmod(variant,3)],false)

static func footstep(surface: String, variant: int = 0) -> AudioStream:
	var file_surface: String = FOOTSTEP_FILES.get(surface,"concrete")
	return _stream(FOOTSTEP_ROOT+"%s_%d.wav"%[file_surface,posmod(variant,4)],false)

static func activity(kind: String) -> AudioStream:
	return _stream(ACTIVITY_ROOT+kind+".wav",false)

static func footstep_pitch(surface: String) -> float:
	# V1 has no separate recorded dirt/snow library. Keep its recorded soft step,
	# with a restrained playback treatment instead of synthesizing new PCM.
	match surface.trim_suffix("_wet"):
		"snow": return .82
		"dirt": return .92
		"gravel": return 1.08
		_: return 1.0

static func _stream(path: String, looped: bool) -> AudioStream:
	if _cache.has(path): return _cache[path]
	if not ResourceLoader.exists(path): return null
	var source := load(path) as AudioStream
	if source == null: return null
	var stream := source.duplicate()
	if stream is AudioStreamOggVorbis: stream.loop = looped
	_cache[path] = stream
	return stream
