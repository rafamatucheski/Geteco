extends RefCounted
## One immutable metadata index per session; WAVs are loaded only on speech events.
## Generated, technically validated takes may play while artistic review is pending.
const MANIFEST := "res://audio/mission_voices/directed/runtime.json"
## Falas da ElevenLabs ficam fora de runtime.json porque a publicação do banco local
## reescreve aquele arquivo; este se sobrepõe chave a chave (tools/install_elevenlabs_voices.py).
const OVERLAY := "res://audio/mission_voices/directed/elevenlabs.json"
const DIRECTION := "res://data/dialogue/voice-line-direction.json"
const CAST := "res://data/dialogue/voice-cast.json"
static var _loaded := false
static var _lines: Dictionary = {}
static var _aliases: Dictionary = {}
static var _legacy: Dictionary = {}
static var _profiles: Dictionary = {}
static var _takes: Dictionary = {}
static var _streams: Dictionary = {}
static var _last_variant: Dictionary = {}

static func enabled() -> bool:
	return OS.get_environment("GETECO_DIRECTED_VOICES").to_lower() not in ["0", "false", "off"]

static func language(value: String) -> String:
	return "en" if value.to_lower().replace("-", "_").get_slice("_", 0) == "en" else "pt_BR"

static func key(text: String, persona: String) -> String:
	return (persona.to_lower() + "|" + text).sha256_text()

static func _json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path): return {}
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return value if value is Dictionary else {}

static func _load_index() -> void:
	if _loaded: return
	_loaded = true
	for row in _json(DIRECTION).get("lines", []):
		if not row is Dictionary: continue
		var row_key := key(str(row.get("source", "")), str(row.get("speaker", "")))
		if row_key != str(row.get("key", "")): continue
		_lines[row_key] = row
		for alias in [row.get("spoken_pt", ""), row.get("spoken_en", "")]:
			_add_alias(str(alias), str(row.speaker), row_key)
	for row in _json("res://audio/mission_voices/en/catalog.json").get("lines", []):
		var row_key := key(str(row.get("text", "")), str(row.get("persona", "")))
		_legacy[row_key] = row
		_add_alias(str(row.get("en", "")), str(row.get("persona", "")), row_key)
		for alias in row.get("aliases", []): _add_alias(str(alias), str(row.get("persona", "")), row_key)
	_profiles = _json(CAST).get("personas", {})
	var manifest := _json(MANIFEST)
	# Whole-file hashes are calculated once, never on the frame/speech hot path.
	# Changing acting direction or a cast profile invalidates an older runtime bank.
	if int(manifest.get("version", 0)) == 1 and str(manifest.get("cast_sha256", "")) == FileAccess.get_sha256(CAST) \
			and str(manifest.get("direction_sha256", "")) == FileAccess.get_sha256(DIRECTION):
		_takes = manifest.get("lines", {})
	# A sobreposição não depende dos hashes do banco local: cada entrada ainda passa pela
	# conferência de texto falado, pessoa e idioma em resolve().
	# GETECO_ELEVENLABS_VOICES=0 volta ao banco local, para comparação A/B no mesmo build.
	var overlay := {} if OS.get_environment("GETECO_ELEVENLABS_VOICES").to_lower() in ["0", "false", "off"] else _json(OVERLAY)
	if int(overlay.get("version", 0)) == 1:
		var overlay_lines: Dictionary = overlay.get("lines", {})
		for lang in overlay_lines:
			if not _takes.has(lang): _takes[lang] = {}
			for row_key in overlay_lines[lang]: _takes[lang][row_key] = overlay_lines[lang][row_key]

static func _add_alias(text: String, persona: String, row_key: String) -> void:
	if text.is_empty(): return
	var alias_key := key(text, persona)
	# Ambiguous translations must never select another person's contextual line.
	if _aliases.has(alias_key) and _aliases[alias_key] != row_key:
		_aliases[alias_key] = ""
	else: _aliases[alias_key] = row_key

static func canonical(text: String, persona: String) -> Dictionary:
	_load_index()
	var row_key := key(text, persona)
	if not _lines.has(row_key): row_key = str(_aliases.get(row_key, row_key))
	return _lines.get(row_key, {})

static func profile(row: Dictionary) -> Dictionary:
	if row.is_empty(): return {}
	var person: Dictionary = _profiles.get(str(row.get("speaker", "")), {})
	var matches: Array[Dictionary] = []
	if str(row.key) in person.get("line_keys", []): matches.append(person)
	for variant in person.get("variants", []):
		if str(row.key) in variant.get("line_keys", []): matches.append(variant)
	if matches.size() != 1: return {}
	var result: Dictionary = matches[0].duplicate()
	result["character_id"] = str(result.get("default_character", result.get("alias_of", result.get("id", ""))))
	return result

