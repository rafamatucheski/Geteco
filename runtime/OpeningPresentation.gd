extends CanvasLayer
## Hosts the native 3D ferry film, then hands back to the playable disembarkation.
const FILM := preload("res://cutscenes/opening/ferry/FerryFilm.gd")
signal completed(skipped: bool)
var film: Control
var _previous_pause := false
var _owns_pause := false
var _viewport: Viewport
var _previous_3d_disabled := false
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
	_viewport = get_viewport()
	_previous_3d_disabled = _viewport.disable_3d
	_owns_pause = true
	get_tree().paused = true
	# The opaque prerecorded film needs no hidden live city render underneath it.
	_viewport.disable_3d = true
	film = FILM.new()
	film.finished.connect(func(destination: StringName): _complete(destination, false))
	film.skipped.connect(func(destination: StringName): _complete(destination, true))
	add_child(film)

func _complete(destination: StringName, was_skipped: bool) -> void:
	if destination != FILM.DESTINATION or not _owns_pause: return
	_release_world()
	completed.emit(was_skipped)
	queue_free()

func _exit_tree() -> void:
	_release_world()
	for translation in _translations: TranslationServer.remove_translation(translation)

func _release_world() -> void:
	if not _owns_pause: return
	if is_instance_valid(_viewport): _viewport.disable_3d = _previous_3d_disabled
	get_tree().paused = _previous_pause
	_owns_pause = false
