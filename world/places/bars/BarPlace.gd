extends "res://world/places/NativePlace.gd"
## Room owns the games and speaker; FullSession owns modal and resident lifetime.
var session
var game_ui
var game_active := false
var opened_health := 0.0
var game_origin := Vector3.ZERO
var speaker: AudioStreamPlayer

func _ready() -> void:
	super._ready()
	for station in definition.get("bar_stations",{}):
		interaction_points[station] = to_global(definition.bar_stations[station])
	# The orthographic camera is over 25 m from the jukebox. Room-owned music
	# must follow occupancy instead of fading against that remote listener.
	speaker = AudioStreamPlayer.new()
	speaker.name = "BarMusic"
	speaker.volume_db = -15
	speaker.bus = "Music" if AudioServer.get_bus_index("Music") >= 0 else "Master"
	var track := "res://audio/workshop/digo_blues_loop.ogg" if definition.id == "desert_bar" else "res://audio/living_city/porto_groove.ogg"
	var stream = load(track)
	if stream is AudioStreamOggVorbis:
		stream = stream.duplicate()
		stream.loop = true
	speaker.stream = stream
	add_child(speaker)
	set_process(false)

func on_session_entered(owner_session) -> void:
	session = owner_session
	var yaws: Array = definition.get("bar_drinker_yaws",[])
	for index in mini(yaws.size(),session.room_npcs.size()):
		var actor = session.room_npcs[index]
		if is_instance_valid(actor): actor.visual.rotation.y = float(yaws[index])
	if active: speaker.play()
	set_process(true)

func nearest_action(owner_session) -> Dictionary:
	if game_active or owner_session.modal or not active or owner_session.world.gameplay.health <= 0: return {}
	var result := {}
	var distance := 1.25
	for key in ["bar_darts","bar_pool"]:
		if not interaction_points.has(key): continue
		var separation: float = owner_session.world.player.global_position.distance_to(interaction_points[key])
		if separation < distance:
			distance = separation
			result = {"id":"bar_game","target":key,"label":"Jogar dardos" if key == "bar_darts" else "Jogar bilhar"}
	return result

func start_game(kind: String, owner_session) -> bool:
	if kind not in ["bar_darts","bar_pool"] or nearest_action(owner_session).get("target","") != kind: return false
	session = owner_session
	session._menu("Dardos" if kind == "bar_darts" else "Bilhar")
	session.panel.hide()
	session.menu_closed = dismiss_game
	game_ui = preload("res://world/places/bars/BarGameScreen.gd").new()
	game_ui.adapter = self
	add_child(game_ui)
	game_origin = session.world.player.global_position
	opened_health = float(session.world.gameplay.health)
	game_active = true
	game_ui.open_game(kind)
	return true

func handle_game_input(event: InputEvent) -> bool:
	return game_ui.handle_input(event) if game_active and is_instance_valid(game_ui) else false

func close_game() -> void:
	if not game_active: return
	if is_instance_valid(session) and session.menu_closed == Callable(self,"dismiss_game"):
		session.close_menu()
	else: dismiss_game()

func dismiss_game() -> void:
	game_active = false
	if is_instance_valid(game_ui):
		game_ui.hide()
		game_ui.queue_free()
	game_ui = null

func _process(_delta: float) -> void:
	if not game_active: return
	if not is_instance_valid(session) or session.room != self or not session.modal or not active or session.world.gameplay.health < opened_health or session.world.player.global_position.distance_to(game_origin) > 1.2:
		close_game()

func set_active(value: bool) -> void:
	if not value:
		close_game()
		if is_instance_valid(speaker): speaker.stop()
	super.set_active(value)
	if value and is_instance_valid(session) and is_instance_valid(speaker): speaker.play()

func _exit_tree() -> void:
	dismiss_game()
