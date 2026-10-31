extends RefCounted
## Instalado uma vez. As notificações nativas de tradução de Control atualizam a UI existente.
## Strings de origem e identificadores salvos ficam intactos; só a apresentação é traduzida.
static var _installed := false
static var _resources: Array[Translation] = []

static func install() -> void:
	if _installed: return
	_installed = true
	var pairs: Dictionary = {}
	var files := DirAccess.get_files_at("res://data/localization")
	files.sort()
	for file in files:
		if file.ends_with(".en.json"):
			var rows: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/localization/"+file))
			if rows is Dictionary: pairs.merge(rows, true)
	var speech: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/dialogue/english-voice-translations.json"))
	if speech is Dictionary:
		for source in speech:
			if speech[source] is String: pairs[source] = speech[source]
	for language in ["pt", "en"]:
		var resource := preload("res://runtime/PresentationTranslation.gd").new()
		resource.locale = language
		resource.configure(pairs, language == "en")
		TranslationServer.add_translation(resource)
		_resources.append(resource)

static func text(source: String) -> String:
	return TranslationServer.translate(source)

static func uninstall() -> void:
	for resource in _resources: TranslationServer.remove_translation(resource)
	_resources.clear()
	_installed = false
