extends SceneTree
## Actual production manifest and WAVs only. Run after the first 22 Ferry takes publish.
## Headless calls exercise transport callbacks; they do not certify listening or rendered timing.
const VOICE := preload("res://audio/ExpressiveVoice.gd")
const BANK := preload("res://audio/DirectedVoiceBank.gd")
const TRACK := preload("res://cutscenes/opening/ferry/FerryVoiceTrack.gd")
const FILM := preload("res://cutscenes/opening/ferry/FerryFilm.gd")
var checks := 0
var failures: Array[String] = []
var report := {"fixtures":false, "legacy_fallback_allowed":false,
	"scope":"Real production takes, film nodes and transport callbacks; clock jumps and EOF signals invoked diagnostically",
	"artistic_review":"not_asserted", "rendered_timing_review":"not_asserted_by_headless_execution"}

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)

func run() -> void:
	if not BANK.enabled() or not FileAccess.file_exists(BANK.MANIFEST):
		push_error("Ferry production bank is not ready; require runtime.json and GETECO_DIRECTED_VOICES=1")
		quit(2)
		return
	if "--no-save" not in OS.get_cmdline_user_args():
		push_error("Run with isolated APPDATA and --no-save")
		quit(2)
		return
	var lines: Array = BANK._json("res://cutscenes/opening/ferry/timing.json").get("lines", [])
	check(lines.size() == 11, "Ferry still has all eleven authored beats")
	var track := TRACK.new()
	root.add_child(track)
	var windows := {}
	var window_failures := {}
	var modes := {}
	var actual_pairs := 0
	for language in ["pt_BR", "en"]:
		modes[language] = track.configure(lines, language)
		windows[language] = track.windows.duplicate(true)
		window_failures[language] = track.failures.duplicate(true)
		check(track.windows.size() == 11, str(language) + ": every film window audited even after an earlier failure")
		for line in lines:
			var shown := VOICE.presentation(str(line.text), str(line.speaker), language, "pt_BR", "", "opening_ferry")
			var label := str(line.id) + ": " + str(language)
			check(shown.directed and shown.stream != null, label + ": validated production WAV, no legacy fallback")
			if not shown.directed or shown.stream == null: continue
			actual_pairs += 1
			var row := BANK.canonical(str(line.text), str(line.speaker))
			var profile := BANK.profile(row)
			var take := BANK.resolve(row, language, str(profile.character_id), "opening_ferry")
			check(not take.is_empty() and absf(shown.stream.get_length() - float(take.get("duration_seconds", 0.0))) <= .03, label + ": duration agrees with technical manifest")
			check(str(shown.stream.get_meta("character_id", "")) == str(profile.character_id), label + ": actor identity matches the beat")
			for text_language in ["pt_BR", "en"]:
				var caption := VOICE.presentation(str(line.text), str(line.speaker), language, text_language, str(profile.character_id), "opening_ferry")
				check(caption.directed and caption.message == str(row.spoken_en if text_language == "en" else row.spoken_pt), label + ": independent " + text_language + " caption")
		check(modes[language], str(language) + ": all eleven takes fit the film: " + JSON.stringify(track.failures))
	track.free()
	check(actual_pairs == 22, "All 22 actual Ferry language/take pairs load")
	report.windows = windows
	report.window_failures = window_failures
	report.directed_languages = modes
	report.actual_pairs = actual_pairs
	if bool(modes.get("pt_BR", false)) and bool(modes.get("en", false)):
		await _film_contracts()
		report.transport_executed = true
	else:
		report.transport_executed = false
		report.transport_pending_reason = "Both languages must have eleven complete takes that fit before directed transport can pass"
	_finish_report()

