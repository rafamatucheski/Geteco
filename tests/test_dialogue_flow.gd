extends SceneTree
## Real Main/session: caption, voice, modal input and recovery share one lifecycle.
const HOME := preload("res://cutscenes/opening/home/HomeCall.gd")
const ARRIVAL := preload("res://runtime/ArrivalDialogue.gd")
var checks := 0
var failures: Array[String] = []
var completions := 0

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)

func run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args(): push_error("Use isolated APPDATA and --no-save"); quit(2); return
	var settings := root.get_node("V2Settings")
	var previous_voice: String = settings.voice_language
	var previous_locale := TranslationServer.get_locale()
	settings.voice_language = "en"
	TranslationServer.set_locale("pt_BR")
	var world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	root.add_child(world)
	current_scene = world
	var deadline := Time.get_ticks_msec()+90000
	while Time.get_ticks_msec()<deadline:
		await process_frame
		if world.session != null and world.session.ready_for_play: break
	check(world.session != null and world.session.ready_for_play, "Real session becomes playable")
	if world.session == null or not world.session.ready_for_play: quit(1); return
	var session = world.session
	world.gameplay.god_mode = true
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	check(await session.enter_place("maciota", false), "Real garage transition succeeds")
	var line := {"speaker":"MACIOTA", "message":ARRIVAL.MEETING[0][1]}
	session.show_dialogue([line, {"speaker":"DANTE", "message":"Alô?"}], func(): completions += 1)
	await process_frame
	check(session.modal and session.dialogue_open and world.player.input_locked, "Conversation retains gameplay input lock")
	check(session.dialogue_card.visible and not session.panel.visible, "Conversation uses the compact card without the old menu panel")
	check(session.dialogue_card.message.text == line.message, "English voice leaves Portuguese text intact")
	check(session.dialogue_voice.playing and session.dialogue_voice.stream.resource_path.begins_with("res://audio/mission_voices/en/"), "Real dialogue player uses English")
	check(session.dialogue_card.advance_button.has_focus(), "Continue receives real keyboard/controller focus")
	var card_id: int = session.dialogue_card.get_instance_id()
	var event := InputEventAction.new()
	event.action = "interact"
	event.pressed = true
	paused = true
	session._input(event)
	check(session.dialogue_card.speaker_label.text == "MACIOTA", "Paused menu input cannot advance the conversation underneath")
	paused = false
	session._input(event)
	check(session.dialogue_open and session.dialogue_card.speaker_label.text == "DANTE" and completions == 0, "One interaction advances exactly one line")
	check(is_equal_approx(session.dialogue_voice.volume_db, -8.0), "English Dante shares the opening and Maciota dialogue level")
	session.dialogue_card.advance_button.pressed.emit()
	check(completions == 1 and not session.modal and not session.dialogue_card.visible and not session.dialogue_voice.playing, "Completion closes UI/audio exactly once")
	check(not world.player.input_locked, "Closing a conversation restores movement")
	for cycle in 3:
		session.show_dialogue([line])
		session.close_menu()
	check(session.dialogue_card.get_instance_id() == card_id and not session.dialogue_voice.playing, "Repeated conversations reuse one card and leave no voice playing")
	session.show_speech("MACIOTA", ARRIVAL.TOUR[0][1], .1)
	check(session.speech_active and session.speech_caption.visible and not session.modal, "Ambient dialogue has its own readable caption without locking movement")
	check(session.notice_time >= session.speech_voice.stream.get_length(), "Caption remains for the entire English take")
	var remaining: float = session.notice_time
	paused = true
	await create_timer(.15).timeout
	check(is_equal_approx(remaining, session.notice_time) and not session.speech_caption.visible and session.speech_voice.stream_paused, "Pause freezes voice/caption lifetime and hides caption behind menus")
	paused = false
	await process_frame
	# SceneTree.process_frame is emitted before Node._process updates visibility.
	await process_frame
	check(session.speech_caption.visible and not session.speech_voice.stream_paused, "Resume restores the same spoken caption")
	session.show_message("Missão: R$ 500")
	check(not session.speech_active and not session.speech_voice.playing and session.notice.text == "Missão: R$ 500", "System notifications remain unvoiced even with a colon")
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://audio/mission_voices/en/catalog.json"))
	for entry in catalog.lines:
		if not str(entry.section).begins_with("spoken_notice:") or entry.aliases.is_empty(): continue
		session.show_message(entry.aliases[0])
		check(session.speech_active and session.speech_voice.playing, "Exact authored notice starts the selected character voice")
		break
	session.show_dialogue([line])
	check(not session.speech_active and not session.speech_voice.playing, "A conversation stops the previous ambient caption and voice")
	session.close_menu()
	settings.voice_language = "pt_BR"
	session.show_dialogue([line])
	check(session.dialogue_voice.stream.resource_path.begins_with("res://audio/mission_voices/maciota_baritone/"), "Switching back restores the stable Portuguese Maciota voice")
	session.close_menu()
	var guided_completions := [0]
	session.arrival.active = true
	session.arrival.controls_locked = false
	session.arrival._dialogue(ARRIVAL.MEETING, func(): guided_completions[0] += 1)
	var cancel := InputEventAction.new()
	cancel.action = "ui_cancel"
	cancel.pressed = true
	session._input(cancel)
	check(session.dialogue_open and session.dialogue_card.visible and session.arrival.dialogue_in_progress(), "Cancel cannot strand the guided arrival or orphan its voice")
	for index in ARRIVAL.MEETING.size(): session.dialogue_card.advance_button.pressed.emit()
	check(guided_completions[0] == 1 and not session.arrival.voice.playing and not session.modal, "Guided arrival completes once and stops its separate voice player")
	session.arrival._meeting_started = true
	session.arrival._dialogue(ARRIVAL.MEETING, func(): guided_completions[0] += 1)
	session.interrupt_dialogue()
	check(guided_completions[0] == 1 and not session.arrival._meeting_started and not session.arrival.dialogue_in_progress() and not session.arrival.voice.playing and not session.dialogue_card.visible, "Recovery interrupts guided speech without completing it or preventing a retry")
	session.close_menu()
	session.arrival.active = false
	for selected_voice in ["en", "pt_BR"]:
		settings.voice_language = selected_voice
		TranslationServer.set_locale("pt_BR" if selected_voice == "en" else "en")
		var film := HOME.new()
		root.add_child(film)
		film.set_process(false)
		var timing_ok := true
		var bank_ok := true
		for index in film._recorded_lines.size():
			var stream: AudioStream = film._recorded_lines[index]
			bank_ok = bank_ok and stream != null and str(stream.get_meta("voice_language", "")) == selected_voice
			timing_ok = timing_ok and stream != null and float(film.line_times[index][1])-float(film.line_times[index][0]) >= stream.get_length()
		check(bank_ok and timing_ok, "Home call %s audio matches preference and every shot contains its entire take" % selected_voice)
		film._show_caption(float(film.line_times[1][0])+.1)
		check(("Seu irmão" in film.subtitle.text) if selected_voice == "en" else ("Your brother" in film.subtitle.text), "Home caption locale is independent from its selected voice")
		film.free()
	settings.voice_language = previous_voice
	TranslationServer.set_locale(previous_locale)
	world.queue_free()
	await process_frame
	await process_frame
	print("DIALOGUE_FLOW checks=%d failures=%s" % [checks, failures])
	quit(0 if failures.is_empty() else 1)