static func legacy_message(row: Dictionary, requested_language: String, fallback: String) -> String:
	if row.is_empty(): return fallback
	if language(requested_language) == "pt_BR": return str(row.source)
	var original: Dictionary = _legacy.get(str(row.key), {})
	if not original.is_empty(): return str(original.get("en", row.source))
	return TranslationServer.translate(str(row.source))

static func resolve(row: Dictionary, requested_language: String, character_id := "", section := "") -> Dictionary:
	if not enabled() or row.is_empty(): return {}
	var actor := profile(row)
	if actor.is_empty(): return {}
	if not character_id.is_empty() and character_id != str(actor.character_id): return {}
	if not section.is_empty() and section != str(row.get("source_section", "")):
		if section not in actor.get("contexts", []) and section not in actor.get("sections", []): return {}
	var lang := language(requested_language)
	var entry: Dictionary = _takes.get(lang, {}).get(str(row.key), {})
	if entry.is_empty(): return {}
	if entry.get("status", "") not in ["generated", "approved"]: return {}
	var validation: Variant = entry.get("technical_validation", {})
	if not validation is Dictionary or validation.get("passed", false) != true: return {}
	for field in ["transcription_validation", "gender_validation"]:
		var review: Variant = entry.get(field, {})
		if review is Dictionary and (review.get("status", "") == "failed" or review.get("passed", true) == false): return {}
	var spoken := str(row.get("spoken_en" if lang == "en" else "spoken_pt", ""))
	if spoken.is_empty() or str(entry.get("spoken_text", "")) != spoken: return {}
	if str(entry.get("source", "")) != str(row.source) or str(entry.get("persona", "")) != str(row.speaker): return {}
	if str(entry.get("language", "")) != lang or str(entry.get("character_id", "")) != str(actor.character_id): return {}
	if str(entry.get("voice_gender", "")) != str(actor.get("gender", "")): return {}
	if str(entry.get("voice_gender", "")) not in ["male", "female"]: return {}
	if str(entry.get("signature", "")).length() != 64 or float(entry.get("duration_seconds", 0)) <= 0: return {}
	if str(entry.get("anchor_id", "")) != str(actor.character_id) or str(entry.get("anchor_sha256", "")).length() != 64: return {}
	var path := str(entry.get("path", ""))
	if not path.begins_with("res://audio/mission_voices/directed/") or ".." in path or not path.ends_with(".wav"): return {}
	if not ResourceLoader.exists(path) and not FileAccess.file_exists(path): return {}
	return _pick_variant(entry)

## Falas repetidas (dor, cumprimento) têm vários tons; sorteia um sem repetir o anterior.
static func _pick_variant(entry: Dictionary) -> Dictionary:
	var variants: Variant = entry.get("variants", [])
	if not variants is Array or variants.size() < 2: return entry
	var key := str(entry.get("source_key", entry.path))
	var index: int = randi() % variants.size()
	if index == int(_last_variant.get(key, -1)): index = (index + 1) % variants.size()
	_last_variant[key] = index
	var chosen: Variant = variants[index]
	if not chosen is Dictionary: return entry
	var path := str(chosen.get("path", ""))
	if not path.begins_with("res://audio/mission_voices/directed/") or ".." in path or not path.ends_with(".wav"): return entry
	var result := entry.duplicate()
	for field in ["path", "audio_sha256", "duration_seconds", "playback_gain_db"]:
		if chosen.has(field): result[field] = chosen[field]
	return result

static func stream(entry: Dictionary) -> AudioStream:
	if entry.is_empty(): return null
	var path := str(entry.path)
	if _streams.has(path): return _streams[path]
	var result: AudioStream
	if ResourceLoader.exists(path, "AudioStream"):
		result = ResourceLoader.load(path, "AudioStream") as AudioStream
	if result == null and FileAccess.file_exists(path):
		result = AudioStreamWAV.load_from_file(ProjectSettings.globalize_path(path))
	if result == null: return null
	result.set_meta("mission_voice", true)
	result.set_meta("directed_voice", true)
	result.set_meta("voice_language", entry.language)
	result.set_meta("character_id", entry.character_id)
	result.set_meta("spoken_text", entry.spoken_text)
	# Tons sorteados da mesma fala são intercambiáveis; o grupo identifica a fala, não o arquivo.
	if entry.get("variants", []) is Array and entry.get("variants", []).size() > 1:
		result.set_meta("voice_variant_group", str(entry.get("source_key", "")))
	result.set_meta("directed_gain_db", clampf(float(entry.get("playback_gain_db", entry.get("directed_gain_db", 0.0))), -24.0, 12.0))
	if _streams.size() >= 32: _streams.erase(_streams.keys()[0])
	_streams[path] = result
	return result
