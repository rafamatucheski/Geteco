extends RefCounted
## Recorded dialogue follows the audio preference, independently of subtitle locale.
## Legacy ambient speech keeps one finite buffer per line and a bounded cache.
const RATE := 22050
const DIRECTED := preload("res://audio/DirectedVoiceBank.gd")
static var cache: Dictionary = {}
static var recordings: Dictionary = {}
static var maciota_recordings: Dictionary = {}
static var english_recordings: Dictionary = {}
static var _canonical_keys: Dictionary = {}
static var _recordings_loaded := false
static var _missing_recordings: Dictionary = {}

static func selected_language() -> String:
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null:
		var settings := tree.root.get_node_or_null("V2Settings")
		if settings != null: return str(settings.voice_language)
	return "pt_BR"

static func _language(value: String) -> String:
	if value.is_empty(): return selected_language()
	return "en" if value.to_lower().replace("-", "_").get_slice("_", 0) == "en" else "pt_BR"

static func recording_key(text: String, persona: String) -> String:
	return (persona.to_lower() + "|" + text).sha256_text()

static func playback_volume(stream: AudioStream, portuguese_volume := 0.0) -> float:
	if stream != null and stream.get_meta("directed_voice", false):
		return float(stream.get_meta("directed_gain_db", 0.0))
	# English takes are normalized as one cast. Keep the same dialogue level in
	# cutscenes, conversations and ambient captions; retain the existing PT mix.
	return -8.0 if stream != null and stream.get_meta("voice_language", "") == "en" else portuguese_volume

static func _legacy_recording(text: String, persona: String, language: String) -> AudioStream:
	if not _recordings_loaded:
		_recordings_loaded = true
		var manifest := "res://audio/mission_voices/recordings.json"
		if FileAccess.file_exists(manifest):
			var data = JSON.parse_string(FileAccess.get_file_as_string(manifest))
			if data is Dictionary: recordings = data
		var maciota_manifest := "res://audio/mission_voices/maciota_baritone/recordings.json"
		if FileAccess.file_exists(maciota_manifest):
			var data = JSON.parse_string(FileAccess.get_file_as_string(maciota_manifest))
			if data is Dictionary: maciota_recordings = data
		var english_manifest := "res://audio/mission_voices/en/recordings.json"
		if FileAccess.file_exists(english_manifest):
			var data = JSON.parse_string(FileAccess.get_file_as_string(english_manifest))
			if data is Dictionary: english_recordings = data
		var catalog := "res://audio/mission_voices/en/catalog.json"
		if FileAccess.file_exists(catalog):
			var data = JSON.parse_string(FileAccess.get_file_as_string(catalog))
			if data is Dictionary:
				for entry in data.get("lines", []):
					var canonical_key := recording_key(str(entry.get("text", "")), str(entry.get("persona", "")))
					var aliases: Array = entry.get("aliases", []).duplicate()
					aliases.append(str(entry.get("en", "")))
					for alias in aliases:
						if str(alias).is_empty(): continue
						_canonical_keys[recording_key(str(alias), str(entry.get("persona", "")))] = canonical_key
	# The caller is Maciota too. Keep both on the same authored voice bank and
	# never fall back to the older, independently designed VoiceDesign takes.
	var bank := maciota_recordings if persona.to_lower() in ["maciota", "caller"] else recordings
	if language == "en": bank = english_recordings
	# Resolve subtitle aliases before choosing the take, so English subtitles can
	# still use Portuguese voices (including Maciota's fixed baritone recording).
	var raw_key := recording_key(text, persona)
	var key: String = _canonical_keys.get(raw_key, raw_key)
	var path := String(bank.get(key, ""))
	if path.is_empty() or not ResourceLoader.exists(path): return null
	var stream := load(path) as AudioStream
	if stream != null:
		stream.set_meta("mission_voice", true)
		stream.set_meta("voice_language", language)
	return stream

