extends CanvasLayer
## Sobrevive à troca de cena. A barra usa recursos + marcos reais de preparação.
signal finished
signal failed(message: String)
const SCREEN = preload("res://ui/LoadingScreen.gd")
var active := false
var screen: Control
var last_variant := -1
var _previous_pause := false

func _ready() -> void:
	layer = 200
	process_mode = Node.PROCESS_MODE_ALWAYS

func begin(path: String, new_game := false) -> bool:
	if active: return false
	active = true
	_previous_pause = get_tree().paused
	get_tree().paused = true
	last_variant = (last_variant+1)%3
	screen = SCREEN.new()
	screen.variant = last_variant
	add_child(screen)
	_run.call_deferred(path,new_game)
	return true

func _draw_frame() -> void:
	await get_tree().process_frame
	if DisplayServer.get_name() != "headless": await RenderingServer.frame_post_draw

func _run(path: String, new_game: bool) -> void:
	await _draw_frame()
	if not ResourceLoader.exists(path):
		_error("Partida indisponível. Volte e escolha outra partida.","Game unavailable. Go back and choose another game.")
		return
	var error := ResourceLoader.load_threaded_request(path,"PackedScene")
	if error != OK:
		_error("Não foi possível abrir esta partida.","This game could not be opened.")
		return
	var resource_progress: Array = []
	while true:
		var status := ResourceLoader.load_threaded_get_status(path,resource_progress)
		if status == ResourceLoader.THREAD_LOAD_FAILED or status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			_error("Não foi possível carregar os arquivos da partida.","The game files could not be loaded.")
			return
		if not resource_progress.is_empty(): screen.set_stage(float(resource_progress[0])*0.60,_text("Carregando a cidade…","Loading the city…"))
		if status == ResourceLoader.THREAD_LOAD_LOADED: break
		await get_tree().process_frame
	var packed := ResourceLoader.load_threaded_get(path) as PackedScene
	if packed == null:
		_error("Partida indisponível.","Game unavailable.")
		return
	screen.set_stage(0.64,_text("Entrando no mundo…","Entering the world…"))
	await _draw_frame()
	if new_game:
		get_node("/root/CampaignState").reset_campaign()
		get_node("/root/WantedManager").reset()
		get_node("/root/SaveManager").clear_pending_save()
	get_node("/root/CityAudioManager").set_active(false)
	error = get_tree().change_scene_to_packed(packed)
	if error != OK:
		_error("Não foi possível iniciar a partida.","The game could not be started.")
		return
	# O mundo pode construir nós em call_deferred mesmo com a simulação pausada.
	await get_tree().scene_changed
	var world := get_tree().current_scene
	screen.set_stage(0.76,_text("Preparando ruas e personagens…","Preparing streets and characters…"))
	var deadline := Time.get_ticks_msec()+120000
	while is_instance_valid(world) and world.get("gameplay_ready") != null and (not bool(world.get("gameplay_ready")) or not bool(world.get("world_build_ready"))):
		if bool(world.get("world_build_ready")): screen.set_stage(0.88,_text("Restaurando sua jornada…","Restoring your journey…"))
		if Time.get_ticks_msec()>deadline:
			_error("A preparação demorou mais que o esperado. Volte ao menu e tente novamente.","Preparation took longer than expected. Return to the menu and try again.",true)
			return
		await get_tree().process_frame
	# Um frame completo de apresentação antes de liberar os controles/abertura.
	screen.set_stage(0.96,_text("Finalizando a entrada…","Finishing up…"))
	await preload("res://VehicleGeometryCache.gd").prepare_common_models(get_tree())
	for i in 4: await _draw_frame()
	screen.set_stage(1.0,_text("Tudo pronto","Ready"))
	while screen.shown_progress < 1.0: await get_tree().process_frame
	await _draw_frame()
	var tween := create_tween()
	tween.tween_property(screen,"modulate:a",0.0,0.25)
	await tween.finished
	screen.queue_free()
	screen = null
	active = false
	get_tree().paused = false
	finished.emit()

func _error(pt: String,en: String,return_to_menu := false) -> void:
	screen.stage.text = _text(pt,en)
	screen.recovery.show()
	screen.recovery.grab_focus()
	screen.recovery.pressed.connect(func():
		screen.queue_free()
		screen = null
		active = false
		get_node("/root/SaveManager").clear_pending_save()
		get_tree().paused = _previous_pause if not return_to_menu else false
		if return_to_menu: get_tree().change_scene_to_file("res://ui/MainMenu.tscn")
		failed.emit(_text(pt,en)))

func _text(pt: String,en: String) -> String:
	return en if TranslationServer.get_locale().begins_with("en") else pt
