extends SceneTree
## Resolve cada tomada autoral pelo loader de produção nas quatro
## combinações de legenda/voz; um manifesto sozinho não prova áudio tocável.
const VOICE := preload("res://audio/ExpressiveVoice.gd")
const SERVICES := preload("res://data/catalogs/ServiceDialogue.gd")
const ROUTINES := preload("res://gameplay/routines_v1/RoutineCatalog.gd")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://audio/mission_voices/en/catalog.json"))
	var checks := 0
	var failures := 0
	var catalog_keys: Dictionary = {}
	for row in catalog.lines: catalog_keys[str(row.key)] = true
	# Avalia as funções reais que produzem os dados, independente das expressões
	# regulares do extrator Python, para que moradores recém-acrescentados não fiquem mudos.
	for definition in ROUTINES.definitions():
		for text in definition.get("lines", []):
			checks += 1
			if not catalog_keys.has(VOICE.recording_key(str(text), str(definition.display_name))):
				failures += 1
				push_error("Routine dialogue omitted from bank: %s" % definition.id)
	for id in SERVICES.PEOPLE:
		for line in SERVICES.lines(id):
			if str(line.speaker).to_lower() in ["terminal", "triagem", "alarme"]: continue
			checks += 1
			if not catalog_keys.has(VOICE.recording_key(str(line.message), str(line.speaker))):
				failures += 1
				push_error("Service dialogue omitted from bank: %s" % id)
	for row in catalog.lines:
		for language in ["pt_BR", "en"]:
			var canonical: AudioStream = VOICE.recorded_line(str(row.text), str(row.persona), language)
			var translated: AudioStream = VOICE.recorded_line(str(row.en), str(row.persona), language)
			checks += 2
			if canonical == null or canonical.get_length() <= 0.1:
				failures += 1
				push_error("Unplayable %s take: %s" % [language, row.key])
			var same_variant_group: bool = canonical != null and translated != null and canonical.has_meta("voice_variant_group") \
				and canonical.get_meta("voice_variant_group") == translated.get_meta("voice_variant_group", "")
			if translated == null or (canonical != translated and not same_variant_group):
				failures += 1
				push_error("Subtitle language changes %s take: %s" % [language, row.key])
	print("BILINGUAL_VOICE_COVERAGE lines=%d checks=%d failures=%d" % [catalog.lines.size(), checks, failures])
	quit(0 if failures == 0 else 1)