func _film_contracts() -> void:
	var settings := root.get_node("V2Settings")
	var old_voice: String = settings.voice_language
	var old_text: String = settings.text_language
	settings.voice_language = "pt_BR"
	settings.text_language = "pt_BR"
	var film := FILM.new()
	root.add_child(film)
	# Keep the real video/stems and deferred startup. Explicit jumps below probe
	# the speech scheduler without seeking the video decoder.
	film.set_process(false)
	var start_deadline := Time.get_ticks_msec() + 3000
	while not film._started and Time.get_ticks_msec() < start_deadline: await process_frame
	check(film._started and film.video.is_playing(), "Real film deferred startup begins video playback")
	check(film.voice_track.directed and film.video.volume_db <= -80.0, "Directed PT mutes the embedded legacy speech stem")
	check(film._legacy_english.stream == null and not film._legacy_english.playing, "Legacy EN speech is detached while directed speech is active")
	check(film.stems.size() == 2 and film.stems[0].playing and film.stems[1].playing, "Ambient sea/engine and music stems continue independently")
	for index in [0, 1, 4, 8]:
		var time: float = float(film.lines[index].start) + .15
		film.voice_track.update_clock(time)
		film._show_caption(time)
		await create_timer(.08).timeout
		check(film.voice_track.player.playing and film.voice_track.player.stream == film.voice_track.takes[index].stream,
			"Clock jump selects actual take for beat " + str(film.lines[index].id))
		check(film.voice_track.player.get_playback_position() >= .13, "Speech starts at the requested intra-take offset: " + str(film.lines[index].id))
		check(film.subtitle.text.ends_with(film.voice_track.caption(index, "pt")), "Film caption follows actual take: " + str(film.lines[index].id))
		check(is_equal_approx(film.voice_track.player.volume_db, VOICE.playback_volume(film.voice_track.player.stream)), "Film uses the calibrated directed gain: " + str(film.lines[index].id))
		if bool(film.lines[index].get("memory", false)):
			check(AudioServer.get_bus_effect_count(AudioServer.get_bus_index(film.voice_track.player.bus)) == 2, "Remembered phone retains its band-limited voice bus")
	var memory_bus: String = film.voice_track._memory_bus
	film.pause_playback()
	check(film.video.paused and film.voice_track.player.stream_paused and film.stems[0].stream_paused and film.stems[1].stream_paused, "Pause holds all film audio and video")
	settings.voice_language = "en"
	check(film.voice_track.directed and film.voice_track.player.stream_paused and film.video.volume_db <= -80.0, "Changing voice language while paused preserves pause and embedded-track mute")
	film.resume_playback()
	film.voice_track.update_clock(16.15)
	film._show_caption(16.15)
	check(not film.video.paused and not film.voice_track.player.stream_paused and film.voice_track.player.playing, "Resume and clock update play the replacement take")
	check(str(film.voice_track.player.stream.get_meta("voice_language", "")) == "en" and film.subtitle.text.ends_with(film.voice_track.caption(1, "pt")), "EN audio and PT subtitles remain independent after voice change")
	settings.text_language = "en"
	film._show_caption(16.15)
	check(film.subtitle.text.ends_with(film.voice_track.caption(1, "en")) and str(film.voice_track.player.stream.get_meta("voice_language", "")) == "en", "Text-language callback changes caption without changing the selected voice")
	film.request_skip()
	check(film.skip_dialog.visible and film._paused and film.voice_track.player.stream_paused, "Requesting skip pauses playback before confirmation")
	film.skip_dialog.hide()
	film.skip_dialog.canceled.emit()
	check(not film._paused and not film.voice_track.player.stream_paused, "Cancel-skip callback resumes speech")
	var skipped_events := [0]
	var finished_events := [0]
	film.skipped.connect(func(destination):
		skipped_events[0] += 1
		check(destination == FILM.DESTINATION, "Skip callback preserves arrival destination"))
	film.finished.connect(func(_destination): finished_events[0] += 1)
	film.skip_dialog.confirmed.emit()
	film.skip()
	await _wait_complete(film)
	check(skipped_events[0] == 1 and finished_events[0] == 0, "Confirmed skip completes exactly once and never emits normal completion")
	check(not film.video.is_playing() and not film.voice_track.player.playing and not film.stems[0].playing and not film.stems[1].playing, "Skip completion stops every active film track")
	check(film.video.volume_db <= -80.0, "Fade never raises the muted embedded dialogue")
	film.free()
	check(memory_bus.is_empty() or AudioServer.get_bus_index(memory_bus) < 0, "Removing the film removes its private phone bus")
	var completion := FILM.new()
	root.add_child(completion)
	completion.set_process(false)
	var completed_events := [0]
	completion.finished.connect(func(destination):
		completed_events[0] += 1
		check(destination == FILM.DESTINATION, "EOF callback preserves arrival destination"))
	completion.video.finished.emit()
	completion.video.finished.emit()
	await _wait_complete(completion)
	check(completed_events[0] == 1 and not completion._started, "EOF callback is idempotent and cancels a pending deferred startup")
	completion.free()
	settings.voice_language = old_voice
	settings.text_language = old_text

func _wait_complete(film: Control) -> void:
	var deadline := Time.get_ticks_msec() + 3000
	while not film._completed and Time.get_ticks_msec() < deadline: await process_frame
	check(film._completed, "Film transition fade reaches completion within the test deadline")

func _finish_report() -> void:
	report.checks = checks
	report.failures = failures
	report.cache_streams = BANK._streams.size()
	var path := "user://directed-ferry-production.json"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--report="): path = argument.trim_prefix("--report=")
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify(report, "\t") + "\n")
	for failure in failures: push_error(failure)
	print("DIRECTED_FERRY_PRODUCTION checks=%d pairs=%d failures=%d report=%s" % [checks, int(report.actual_pairs), failures.size(), path])
	quit(0 if failures.is_empty() else 1)
