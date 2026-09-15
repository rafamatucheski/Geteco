extends RefCounted

static var _streams := {}

static func stream_for(event: StringName) -> AudioStream:
	if event not in [&"officer_down", &"reinforcements", &"suspect_spotted", &"search_cancelled", &"cruiser_stolen"]: return null
	if not _streams.has(event):
		_streams[event] = load("res://audio/police_dispatch/%s.wav" % event)
	return _streams[event]