static func presentation(text: String, persona: String, voice_language := "", text_language := "", character_id := "", section := "") -> Dictionary:
	var audio_language := _language(voice_language)
	var caption_language := DIRECTED.language(TranslationServer.get_locale() if text_language.is_empty() else text_language)
	var row := DIRECTED.canonical(text, persona)
	var actor := DIRECTED.profile(row)
	var result := {"message":DIRECTED.legacy_message(row, caption_language, text), "stream":null, "duration":0.0,
		"directed":false, "source_key":str(row.get("key", recording_key(text, persona))),
		"character_id":str(actor.get("character_id", "")), "voice_text":text, "language":audio_language}
	# An explicitly bound body never borrows a different contextual identity.
	if not character_id.is_empty() and (actor.is_empty() or character_id != str(actor.get("character_id", ""))):
		result["identity_mismatch"] = true
		return result
	var take := DIRECTED.resolve(row, audio_language, character_id, section)
	var stream := DIRECTED.stream(take)
	if stream != null:
		result["directed"] = true
		result["message"] = str(row.get("spoken_en" if caption_language == "en" else "spoken_pt", text))
		result["voice_text"] = str(take.spoken_text)
	else:
		# Legacy role recordings have no proof of body/casting compatibility. A
		# verified body with unresolved casting stays captioned until its take exists.
		var blocked_cast: bool = not character_id.is_empty() and (not actor.get("casting_blockers", []).is_empty() or actor.get("allow_legacy_voice_fallback", true) == false)
		if not DIRECTED.enabled() or not blocked_cast:
			stream = _legacy_recording(str(row.get("source", text)), persona, audio_language)
	result["stream"] = stream
	if stream != null: result["duration"] = stream.get_length()
	return result

static func _recording(text: String, persona: String, language: String, character_id := "", section := "") -> AudioStream:
	return presentation(text, persona, language, "", character_id, section).stream as AudioStream

static func line(text: String, persona := "dante", duration := 0.0, language := "") -> AudioStream:
	var resolved_language := _language(language)
	var key := "%s|%s|%s|%s|%s" % [DIRECTED.enabled(), resolved_language, persona.to_lower(), duration, text]
	if cache.has(key):
		return cache[key]
	var recorded := _recording(text, persona, resolved_language)
	if recorded != null:
		if cache.size() >= 32: cache.erase(cache.keys()[0])
		cache[key] = recorded
		return recorded
	if resolved_language == "en":
		_report_missing(text, persona, resolved_language)
		return null
	var units: Array[float] = []
	var voiced: Array[bool] = []
	for character in text.left(400):
		units.append(4.0 if character in ".!?;:" else (2.0 if character in ",—\n" else (0.65 if character == " " else 1.0)))
		voiced.append(not character in " .!?;:,—\n")
	var total := 0.0
	for unit in units: total += unit
	var seconds := clampf(duration if duration > 0 else total * 0.052, 0.3, 12.0)
	var samples := int(seconds * RATE)
	var pcm := PackedByteArray()
	pcm.resize(samples * 2)
	var envelope := PackedFloat32Array()
	envelope.resize(int(ceil(seconds * 100.0)) + 1)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key)
	var base := 148.0 if persona == "dante" else (106.0 if persona == "maciota" else 178.0)
	var cursor := 0
	for index in units.size():
		var end := mini(samples, cursor + int(samples * units[index] / maxf(total, 1.0)))
		var pitch := base * rng.randf_range(0.88, 1.12)
		var formant := rng.randf_range(2.3, 4.4)
		for i in range(cursor, end):
			if not voiced[index]: continue
			var age := float(i - cursor) / RATE
			var span := maxf(float(end - cursor) / RATE, 0.001)
			var amp := sin(PI * age / span)
			amp *= amp
			var fundamental := sin(TAU * pitch * age)
			var value := fundamental * 0.12 + sin(TAU * pitch * formant * age) * 0.04 + sin(TAU * pitch * 6.0 * age) * 0.012
			if persona == "caller":
				value = fundamental * 0.035 + sin(TAU * pitch * 3.0 * age) * 0.08
			pcm.encode_s16(i * 2, int(value * amp * 32767))
			envelope[mini(int(float(i) / RATE * 100), envelope.size() - 1)] = amp
		cursor = end
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.data = pcm
	stream.set_meta("speech_envelope", envelope)
	if cache.size() >= 32:
		cache.erase(cache.keys()[0])
	cache[key] = stream
	return stream

static func recorded_line(text: String, persona := "dante", language := "", character_id := "", section := "") -> AudioStream:
	# Authored dialogue is silent until the exact recording exists. Non-verbal
	# fallback is still available to its original ambient speech consumers.
	var resolved_language := _language(language)
	var stream := _recording(text, persona, resolved_language, character_id, section)
	if stream == null: _report_missing(text, persona, resolved_language)
	return stream

static func _report_missing(text: String, persona: String, language: String) -> void:
	var key := language + "|" + recording_key(text, persona)
	if _missing_recordings.has(key): return
	_missing_recordings[key] = true
	push_warning("Missing %s dialogue recording for %s: %s" % [language, persona, text.left(100)])

static func mouth(audio: AudioStreamPlayer) -> float:
	if not is_instance_valid(audio) or not audio.playing or audio.stream_paused:
		return 0.0
	var envelope: PackedFloat32Array = audio.stream.get_meta("speech_envelope", PackedFloat32Array())
	var index := int(audio.get_playback_position() * 100.0)
	return envelope[index] if index >= 0 and index < envelope.size() else 0.0
