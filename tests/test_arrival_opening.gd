extends SceneTree
## Production ferry movie is the opening actually selected by the game.
const PRESENTATION := preload("res://runtime/OpeningPresentation.gd")
var failures: Array[String] = []
var completions: Array[bool] = []
var checks := 0

func _initialize() -> void:
	# Este teste confere a abertura: o runner a pula por padrão (Arrival.skip_opening).
	OS.set_environment("GETECO_SKIP_OPENING", "0")
	run.call_deferred()

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
	check(paused and root.disable_3d, "ferry opening owns pause and suspends hidden city rendering")
	check(film.video.stream != null and film.video.stream.resource_path.ends_with("/ferry/arrival.ogv"), "opening selects the produced boat movie")
	film._show_caption(16.1)
	# 16/10: o stem português usa o elenco dirigido, que diz "Vim atrás do meu irmão".
	check("Vim atrás do meu irmão" in film.subtitle.text, "Dante explains the boat journey")
	film._show_caption(31.1)
	check("Vicente" in film.subtitle.text and "lembrança" in film.subtitle.text, "phone call appears as a memory aboard the ferry")
	film._show_caption(3.0)
	check(film.subtitle.text.is_empty(), "quiet ferry scene has no decorative captions")
	await create_timer(.1).timeout
	film.request_skip()
	var frozen: float = film.video.stream_position
	await create_timer(.1).timeout
	check(film.skip_dialog.visible and is_equal_approx(film.video.stream_position,frozen), "skip confirmation pauses the ferry movie")
	film.skip_dialog.hide()
	film.skip_dialog.canceled.emit()
	await create_timer(.1).timeout
	check(not film.video.paused and film.stems.all(func(stem): return not stem.stream_paused), "cancel resumes video and both audio stems")
	film.skip()
	film.skip()
	await create_timer(.5).timeout
	check(completions == [true] and not paused and root.disable_3d == previous_3d, "skip completes exactly once and restores the world")
	TranslationServer.set_locale("en")
	layer = present()
	layer.film._show_caption(16.1)
	check("I'm here to see my brother" in layer.film.subtitle.text, "ferry movie has English subtitles")
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
