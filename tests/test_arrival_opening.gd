extends SceneTree
## Current Harbor opening: the call happens at home and never reveals the prison plot.
const PRESENTATION := preload("res://runtime/OpeningPresentation.gd")
var failures: Array[String] = []
var completions: Array[bool] = []
var checks := 0

func _initialize() -> void: run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message); push_error(message)

func present() -> CanvasLayer:
	var layer := PRESENTATION.new()
	layer.completed.connect(func(skipped: bool): completions.append(skipped))
	root.add_child(layer)
	return layer

func run() -> void:
	var previous_locale := TranslationServer.get_locale()
	TranslationServer.set_locale("pt_BR")
	var previous_3d := root.disable_3d
	var layer := present()
	var film = layer.film
	check(paused and root.disable_3d, "home opening owns pause and suspends hidden city rendering")
	film._show_caption(float(film.line_times[1][0])+.1)
	check("Seu irmão está em Harbor" in film.subtitle.text, "home call says Vicente is alive and in Harbor")
	film._show_caption(float(film.line_times[3][0])+.1)
	check("na chegada" in film.subtitle.text, "caller promises to meet Dante on arrival")
	film._show_caption(3.0)
	check(film.subtitle.text.is_empty(), "quiet home scene has no decorative captions")
	await create_timer(.1).timeout
	film.request_skip()
	var frozen: float = film.elapsed
	await create_timer(.1).timeout
	check(film.skip_dialog.visible and is_equal_approx(film.elapsed,frozen), "skip confirmation pauses the home timeline")
	film.skip_dialog.hide()
	film.skip_dialog.canceled.emit()
	await create_timer(.1).timeout
	check(film.elapsed > frozen, "cancel resumes the same timeline")
	film.skip()
	film.skip()
	await create_timer(.5).timeout
	check(completions == [true] and not paused and root.disable_3d == previous_3d, "skip completes exactly once and restores the world")
	TranslationServer.set_locale("en")
	layer = present()
	layer.film._show_caption(float(layer.film.line_times[1][0])+.1)
	check("Your brother is in Harbor" in layer.film.subtitle.text, "home call has English subtitles")
	layer.free()
	check(not paused and root.disable_3d == previous_3d and completions == [true], "disposal releases pause without completing arrival")
	paused = true
	root.disable_3d = true
	layer = present()
	layer.free()
	check(paused and root.disable_3d, "existing world pause and rendering state survive disposal")
	paused = false
	root.disable_3d = previous_3d
	TranslationServer.set_locale(previous_locale)
	print("ARRIVAL_OPENING checks=",checks," failures=",failures)
	quit(0 if failures.is_empty() else 1)
