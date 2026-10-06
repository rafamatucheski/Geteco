extends RefCounted
## Exact authored notices only: UI notifications and objectives stay unvoiced.
static var _notices: Dictionary = {}
static var _loaded := false

static func notice(text: String) -> Dictionary:
	if not _loaded:
		_loaded = true
		var path := "res://audio/mission_voices/en/catalog.json"
		if FileAccess.file_exists(path):
			var catalog = JSON.parse_string(FileAccess.get_file_as_string(path))
			if catalog is Dictionary:
				for entry in catalog.get("lines", []):
					for alias in entry.get("aliases", []):
						var split := str(alias).find(": ")
						if split <= 0: continue
						_notices[str(alias)] = {"speaker": str(alias).left(split), "message": str(alias).substr(split+2), "persona": str(entry.persona), "voice_text": str(entry.text)}
	return _notices.get(text, {})
