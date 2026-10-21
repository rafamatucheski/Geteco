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
	var lines: Dictionary = overlay.get("lines", {}).get("pt_BR", {})
	check(lines.size() == 53, "Sobreposição tem as 53 falas instaladas (%d)" % lines.size())
	var rows := {}
	for row in BANK._json(BANK.DIRECTION).get("lines", []): rows[str(row.key)] = row
	for row_key in lines:
		var row: Dictionary = rows.get(row_key, {})
		check(not row.is_empty(), "Chave existe no roteiro: " + row_key)
		if row.is_empty(): continue
		var canonical := BANK.canonical(str(row.source), str(row.speaker))
		var take := BANK.resolve(canonical, "pt_BR", str(row.speaker))
		check(str(take.get("path", "")).contains("/elevenlabs/"), "Fala resolve para a ElevenLabs: " + str(row.spoken_pt))
		check(BANK.stream(take) != null, "Áudio carrega: " + str(row.spoken_pt))
	# Inglês continua no banco local: a sobreposição é só PT-BR.
	for row_key in lines:
		var en := BANK.resolve(rows[row_key], "en", str(rows[row_key].speaker))
		check(not str(en.get("path", "")).contains("/elevenlabs/"), "Inglês não usa áudio PT-BR")
		break
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
