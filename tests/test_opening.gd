extends SceneTree
## Exercise real movie playback, pause ownership and completion (no synthetic clock).
const PRESENTATION = preload("res://runtime/OpeningPresentation.gd")
var failures: Array[String] = []
var completions: Array[bool] = []
var checks := 0

func _initialize() -> void: run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures.append(label); push_error(label)

func present() -> CanvasLayer:
	var presentation := PRESENTATION.new()
	presentation.completed.connect(func(was_skipped: bool): completions.append(was_skipped))
	root.add_child(presentation)
	return presentation

func run() -> void:
	Engine.max_fps = 120
	var previous_locale := TranslationServer.get_locale()
	TranslationServer.set_locale("pt_BR")
	var previous_3d_disabled := root.disable_3d
	var presentation = present()
	check(paused, "opening owns the world pause")
	check(root.disable_3d, "opaque movie suspends the hidden live city render")
	presentation.film.skip()
	presentation.film.skip()
	await create_timer(.5).timeout
	check(not paused and completions == [true], "skip before deferred playback completes once and restores pause")
	check(root.disable_3d == previous_3d_disabled, "early skip restores viewport rendering")
	presentation = present()
	var film = presentation.film
	await create_timer(.5).timeout
	check(film.video.is_playing() and film.video.stream_position > 0.0, "real movie decoder advances")
	check(film.stems.size() == 2 and film.stems[0].playing and film.stems[1].playing, "ambience and music play on separate buses")
	film.request_skip()
	var frozen_position: float = film.video.stream_position
	await create_timer(.25).timeout
	check(film.skip_dialog.visible and film.video.paused and absf(film.video.stream_position-frozen_position) < .04, "skip confirmation freezes movie clock")
	check(film.stems[0].stream_paused and film.stems[1].stream_paused, "skip confirmation freezes audio stems")
	film.skip_dialog.hide()
	film.skip_dialog.canceled.emit()
	await create_timer(.25).timeout
	check(not film.video.paused and film.video.stream_position > frozen_position, "cancel resumes the movie")
	check(not film.stems[0].stream_paused and not film.stems[1].stream_paused, "cancel resumes audio stems")
	film._show_caption(31.2)
	check("Vicente" in film.subtitle.text and "lembrança" in film.subtitle.text, "Portuguese caption identifies the remembered call")
	film._show_caption(28.5)
	check(film.subtitle.text.is_empty(), "dialogue gaps clear captions")
	var quick := "--skip-full-playback" in OS.get_cmdline_user_args()
	if quick: film.skip()
	else: print("OPENING waiting for the real movie's authored ending")
	var deadline := Time.get_ticks_msec()+85000
	while is_instance_valid(presentation) and Time.get_ticks_msec() < deadline:
		await process_frame
	check(not is_instance_valid(presentation) and completions == [true,quick] and not paused, "completion emits once and releases world pause")
	check(root.disable_3d == previous_3d_disabled, "completion restores live rendering")
	if is_instance_valid(presentation): presentation.free()
	TranslationServer.set_locale("en")
	presentation = present()
	presentation.film._show_caption(16.5)
	check("brother" in presentation.film.subtitle.text, "English subtitles follow locale with original Portuguese audio")
	presentation.free()
	check(not paused and completions == [true,quick] and root.disable_3d == previous_3d_disabled, "disposal restores viewport and pause without completing arrival")
	paused = true
	root.disable_3d = true
	presentation = present()
	presentation.free()
	check(paused and root.disable_3d, "disposal preserves existing viewport and pause state")
	paused = false
	root.disable_3d = previous_3d_disabled
	await process_frame
	TranslationServer.set_locale(previous_locale)
	var arrival := preload("res://runtime/Arrival.gd").new()
	arrival.opening_completed = true
	arrival.phase = "disembark"
	var restored := preload("res://runtime/Arrival.gd").new()
	var serialized: Variant = JSON.parse_string(JSON.stringify(arrival.snapshot()))
	check(restored.restore_state(serialized) and restored.opening_completed, "serialized checkpoint prevents replay after loading")
	arrival.free()
	restored.free()
	print("OPENING checks=",checks," failures=", failures)
	quit(0 if failures.is_empty() else 1)
