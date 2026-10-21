extends SceneTree
## Real current opening playback, ownership of pause/rendering, and save checkpoint.
const PRESENTATION := preload("res://runtime/OpeningPresentation.gd")
var failures: Array[String] = []
var completions: Array[bool] = []
var checks := 0

func _initialize() -> void:
	# Este teste confere a abertura: o runner a pula por padrão (Arrival.skip_opening).
	OS.set_environment("GETECO_SKIP_OPENING", "0")
	run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures.append(label); push_error(label)

func present() -> CanvasLayer:
	var layer := PRESENTATION.new()
	layer.completed.connect(func(was_skipped: bool): completions.append(was_skipped))
	root.add_child(layer)
	return layer

func run() -> void:
	var previous_locale := TranslationServer.get_locale()
	TranslationServer.set_locale("pt_BR")
	var previous_3d := root.disable_3d
	var presentation := present()
	check(paused and root.disable_3d, "ferry opening pauses the world and suspends its hidden render")
	presentation.film.skip()
	presentation.film.skip()
	await create_timer(.5).timeout
	check(not paused and completions == [true], "early skip completes exactly once and restores pause")
	check(root.disable_3d == previous_3d, "early skip restores world rendering")
	presentation = present()
	var film = presentation.film
	await create_timer(.5).timeout
	check(film.video.stream != null and film.video.is_playing(), "real ferry movie starts with the production asset")
	check(film.stems.size() == 2 and film.stems[1].playing and film.stems[1].bus == "Music", "music uses the user's separate music bus")
	film.request_skip()
	var frozen: float = film.video.stream_position
	await create_timer(.25).timeout
	check(film.skip_dialog.visible and is_equal_approx(film.video.stream_position,frozen), "skip confirmation freezes the ferry movie")
	check(film.stems.all(func(stem): return stem.stream_paused), "skip confirmation freezes both audio stems")
	film.skip_dialog.hide()
	film.skip_dialog.canceled.emit()
	await create_timer(.25).timeout
	check(not film.video.paused and film.stems.all(func(stem): return not stem.stream_paused), "cancel resumes movie and audio at the same point")
	film._show_caption(16.1)
	check("Vim encontrar meu irmão" in film.subtitle.text, "ferry conversation explains Dante's arrival")
	film._show_caption(31.1)
	check("Vicente" in film.subtitle.text and "lembrança" in film.subtitle.text, "phone call is a memory aboard the ferry")
	film._show_caption(3.0)
	check(film.subtitle.text.is_empty(), "quiet shots clear the captions")
	check(film.lines.size() == 11 and film.video.bus == "SFX", "production ferry timing and embedded voice are loaded")
	check(film.duration >= float(film.lines[-1].end)+.5,"travel and fade remain after the final spoken line")
	var quick := "--skip-full-playback" in OS.get_cmdline_user_args()
	if quick: film.skip()
	else: print("OPENING waiting for the real authored ferry movie")
	var deadline := Time.get_ticks_msec()+ceili((film.duration+.5)*1000.0)
	while is_instance_valid(presentation) and Time.get_ticks_msec() < deadline:
		await process_frame
	check(not is_instance_valid(presentation) and completions == [true,quick] and not paused, "authored ending completes once and releases the world")
	check(root.disable_3d == previous_3d, "natural completion restores rendering")
	if is_instance_valid(presentation): presentation.free()
	TranslationServer.set_locale("en")
	presentation = present()
	presentation.film._show_caption(16.1)
	check("I'm here to see my brother" in presentation.film.subtitle.text, "English ferry subtitles follow locale")
	presentation.free()
	check(not paused and root.disable_3d == previous_3d and completions == [true,quick], "disposal releases the world without completing arrival")
	paused = true
	root.disable_3d = true
	presentation = present()
	presentation.free()
	check(paused and root.disable_3d, "disposal preserves pre-existing pause and viewport state")
	paused = false
	root.disable_3d = previous_3d
	TranslationServer.set_locale(previous_locale)
	var arrival := preload("res://runtime/Arrival.gd").new()
	arrival.opening_completed = true
	arrival.phase = "disembark"
	var restored := preload("res://runtime/Arrival.gd").new()
	var serialized: Variant = JSON.parse_string(JSON.stringify(arrival.snapshot()))
	check(restored.restore_state(serialized) and restored.opening_completed, "serialized current checkpoint prevents repeating the completed ferry movie")
	arrival.free()
	restored.free()
	print("OPENING checks=",checks," failures=",failures)
	quit(0 if failures.is_empty() else 1)
