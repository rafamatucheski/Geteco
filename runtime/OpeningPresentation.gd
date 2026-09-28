extends CanvasLayer
## Hosts the approved prologue through departure; the native ferry replaces bus travel.
signal completed(skipped: bool)
var film: Control
var _previous_pause := false
var _owns_pause := false
var _translations: Array[Translation] = []

func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	var keys := ["CGI_SKIP_BUTTON", "CGI_SKIP_TITLE", "CGI_SKIP_BODY", "CGI_SKIP_OK", "CGI_SKIP_CANCEL"]
	var texts := {"pt":["Pular [Esc]", "Pular introdução?", "Deseja pular a introdução e continuar no cais?", "Pular", "Continuar assistindo"], "en":["Skip [Esc]", "Skip the intro?", "Skip the intro and continue at the passenger pier?", "Skip", "Keep watching"]}
	for locale in texts:
		var translation := Translation.new()
		translation.locale = locale
		for i in keys.size(): translation.add_message(keys[i], texts[locale][i])
		TranslationServer.add_translation(translation)
		_translations.append(translation)
	_previous_pause = get_tree().paused
	_owns_pause = true
	get_tree().paused = true
	film = preload("res://cutscenes/opening/OpeningCutscene.tscn").instantiate()
	film.show_studio_intro = false
	film.show_preview_hud = false
	film.finish_before_travel = true
	film.finished.connect(func(destination: StringName): _complete(destination, false))
	film.skipped.connect(func(destination: StringName): _complete(destination, true))
	add_child(film)

func _complete(destination: StringName, was_skipped: bool) -> void:
	if destination != &"bus_terminal_arrival" or not _owns_pause: return
	get_tree().paused = _previous_pause
	_owns_pause = false
	completed.emit(was_skipped)
	queue_free()

func _exit_tree() -> void:
	if _owns_pause: get_tree().paused = _previous_pause
	for translation in _translations: TranslationServer.remove_translation(translation)
