extends SceneTree
const VOICE := preload("res://audio/ExpressiveVoice.gd")
const ARRIVAL := preload("res://runtime/ArrivalDialogue.gd")
const GARAGE := preload("res://data/GarageSequence.gd")
const BANK := "res://audio/mission_voices/maciota_baritone/"
var checks := 0
var failures := 0

# Keep the real dialogue controller/player; replace only the unrelated world UI.
class DialogueSession extends "res://runtime/FullSession.gd":
	func _ready() -> void:
		set_process(false)
		set_process_input(false)
		column = VBoxContainer.new()
		add_child(column)
		dialogue_voice = AudioStreamPlayer.new()
		add_child(dialogue_voice)
	func _menu(_title: String) -> void:
		for child in column.get_children():
			column.remove_child(child)
			child.queue_free()
	func close_menu() -> void:
		dialogue_voice.stop()
	func _present_dialogue_line(_line: Dictionary) -> void:
		pass

func _initialize() -> void: run.call_deferred()

func run() -> void:
	# Este contrato é do banco maciota_baritone; as falas da ElevenLabs o substituem de propósito
	# e têm teste próprio (test_elevenlabs_voices.gd).
	OS.set_environment("GETECO_ELEVENLABS_VOICES", "0")
	var settings := root.get_node("V2Settings")
	var original_language: String = settings.voice_language
	settings.voice_language = "pt_BR"
	var production: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(BANK + "production.json"))
	check(production.get("complete", false), "Complete Maciota bank is published")
	check(production.get("profile", {}).get("id", "") == "maciota_baritone_v1", "One fixed baritone profile")
	for line in production.get("lines", []):
		var stream := VOICE.recorded_line(line.text, line.persona)
		check(stream != null and stream.resource_path == line.path and stream.resource_path.begins_with(BANK), "Fixed bank resolves " + line.key)
		if stream != null:
			check(absf(stream.get_length() - float(line.seconds)) < .02, "Full take remains at authored speed")
			check(stream is AudioStreamWAV and stream.mix_rate == 24000 and not stream.stereo, "Mono 24 kHz PCM avoids added runtime effects")
	for source in [ARRIVAL.HOME_CALL, ARRIVAL.MEETING, ARRIVAL.TOUR, GARAGE.INTRO_LINES]:
		for line in source:
			if line[0] not in ["MACIOTA", "VOZ AO TELEFONE"]: continue
			check(VOICE.recorded_line(line[1], "caller" if line[0] == "VOZ AO TELEFONE" else "maciota") != null, "Arrival/garage has every exact Maciota take")
	for filename in ["first-favors-dialogue.json", "cobra-dialogue.json", "jessica-dialogue.json"]:
		var dialogue: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/campaign/" + filename))
		for section in dialogue.values():
			if not section is Array: continue
			for line in section:
				if str(line.get("speaker", "")).to_lower() == "maciota":
					check(VOICE.recorded_line(line.pt, "maciota") != null, "Campaign Maciota take exists")
	for phrase in [GARAGE.GREETING, GARAGE.REQUEST, GARAGE.THANKS]:
		check(VOICE.recorded_line(phrase, "maciota") != null, "Restored garage save uses same voice")
	var phrase: String = ARRIVAL.MEETING[0][1]
	check(VOICE.recorded_line(phrase, "MACIOTA") == VOICE.recorded_line(phrase, "maciota"), "Speaker case cannot select another voice")
	# A removed/missing take must not silently revive a different old actor.
	var key := VOICE.recording_key(phrase, "maciota")
	var fixed_path = VOICE.maciota_recordings[key]
	VOICE.maciota_recordings.erase(key)
	check(VOICE.recorded_line(phrase, "maciota") == null, "Missing fixed take cannot use old VoiceDesign voice")
	VOICE.maciota_recordings[key] = fixed_path
	var dante := VOICE.recorded_line("Alô?", "dante")
	check(dante != null and not dante.resource_path.begins_with(BANK), "Dante keeps his existing recording")
	check(VOICE.recorded_line("texto sem tomada", "maciota") == null, "Missing dialogue never produces non-verbal dub")
	var session := DialogueSession.new()
	root.add_child(session)
	session.show_dialogue([{ "speaker": "MACIOTA · Oficina", "message": GARAGE.INTRO_LINES[0][1] },
		{ "speaker": "DANTE", "message": "Alô?" }, { "speaker": "CALLER", "message": ARRIVAL.HOME_CALL[1][1] }])
	check(session.dialogue_voice.playing and session.dialogue_voice.stream.resource_path.begins_with(BANK), "Real workshop controller starts fixed Maciota take")
	check(session.dialogue_voice.pitch_scale == 1.0 and session.dialogue_voice.volume_db == -8.0, "Workshop preserves recording pitch and arrival level")
	session._advance_dialogue()
	check(session.dialogue_voice.stream == dante and session.dialogue_voice.volume_db == 0.0, "Advancing to Dante restores his original level")
	session._advance_dialogue()
	check(session.dialogue_voice.playing and session.dialogue_voice.pitch_scale == 1.0 and session.dialogue_voice.volume_db == -8.0, "Caller uses the same pitch and level")
	session._advance_dialogue()
	check(not session.dialogue_voice.playing, "Closing dialogue stops the recording")
	session.free()
	settings.voice_language = original_language
	await process_frame
	print("MACIOTA_VOICE checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
