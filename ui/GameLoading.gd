extends CanvasLayer
## Sobrevive à troca de cena. A barra usa recursos + marcos reais de preparação.
signal finished
signal presentation_preparing
signal failed(message: String)
const SCREEN = preload("res://ui/LoadingScreen.gd")
var active := false
var screen: Control
var last_variant := -1
var _previous_pause := false
var _master_was_muted := false
var studio_intro_presented := false
var opening: Control
var opening_complete := false
var phase_times_ms: Dictionary = {}
var _phase_started_us := 0
var _load_started_us := 0
var _prefetch_path := ""
var _prefetch_error := OK

func prefetch(path: String) -> void:
	# Main menu hint only: resource I/O happens on the loader thread and no save
	# is read or staged here. If the player clicks immediately, begin() simply
	# waits for the same in-flight request instead of starting another one.
	if active or not ResourceLoader.exists(path):
		return
	if _prefetch_path == path:
		var status := ResourceLoader.load_threaded_get_status(path)
		if status in [ResourceLoader.THREAD_LOAD_IN_PROGRESS, ResourceLoader.THREAD_LOAD_LOADED]:
			return
	_prefetch_path = path
	_prefetch_error = ResourceLoader.load_threaded_request(path, "PackedScene")

func _mark_phase(label: String) -> void:
	var now := Time.get_ticks_usec()
	phase_times_ms[label] = (now - _phase_started_us) / 1000.0
	_phase_started_us = now

func _ready() -> void:
	layer = 200
	process_mode = Node.PROCESS_MODE_ALWAYS

func begin(path: String, new_game := false) -> bool:
	if active: return false
	active = true
	phase_times_ms.clear()
	_load_started_us = Time.get_ticks_usec()
	_phase_started_us = _load_started_us
	if _prefetch_path != path:
		_prefetch_path = ""
		_prefetch_error = OK
	_previous_pause = get_tree().paused
	_master_was_muted = AudioServer.is_bus_mute(0)
	AudioServer.set_bus_mute(0, true)
	get_tree().paused = true
	studio_intro_presented = new_game
	opening_complete = false
	if new_game:
		screen = preload("res://ui/OpeningLoading.gd").new()
	else:
		last_variant = (last_variant+1)%3
		screen = SCREEN.new()
		screen.variant = last_variant
	add_child(screen)
	if new_game:
		_start_opening.call_deferred(path)
	else:
		_run.call_deferred(path,false)
	return true

func _start_opening(path: String) -> void:
	# Read resources during the studio card. Scene construction still waits for
	# the CGI, preserving the presentation while overlapping background I/O.
	if _prefetch_path != path:
		_prefetch_path = path
		_prefetch_error = ResourceLoader.load_threaded_request(path, "PackedScene")
	screen.modulate.a = 0.0
	var fade := create_tween()
	fade.tween_property(screen, "modulate:a", 1.0, 0.9).set_trans(Tween.TRANS_SINE)
	await fade.finished
	opening = preload("res://cutscenes/opening/OpeningCutscene.tscn").instantiate()
	opening.auto_start = false
	opening.show_studio_intro = false
	add_child(opening)
	move_child(opening, screen.get_index())
	opening.finished.connect(func(_beat): opening_complete = true)
	opening.skipped.connect(func(_beat): opening_complete = true)
	while screen.elapsed < 4.5: await get_tree().process_frame
	fade = create_tween()
	fade.tween_property(screen, "modulate:a", 0.0, 0.8).set_trans(Tween.TRANS_SINE)
	await fade.finished
	screen.hide()
	var menu := get_tree().current_scene
	if is_instance_valid(menu) and menu.has_method("_stop_bg_music"): menu._stop_bg_music()
	get_node("/root/CityAudioManager").set_active(false)
	AudioServer.set_bus_mute(0, _master_was_muted)
	opening.play()
	# Resource I/O can overlap the film; scene construction cannot. Even while
	# paused, _ready/deferred world builders block rendering while audio runs.
	while not opening_complete: await get_tree().process_frame
	AudioServer.set_bus_mute(0, true)
	screen.queue_free()
	screen = SCREEN.new()
	add_child(screen)
	await _draw_frame()
	_run(path, true)

func _draw_frame() -> void:
	await get_tree().process_frame
	if DisplayServer.get_name() != "headless": await RenderingServer.frame_post_draw

