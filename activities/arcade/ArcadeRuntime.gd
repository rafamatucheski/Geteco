extends Node
## Owns the cabinet modal; FullSession remains the owner of player controls.
const PLACE := "harbor_arcade"
const TITLES := {"pinball":"Bola de Aço", "blocks":"Blocos", "racer":"Pista Neon", "fighter":"Último Round"}
var session
var ui
var active := false
var cabinet := ""
var opened_health := 0.0
var origin := Vector3.ZERO
var records: Dictionary = {}

func configure(owner_session) -> void:
	name = "ArcadeRuntime"
	session = owner_session
	var saved: Variant = session.state.world_state.get("arcade_records",{})
	if saved is Dictionary:
		for id in TITLES:
			var value: Variant = saved.get(id,0)
			if (value is int or value is float) and is_finite(float(value)):
				records[id] = clampi(int(value),0,999999999)
	set_process(false)

func available() -> bool:
	return session != null and session.ready_for_play and session.state.place_id == PLACE and is_instance_valid(session.room) and session.world.gameplay.health > 0 and not session.world.driving.occupied and not session.is_transition_blocked() and not get_tree().paused

func nearest_action() -> Dictionary:
	if not available() or session.modal: return {}
	var nearest := ""
	var distance := 1.05
	for id in TITLES:
		var point: Variant = session.room.interaction_points.get("arcade_"+id)
		if not point is Vector3: continue
		var separation: float = session.world.player.global_position.distance_to(point)
		if separation < distance:
			distance = separation
			nearest = id
	return {} if nearest.is_empty() else {"id":"arcade","target":nearest,"label":"Jogar "+TITLES[nearest]}

func perform(id: String) -> bool:
	if active or not TITLES.has(id) or nearest_action().get("target","") != id: return false
	if not is_instance_valid(ui):
		ui = preload("res://activities/arcade/ArcadeScreen.gd").new()
		ui.adapter = self
		add_child(ui)
	session._menu(TITLES[id])
	session.panel.hide()
	session.menu_closed = dismiss
	cabinet = id
	origin = session.world.player.global_position
	opened_health = float(session.world.gameplay.health)
	active = true
	ui.open_game(id,int(records.get(id,0)))
	set_process(true)
	return true

func handle_input(event: InputEvent) -> bool:
	if not active: return false
	# Mouse/touch clicks must reach the visible screen buttons.
	if event is InputEventMouse or event is InputEventScreenTouch or event is InputEventScreenDrag: return false
	ui.handle_input(event)
	return true

func record_score() -> void:
	if not active or not is_instance_valid(ui) or ui.game == null: return
	var score: int = clampi(int(ui.game.score),0,999999999)
	if score > int(records.get(cabinet,0)):
		records[cabinet] = score
		session.state.world_state.arcade_records = records.duplicate()
		ui.best = score

func close() -> void:
	if active: session.close_menu()

func dismiss() -> void:
	if not active: return
	record_score()
	active = false
	cabinet = ""
	if is_instance_valid(ui): ui.dismiss()
	set_process(false)
	# Save after FullSession has released the modal; never save the live game.
	_save_records.call_deferred()

func _save_records() -> void:
	if is_instance_valid(session) and session.ready_for_play and not active and not session.is_transition_blocked() and session.world.gameplay.health > 0:
		session.save_game()

func _process(_delta: float) -> void:
	if active and (not available() or not session.modal or session.world.gameplay.health < opened_health or session.world.player.global_position.distance_to(origin) > 1.2): close()

func _exit_tree() -> void:
	if is_instance_valid(ui): ui.dismiss()
