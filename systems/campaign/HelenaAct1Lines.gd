extends RefCounted
## Falas novas do ato 1 (data/campaign/helena-act1-dialogue.json), lidas uma vez. Só legenda: o "en"
## vazio cai no português até a tradução existir, e não há voz gravada para nenhuma delas.
const PATH := "res://data/campaign/helena-act1-dialogue.json"
static var _source: Dictionary = {}

static func source() -> Dictionary:
	if _source.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if parsed is Dictionary: _source = parsed
	return _source

## Linhas prontas para FullSession.show_dialogue: [{speaker, message}].
static func lines(section: String) -> Array:
	var english := TranslationServer.get_locale().begins_with("en")
	var result: Array = []
	var rows: Variant = source().get(section, [])
	if not rows is Array: return result
	for row in rows:
		var text := str(row.get("en", "")) if english else ""
		if text.is_empty(): text = str(row.get("pt", ""))
		result.append({"speaker": str(row.get("speaker", "")), "message": text})
	return result
