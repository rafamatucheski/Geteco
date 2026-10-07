extends Node
const BOARD := preload("res://activities/desert_drag/DesertDragBoard.gd")
var race: Node3D
var session
var layer: CanvasLayer
var board: Control
var backdrop: ColorRect
var pending_strike := ""

func configure(owner_race: Node3D) -> void:
	race=owner_race
	session=race.session
	race.race_completed.connect(_completed)

func open_board() -> bool:
	if race.active or session.modal or not session.ready_for_play or session.controller.save_invalid or session.is_transition_blocked(): return false
	if session.state.region_id!="desert" or not session.state.place_id.is_empty(): return false
	if session.world.gameplay.health<=0 or session.rescue_pending or session.arrest_pending: return false
	if session.world.driving.occupied and absf(session.world.driving.car.speed)>1.0:
		session.show_message("Pare o carro para ver o quadro.")
		return false
	if not is_instance_valid(layer): _build()
	session._menu("Arrancadas")
	session.panel.hide()
	session.menu_closed=dismiss
	layer.show()
	board.show_progress(race.snapshot(),pending_strike)
	pending_strike=""
	_layout()
	return true

func _build() -> void:
	layer=CanvasLayer.new()
	# The normal HUD is layer 50. Keep its notifications below the modal backdrop.
	layer.layer=70
	add_child(layer)
	backdrop=ColorRect.new()
	backdrop.color=Color(0.025,.035,.03,.78)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(backdrop)
	board=BOARD.new()
	layer.add_child(board)
	board.closed.connect(session.close_menu)
	board.race_requested.connect(_request_race)
	get_viewport().size_changed.connect(_layout)
	layer.hide()

func _layout() -> void:
	if not is_instance_valid(board): return
	var available := get_viewport().get_visible_rect().size
	var factor := minf(1.0,minf((available.x-24)/900.0,(available.y-24)/640.0))
	board.scale=Vector2.ONE*factor
	board.position=(available-Vector2(900,640)*factor)*.5

func dismiss() -> void:
	if is_instance_valid(layer): layer.hide()

func _request_race(identity: String) -> void:
	# The board cannot choose a locked rival or create a victory/reward.
	if identity!=preload("res://activities/desert_drag/DesertDragProgress.gd").current_rival(session.state.world_state): return
	session.close_menu()
	var reason: String=race.start_block_reason()
	if not reason.is_empty():
		if open_board(): board.set_message(reason)
		return
	race.perform("start")

func _completed(result: Dictionary) -> void:
	if result.get("first_win",false):
		pending_strike=str(result.rival_id)
		_show_result.call_deferred()

func _show_result() -> void:
	# Cleanup normally stops the car. If another controller has resumed motion,
	# retain the saved strike for the next safe opening instead of stealing input.
	if session.world.driving.occupied and absf(session.world.driving.car.speed)>1.0: return
	open_board()
