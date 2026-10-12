extends SceneTree
## Contract fixtures stay in memory and never publish or approve production takes.
const VOICE := preload("res://audio/ExpressiveVoice.gd")
const BANK := preload("res://audio/DirectedVoiceBank.gd")
const SURFACE := preload("res://audio/VisibleDialogueVoice.gd")
const ACTOR := preload("res://audio/ActorDialogueVoice.gd")
const FERRY := preload("res://cutscenes/opening/ferry/FerryFilm.gd")
const SESSION := preload("res://runtime/FullSession.gd")
const SOURCE := "Coloca o cinto, Dante. Agora deixa comigo."
var checks := 0
var failures: Array[String] = []

class Body extends Node3D:
	var health := 100.0

func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); push_error(label)

func run() -> void:
	var previous_env := OS.get_environment("GETECO_DIRECTED_VOICES")
	OS.set_environment("GETECO_DIRECTED_VOICES", "1")
	var settings := root.get_node("V2Settings")
	var old_voice: String = settings.voice_language
	var old_text: String = settings.text_language
	var direction := BANK._json(BANK.DIRECTION)
	var row: Dictionary = {}
	for candidate in direction.get("lines", []):
		if candidate.key == "2f74ccc16ed52b718b42204c49235f59574f5f599fab5aca4763f109dce41430": row = candidate
	check(not row.is_empty(), "Jessica authored source is present")
	if row.is_empty(): quit(1); return
	BANK.canonical(str(row.source), "jessica")
	var original_takes := BANK._takes.duplicate(true)
	var original_streams := BANK._streams.duplicate()
	var paths := {"pt_BR":"res://audio/mission_voices/directed/pt_BR/2f74ccc16ed52b718b42204c49235f59574f5f599fab5aca4763f109dce41430_18bf54be801ce782.wav",
		"en":"res://audio/mission_voices/directed/en/2f74ccc16ed52b718b42204c49235f59574f5f599fab5aca4763f109dce41430_33c4e8cdd9fd291b.wav"}
	BANK._takes = {"pt_BR":{}, "en":{}}
	for language in paths:
		BANK._takes[language][row.key] = {"path":paths[language], "spoken_text":row.spoken_en if language == "en" else row.spoken_pt,
			"signature":"a".repeat(64), "character_id":"jessica", "persona":"jessica", "source":row.source, "voice_gender":"female",
			"language":language, "duration_seconds":4.0, "status":"generated", "technical_validation":{"passed":true}, "artistic_review":"pending",
			"anchor_id":"jessica", "anchor_sha256":"b".repeat(64)}
	var shown := VOICE.presentation(str(row.source), "jessica", "pt_BR", "en", "jessica")
	check(shown.directed and shown.stream != null, "Technically validated generated take plays without fictitious artistic approval")
	check(shown.message == row.spoken_en and shown.voice_text == row.spoken_pt, "English captions and Portuguese audio select corresponding authored versions independently")
	check(is_zero_approx(VOICE.playback_volume(shown.stream, -8.0)), "Directed normalized PT take does not inherit the legacy minus-eight mix")
	shown.stream.set_meta("directed_gain_db", 1.25)
	check(is_equal_approx(VOICE.playback_volume(shown.stream), 1.25), "Directed playback uses explicit calibrated gain")
	shown.stream.set_meta("directed_gain_db", 0.0)
	check(VOICE.presentation(str(row.spoken_en), "jessica", "en", "pt_BR").source_key == row.key, "Localized rewritten alias resolves to original key")
	check(VOICE.presentation(str(row.source), "jessica", "en", "pt_BR", "cida").stream == null, "Explicit wrong identity is silent")
	for field in ["voice_gender", "language", "character_id", "source", "spoken_text", "persona", "signature", "path", "anchor_id", "anchor_sha256"]:
		var original: Variant = BANK._takes.pt_BR[row.key][field]
		BANK._takes.pt_BR[row.key][field] = "invalid"
		check(BANK.resolve(row, "pt_BR", "jessica").is_empty(), "Refuse mismatched take field: " + field)
		BANK._takes.pt_BR[row.key][field] = original
	BANK._takes.pt_BR[row.key].technical_validation.passed = false
	check(BANK.resolve(row, "pt_BR").is_empty(), "Failed technical validation cannot become an active take")
	BANK._takes.pt_BR[row.key].technical_validation.passed = true
	for field in ["transcription_validation", "gender_validation"]:
		BANK._takes.pt_BR[row.key][field] = {"status":"failed"}
		check(BANK.resolve(row, "pt_BR").is_empty(), "Explicit failed review cannot play: " + field)
		BANK._takes.pt_BR[row.key].erase(field)
	OS.set_environment("GETECO_DIRECTED_VOICES", "0")
	shown = VOICE.presentation(str(row.source), "jessica", "pt_BR", "pt_BR")
	check(not shown.directed and shown.message == row.source, "Diagnostic baseline restores legacy words and audio selection together")
	OS.set_environment("GETECO_DIRECTED_VOICES", "1")
	settings.voice_language = "pt_BR"
	settings.text_language = "pt_BR"
	var label := Label.new()
	label.text = "JESSICA: " + str(row.source)
	root.add_child(label)
	var player := SURFACE.attach(label, str(row.source), "jessica", "jessica")
	check(player.playing and label.text == "JESSICA: " + str(row.spoken_pt), "Visible caption and directed audio start together with prefix preserved")
	settings.text_language = "en"
	check(label.text == "JESSICA: " + str(row.spoken_en) and player.stream.get_meta("voice_language") == "pt_BR", "Live subtitle change keeps audio language")
	settings.voice_language = "en"
	check(player.playing and player.stream.get_meta("voice_language") == "en", "Live voice change restarts the matching language on the same surface")
	label.hide()
	check(not player.playing, "Hiding the surface stops speech")
	check(player.stream == null, "Hidden dialogue surface releases its retained PCM")
	label.show()
	player.refresh(true)
	player.finished.emit()
	check(not player.playing and player.stream == null, "Natural surface completion releases its retained PCM")
	label.free()
	var bodies: Array[Body] = []
	for index in 4:
		var body := Body.new()
		root.add_child(body)
		bodies.append(body)
		ACTOR.speak(body, str(row.source), {"persona":"jessica", "character_id":"jessica", "gender":"female"})
	check(not bodies[0].get_node(ACTOR.PLAYER_NAME).playing and bodies[3].get_node(ACTOR.PLAYER_NAME).playing, "Fourth spatial voice stops oldest, preserving three active voices")
	var active_player: AudioStreamPlayer3D = bodies[3].get_node(ACTOR.PLAYER_NAME)
	paused = true
	check(not active_player.can_process(), "Spatial player inherits scene pause")
	paused = false
	bodies[3].health = 0
	active_player._process(.3)
	check(not active_player.playing, "Death stops the body's active speech")
	check(active_player.stream == null, "Stopped actor releases its PCM outside the bounded cache")
	check(ACTOR.speak(bodies[0], str(row.source), {"persona":"jessica", "character_id":"jessica", "gender":"male"}).stream == null, "Gender mismatch never borrows a recording")
	ACTOR.stop_all()
	for body in bodies: body.free()
	var surface_body := Body.new()
	root.add_child(surface_body)
	var bubble := Label3D.new()
	surface_body.add_child(bubble)
	var binding := {"persona":"jessica", "character_id":"jessica", "gender":"female"}
	ACTOR.speak(surface_body, str(row.source), binding, bubble)
	var bubble_player: AudioStreamPlayer3D = surface_body.get_node(ACTOR.PLAYER_NAME)
	bubble.hide()
	check(not bubble_player.playing and bubble_player.stream == null, "Hiding a 3D caption immediately releases its voice")
	bubble.show()
	ACTOR.speak(surface_body, str(row.source), binding, bubble)
	bubble.free()
	check(not bubble_player.playing and bubble_player.stream == null, "Freeing a subtitle surface cancels its emitter's take")
	surface_body.free()
	if "--metadata-only" in OS.get_cmdline_user_args():
		pass
	elif "--no-save" not in OS.get_cmdline_user_args():
		check(false, "Real dialogue integration requires isolated APPDATA and --no-save")
	else:
		var world = load("res://Main.tscn").instantiate()
		world.set_meta("skip_arrival", true)
		root.add_child(world)
		current_scene = world
		var deadline := Time.get_ticks_msec() + 90000
		while Time.get_ticks_msec() < deadline:
			await process_frame
			if world.session != null and world.session.ready_for_play: break
		check(world.session != null and world.session.ready_for_play, "Real Main becomes ready with directed metadata enabled")
		if world.session != null and world.session.ready_for_play:
			var session = world.session
			world.gameplay.god_mode = true
			world.player.controlled_automatically = true
			settings.text_language = "pt_BR"
			settings.voice_language = "en"
			var completed := [0]
			session.show_dialogue([{"speaker":"JESSICA", "message":row.source, "character_id":"jessica"}], func(): completed[0] += 1)
			check(session.dialogue_card.message.text == row.spoken_pt and session.dialogue_voice.stream.get_meta("voice_language") == "en", "Real dialogue card uses matching rewritten PT caption with EN audio")
			check(is_zero_approx(session.dialogue_voice.volume_db), "Directed English dialogue uses normalized gain without legacy attenuation")
			settings.text_language = "en"
			check(session.dialogue_card.message.text == row.spoken_en and completed[0] == 0, "Live caption change preserves current dialogue and callback")
			settings.voice_language = "pt_BR"
			check(session.dialogue_voice.playing and session.dialogue_voice.stream.get_meta("voice_language") == "pt_BR", "Real session replaces active voice after language change")
			session.interrupt_dialogue()
			check(not session.dialogue_voice.playing and completed[0] == 0 and not session.dialogue_card.visible, "Directed dialogue recovery stops audio without completing the mission callback")
			session.close_menu()
			session.show_speech("JESSICA", str(row.source), .1, true, "jessica", str(row.source), "jessica")
			check(session.speech_caption.text.contains(str(row.spoken_en)) and session.notice_time >= session.speech_voice.stream.get_length(), "Directed ambient caption remains for its complete matching take")
			session.show_speech("JESSICA", "Mensagem já localizada pelo emissor", 2.0, false)
			check(session.speech_caption.text.contains("Mensagem já localizada pelo emissor") and not session.speech_voice.playing, "Prelocalized spatial notices are not rewritten or double-voiced")
			session.show_speech("JESSICA", str(row.spoken_en), .1, false, "jessica", str(row.source), "jessica", str(row.source_section))
			settings.text_language = "pt_BR"
			check(session.speech_caption.text.contains(str(row.spoken_pt)) and not session.speech_voice.playing, "Canonical spatial warning changes subtitle language without starting a duplicate 2D voice")
			settings.voice_language = "en"
			check(session.notice_time >= BANK.stream(BANK._takes.en[row.key]).get_length() and not session.speech_voice.playing, "Voice-language change extends the externally voiced warning without borrowing its playback")
			var nearby := Body.new()
			world.add_child(nearby)
			nearby.global_position = world.player.global_position + Vector3.RIGHT
			ACTOR.speak(nearby, str(row.source), binding)
			var spatial: AudioStreamPlayer3D = nearby.get_node(ACTOR.PLAYER_NAME)
			check(spatial.playing and spatial.volume_db > -1.0 and spatial.attenuation_model == AudioStreamPlayer3D.ATTENUATION_DISABLED, "Nearby speech is audible relative to player despite elevated isometric camera")
			var distant := Body.new()
			world.add_child(distant)
			distant.global_position = world.player.global_position + Vector3.RIGHT * 60.0
			ACTOR.speak(distant, str(row.source), binding)
			check(not distant.has_node(ACTOR.PLAYER_NAME) and spatial.playing, "Distant speech creates no player and cannot evict a nearby voice")
			nearby.global_position = world.player.global_position + Vector3.RIGHT * 46.0
			spatial._process(.3)
			check(not spatial.playing and spatial.stream == null, "Moving beyond hearing range releases the active voice")
		world.queue_free()
		await process_frame
		await process_frame
	settings.voice_language = "en"
	var film := FERRY.new()
	root.add_child(film)
	film.set_process(false)
	check(not film.voice_track.directed and film.stems.size() == 3, "Partial ferry bank preserves complete legacy EN mix and ambience/music")
	film.voice_track.player.stream = BANK.stream(BANK._takes.en[row.key])
	film.voice_track.player.play()
	film.pause_playback()
	check(film.video.paused and film.voice_track.player.stream_paused, "Ferry pause includes directed speech player")
	film.free()
	BANK._takes = original_takes
	BANK._streams = original_streams
	settings.voice_language = old_voice
	settings.text_language = old_text
	OS.set_environment("GETECO_DIRECTED_VOICES", previous_env)
	await process_frame
	print("DIRECTED_VOICE_RUNTIME checks=%d failures=%s" % [checks, failures])
	quit(0 if failures.is_empty() else 1)
