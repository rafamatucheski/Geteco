extends RefCounted
## Verbatim PT/EN dialogue from HarborFirstFavors, loaded once per session.
var _source: Dictionary = {}
var _cobra: Dictionary = {}

func _init() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/campaign/first-favors-dialogue.json"))
	if parsed is Dictionary: _source = parsed
	var cobra: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/campaign/cobra-dialogue.json"))
	if cobra is Dictionary: _cobra = cobra

func lines(section: String, language: String = "pt") -> Array:
	var source: Array = []
	match section:
		"primeiro_giro_begin": source = _source.get("begin", [])
		"bank_receipt": source = _source.get("interact", []).slice(2)
		"bank_unavailable": source = _source.get("interact", []).slice(0, 2)
		"primeiro_giro_finish": source = _source.get("finish_dialogue", [])
		_: source = _cobra.get(section, [])
	var result := []
	for row in source:
		result.append({"speaker": row.speaker, "message": row.en if language.begins_with("en") else row.pt,
			"source": row.source, "line": row.line})
	return result
