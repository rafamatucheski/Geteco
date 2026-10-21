extends SceneTree
## As falas PT-BR da ElevenLabs (Dante e Maciota) substituem o banco local e tocam de verdade.
const BANK := preload("res://audio/DirectedVoiceBank.gd")
var checks := 0
var failures: Array[String] = []

func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); push_error(label)

func run() -> void:
	OS.set_environment("GETECO_DIRECTED_VOICES", "1")
	var overlay := BANK._json(BANK.OVERLAY)
	var rows := {}
	for row in BANK._json(BANK.DIRECTION).get("lines", []): rows[str(row.key)] = row
	# Elenco ElevenLabs: Dante, Maciota (e a voz ao telefone), Helena bancária, Takeshi, Vicente.
	var expected := {"pt_BR": 128, "en": 128}
	for language in expected:
		var lines: Dictionary = overlay.get("lines", {}).get(language, {})
		check(lines.size() == expected[language], "%s tem %d falas instaladas (%d)" % [language, expected[language], lines.size()])
		for row_key in lines:
			var row: Dictionary = rows.get(row_key, {})
			check(not row.is_empty(), "Chave existe no roteiro: " + row_key)
			if row.is_empty(): continue
			var take := BANK.resolve(BANK.canonical(str(row.source), str(row.speaker)), language, str(lines[row_key].character_id))
			check(str(take.get("path", "")).contains("/elevenlabs/" + language + "/"), "%s resolve para a ElevenLabs: %s" % [language, row_key])
			check(BANK.stream(take) != null, "Áudio carrega: %s %s" % [language, row_key])
	var pain: Dictionary = rows.get("80a833fa7c4bf1c457d0ce1d3fbaf3e0fe21b6b6f926b242223d70ce494307ac", {})
	var seen := {}
	var previous := ""
	var repeated := false
	for i in 24:
		var path := str(BANK.resolve(pain, "pt_BR", "dante").get("path", ""))
		seen[path] = true
		repeated = repeated or path == previous
		previous = path
	check(seen.size() >= 3, "Dor do Dante sorteia vários tons (%d)" % seen.size())
	check(not repeated, "Mesmo tom não toca duas vezes seguidas")
	print("TEST_ELEVENLABS_VOICES checks=%d failures=%d" % [checks, failures.size()])
	for failure in failures.slice(0, 10): print("  FAIL ", failure)
	quit(0 if failures.is_empty() else 1)