func _run(path: String, new_game: bool) -> void:
	await _draw_frame()
	if not ResourceLoader.exists(path):
		_error("Partida indisponível. Volte e escolha outra partida.","Game unavailable. Go back and choose another game.")
		return
	var error := _prefetch_error if _prefetch_path == path else ResourceLoader.load_threaded_request(path,"PackedScene")
	if error != OK:
		_error("Não foi possível abrir esta partida.","This game could not be opened.")
		return
	_mark_phase("before_resources")
	var resource_progress: Array = []
	while true:
		var status := ResourceLoader.load_threaded_get_status(path,resource_progress)
		if status == ResourceLoader.THREAD_LOAD_FAILED or status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			_error("Não foi possível carregar os arquivos da partida.","The game files could not be loaded.")
			return
		if not resource_progress.is_empty(): screen.set_stage(float(resource_progress[0])*0.30,_text("Carregando a cidade…","Loading the city…"))
		if status == ResourceLoader.THREAD_LOAD_LOADED: break
		await get_tree().process_frame
	var packed := ResourceLoader.load_threaded_get(path) as PackedScene
	if packed == null:
		_error("Partida indisponível.","Game unavailable.")
		return
	_mark_phase("resources")
	screen.set_stage(0.32,_text("Entrando no mundo…","Entering the world…"))
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
	_mark_phase("scene_ready")
	var world := get_tree().current_scene
	screen.set_stage(0.50,_text("Preparando ruas e personagens…","Preparing streets and characters…"))
	var deadline := Time.get_ticks_msec()+120000
	while is_instance_valid(world) and world.get("gameplay_ready") != null and (not bool(world.get("gameplay_ready")) or not bool(world.get("world_build_ready"))):
		if bool(world.get("world_build_ready")): screen.set_stage(0.60,_text("Restaurando sua jornada…","Restoring your journey…"))
		if Time.get_ticks_msec()>deadline:
			_error("A preparação demorou mais que o esperado. Volte ao menu e tente novamente.","Preparation took longer than expected. Return to the menu and try again.",true)
			return
		await get_tree().process_frame
	# Um frame completo de apresentação antes de liberar os controles/abertura.
	_mark_phase("world_build")
	screen.set_stage(0.65,_text("Preparando veículos…","Preparing vehicles…"))
	await preload("res://cars/VehicleGeometryCache.gd").prepare_common_models(get_tree())
	_mark_phase("vehicle_models")
	screen.set_stage(0.75,_text("Preparando o trânsito…","Preparing traffic…"))
	await preload("res://cars/VehicleGeometryCache.gd").prepare_resident_presentations(get_tree())
	_mark_phase("resident_vehicles")
	screen.set_stage(0.85,_text("Preparando equipes de emergência…","Preparing emergency crews…"))
	await get_node("/root/EmergencyPool").prepare_presentations()
	_mark_phase("emergency")
	screen.set_stage(0.93,_text("Preparando áudio…","Preparing audio…"))
	await preload("res://audio/VehicleEngineSound.gd").prepare_catalog(get_tree())
	_mark_phase("audio")
	screen.set_stage(0.98,_text("Finalizando a entrada…","Finishing up…"))
	for i in 4: await _draw_frame()
	presentation_preparing.emit()
	await _draw_frame()
	if new_game:
		while not opening_complete: await get_tree().process_frame
		screen.queue_free()
		screen = null
		active = false
		get_tree().paused = false
		AudioServer.set_bus_mute(0, _master_was_muted)
		phase_times_ms["total"] = (Time.get_ticks_usec() - _load_started_us) / 1000.0
		finished.emit()
		opening = null
		return
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
	AudioServer.set_bus_mute(0, _master_was_muted)
	phase_times_ms["total"] = (Time.get_ticks_usec() - _load_started_us) / 1000.0
	finished.emit()

func _error(pt: String,en: String,return_to_menu := false) -> void:
	if is_instance_valid(opening):
		opening.queue_free()
		opening = null
	screen.show()
	screen.modulate.a = 1.0
	screen.stage.text = _text(pt,en)
	screen.recovery.show()
	screen.recovery.grab_focus()
	screen.recovery.pressed.connect(func():
		screen.queue_free()
		screen = null
		active = false
		AudioServer.set_bus_mute(0, _master_was_muted)
		get_node("/root/SaveManager").clear_pending_save()
		get_tree().paused = _previous_pause if not return_to_menu else false
		if return_to_menu: get_tree().change_scene_to_file("res://ui/MainMenu.tscn")
		failed.emit(_text(pt,en)))

func _text(pt: String,en: String) -> String:
	return en if TranslationServer.get_locale().begins_with("en") else pt
