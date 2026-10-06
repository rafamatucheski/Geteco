extends SceneTree
## Real current opening playback, ownership of pause/rendering, and save checkpoint.
const PRESENTATION := preload("res://runtime/OpeningPresentation.gd")
var failures: Array[String] = []
var completions: Array[bool] = []
var checks := 0

func _initialize() -> void: run.call_deferred()

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
	check(paused and root.disable_3d, "home opening pauses the world and suspends its hidden render")
	presentation.film.skip()
	presentation.film.skip()
	await create_timer(.5).timeout
	check(not paused and completions == [true], "early skip completes exactly once and restores pause")
	check(root.disable_3d == previous_3d, "early skip restores world rendering")
	presentation = present()
	var film = presentation.film
	await create_timer(.5).timeout
	check(film.elapsed > 0 and film.image.texture != null, "real home timeline advances with established artwork")
	check(film.music.playing and film.music.bus == "Music", "music uses the user's separate music bus")
	film.request_skip()
	var frozen: float = film.elapsed
	await create_timer(.25).timeout
	check(film.skip_dialog.visible and is_equal_approx(film.elapsed,frozen), "skip confirmation freezes the home timeline")
	check(film.music.stream_paused, "skip confirmation freezes music")
	film.skip_dialog.hide()
	film.skip_dialog.canceled.emit()
	await create_timer(.25).timeout
	check(film.elapsed > frozen and not film.music.stream_paused, "cancel resumes image and audio at the same point")
	film._show_caption(float(film.line_times[1][0])+.1)
	check("Seu irmão está em Harbor" in film.subtitle.text, "home call points to the living brother")
	film._show_caption(float(film.line_times[3][0])+.1)
	check("na chegada" in film.subtitle.text, "caller promises the direct arrival meeting")
	film._show_caption(3.0)
	check(film.subtitle.text.is_empty(), "quiet shots clear the captions")
	var voiced := 0
	for index in film._recorded_lines.size():
		var stream: AudioStream = film._recorded_lines[index]
		if stream == null: continue
		voiced += 1
		check(float(film.line_times[index][1])-float(film.line_times[index][0]) >= stream.get_length()+.349, "home call keeps the complete recorded performance inside its caption window")
	if "--require-pt-voices" in OS.get_cmdline_user_args(): check(voiced == 5,"all five current home call takes are imported")
	check(film.duration >= float(film.line_times[-1][1])+.5,"travel and fade remain after the final spoken line")
	var quick := "--skip-full-playback" in OS.get_cmdline_user_args()
	if quick: film.skip()
	else: print("OPENING waiting for the real authored home timeline")
	var deadline := Time.get_ticks_msec()+ceili((film.duration+.5)*1000.0)
	while is_instance_valid(presentation) and Time.get_ticks_msec() < deadline:
		await process_frame
	check(not is_instance_valid(presentation) and completions == [true,quick] and not paused, "authored ending completes once and releases the world")
	check(root.disable_3d == previous_3d, "natural completion restores rendering")
	if is_instance_valid(presentation): presentation.free()
	TranslationServer.set_locale("en")
	presentation = present()
	presentation.film._show_caption(float(presentation.film.line_times[1][0])+.1)
	check("Your brother is in Harbor" in presentation.film.subtitle.text, "English home subtitles follow locale")
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
	check(restored.restore_state(serialized) and restored.opening_completed, "serialized current checkpoint prevents repeating the completed home call")
	arrival.free()
	restored.free()
	print("OPENING checks=",checks," failures=",failures)
	quit(0 if failures.is_empty() else 1)
