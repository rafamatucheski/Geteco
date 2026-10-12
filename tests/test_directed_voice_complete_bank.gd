extends SceneTree
## Run only after production runtime.json is complete. No fixtures or legacy fallback.
const VOICE := preload("res://audio/ExpressiveVoice.gd")
const BANK := preload("res://audio/DirectedVoiceBank.gd")
const FERRY_TRACK := preload("res://cutscenes/opening/ferry/FerryVoiceTrack.gd")
const EXPECTED_LINES := 565
var failures: Array[String] = []
var checks := 0
var directed_pairs := 0
var total_seconds := {"pt_BR":0.0, "en":0.0}

func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)

func run() -> void:
	if not BANK.enabled(): push_error("Complete-bank validation requires GETECO_DIRECTED_VOICES=1"); quit(2); return
	var direction := BANK._json(BANK.DIRECTION)
	var manifest := BANK._json(BANK.MANIFEST)
	var rows: Array = direction.get("lines", [])
	if rows.size() != EXPECTED_LINES or manifest.get("lines", {}).get("pt_BR", {}).size() != EXPECTED_LINES or manifest.get("lines", {}).get("en", {}).size() != EXPECTED_LINES:
		push_error("Production bank is not ready: expected 565 validated entries per language. No partial-bank success is allowed.")
		quit(2)
		return
	var identities: Dictionary = {}
	for row in rows:
		var canonical := BANK.canonical(str(row.source), str(row.speaker))
		var actor := BANK.profile(canonical)
		check(not actor.is_empty(), str(row.key) + ": contextual identity resolves")
		if actor.is_empty(): continue
		identities[str(actor.character_id)] = true
		for audio_language in ["pt_BR", "en"]:
			var label: String = str(row.key) + ":" + str(audio_language)
			var take := BANK.resolve(canonical, audio_language, str(actor.character_id), str(row.source_section))
			check(not take.is_empty(), label + ": current hashes, identity, gender, words, anchor and technical validation")
			if take.is_empty(): continue
			var first := VOICE.presentation(str(row.source), str(row.speaker), audio_language, "pt_BR", str(actor.character_id), str(row.source_section))
			check(first.directed and first.stream != null, label + ": production take loads without fallback")
			if not first.directed or first.stream == null: continue
			directed_pairs += 1
			var stream := first.stream as AudioStream
			total_seconds[audio_language] += stream.get_length()
			check(absf(stream.get_length() - float(take.duration_seconds)) <= .03, label + ": WAV duration matches validated manifest")
			check(str(stream.get_meta("voice_language", "")) == audio_language and str(stream.get_meta("character_id", "")) == str(actor.character_id), label + ": loaded audio metadata belongs to this identity/language")
			for caption_language in ["pt_BR", "en"]:
				var words := str(row.spoken_en if caption_language == "en" else row.spoken_pt)
				var shown := VOICE.presentation(str(row.source), str(row.speaker), audio_language, caption_language, str(actor.character_id), str(row.source_section))
				check(shown.directed and shown.message == words and shown.source_key == row.key, label + ": matching " + caption_language + " caption")
				var alias := VOICE.presentation(words, str(row.speaker), audio_language, caption_language, str(actor.character_id), str(row.source_section))
				check(alias.directed and alias.source_key == row.key and alias.message == words, label + ": rewritten " + caption_language + " alias")
			var legacy: Dictionary = BANK._legacy.get(str(row.key), {})
			for text in legacy.get("aliases", []) + ([legacy.en] if legacy.has("en") else []):
				var alias := VOICE.presentation(str(text), str(row.speaker), audio_language, "en", str(actor.character_id), str(row.source_section))
				check(alias.directed and alias.source_key == row.key, label + ": legacy alias resolves to directed take")
			check(BANK._streams.size() <= 32, label + ": bounded stream cache")
	check(directed_pairs == EXPECTED_LINES * 2, "All 1,130 production language/take pairs loaded with directed=true")
	check(identities.size() == 95, "All 95 contextual casting identities covered")
	var ferry_rows: Array = BANK._json("res://cutscenes/opening/ferry/timing.json").get("lines", [])
	var ferry := FERRY_TRACK.new()
	root.add_child(ferry)
	var ferry_modes := {}
	var ferry_failures := {}
	for language in ["pt_BR", "en"]:
		ferry_modes[language] = ferry.configure(ferry_rows, language)
		if not ferry_modes[language]: ferry_failures[language] = ferry.failures.duplicate(true)
		check(ferry_modes[language], "Ferry " + str(language) + " uses all eleven directed takes without overflow: " + ferry.reason + " " + JSON.stringify(ferry.failures))
	ferry.free()
	var report := {"checks":checks, "failures":failures, "lines":rows.size(), "directed_pairs":directed_pairs, "identities":identities.size(),
		"duration_seconds":total_seconds, "cache_streams":BANK._streams.size(), "fixtures":false, "legacy_fallback_allowed":false,
		"ferry_directed":ferry_modes,
		"ferry_failures":ferry_failures,
		"artistic_review":"not_asserted_by_this_technical_test", "performance_review":"not_asserted_by_headless_execution"}
	var report_path := "user://directed-runtime-complete-bank.json"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--report="): report_path = argument.trim_prefix("--report=")
	var file := FileAccess.open(report_path, FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify(report, "\t") + "\n")
	for failure in failures: push_error(failure)
	print("DIRECTED_COMPLETE_BANK checks=%d directed_pairs=%d identities=%d failures=%d report=%s" % [checks, directed_pairs, identities.size(), failures.size(), report_path])
	quit(0 if failures.is_empty() else 1)
