extends Node
const BOARD := preload("res://activities/desert_drag/DesertDragBoard.gd")
const RESULTS := preload("res://activities/desert_drag/DesertDragResults.gd")
const PROGRESS := preload("res://activities/desert_drag/DesertDragProgress.gd")
const STYLES := preload("res://activities/desert_drag/DragInstrumentStyles.gd")
const DRAG_INSTRUMENT_SHOP := preload("res://activities/desert_drag/DragInstrumentShop.gd")
var race: Node3D
var session
var layer: CanvasLayer
var board: Control
var backdrop: ColorRect
var pending_strike := ""
var results_layer: CanvasLayer
var results: Control
var result_busy := false
var instrument_shop: Control
var open_board_panel: Control

func configure(owner_race: Node3D) -> void:
	race=owner_race
	session=race.session
	race.race_completed.connect(_completed)
	race.return_completed.connect(_completed)

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
	board.show()
	if is_instance_valid(instrument_shop): instrument_shop.hide()
	if is_instance_valid(open_board_panel): open_board_panel.hide()
	board.show_progress(race.snapshot(),pending_strike)
	pending_strike=""
	_layout()
	return true

func _build() -> void:
	layer=CanvasLayer.new()
	# O HUD normal fica na camada 50. Mantém as notificações dele abaixo do fundo do modal.
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
	board.instruments_requested.connect(_open_instruments)
	board.takeshi_requested.connect(_open_takeshi)
	board.open_meet_requested.connect(_open_meet)
	board.night_requested.connect(_open_night)
	board.return_requested.connect(_request_return)
	board.challenges_requested.connect(_open_challenges)
	board.loaner_requested.connect(_open_loaner)
	get_viewport().size_changed.connect(_layout)
	layer.hide()

func _layout() -> void:
	if not is_instance_valid(board): return
	var available := get_viewport().get_visible_rect().size
	var factor := minf(1.0,minf((available.x-24)/900.0,(available.y-24)/640.0))
	board.scale=Vector2.ONE*factor
	board.position=(available-Vector2(900,640)*factor)*.5
	if is_instance_valid(instrument_shop):
		instrument_shop.scale=board.scale
		instrument_shop.position=board.position
	if is_instance_valid(open_board_panel):
		open_board_panel.scale=board.scale
		open_board_panel.position=board.position

func dismiss() -> void:
	if is_instance_valid(layer): layer.hide()
	if is_instance_valid(instrument_shop): instrument_shop.hide()
	if is_instance_valid(open_board_panel): open_board_panel.hide()

func _open_meet() -> void:
	if not session.modal or race.active or not layer.visible: return
	if not is_instance_valid(open_board_panel):
		open_board_panel = preload("res://activities/desert_drag/DragOpenBoard.gd").new()
		layer.add_child(open_board_panel)
		open_board_panel.action_requested.connect(_open_meet_action)
		race.open_meet.changed.connect(_refresh_open_meet)
	board.hide()
	open_board_panel.show()
	_refresh_open_meet()
	_layout()
	open_board_panel.now_button.grab_focus()

func _refresh_open_meet() -> void:
	if is_instance_valid(open_board_panel): open_board_panel.show_ticket(race.open_meet.ticket())

func _open_meet_action(action: String) -> void:
	if not session.modal or not is_instance_valid(open_board_panel) or not open_board_panel.is_visible_in_tree(): return
	if action=="back":
		open_board_panel.hide()
		board.show()
		board.open_meet_button.grab_focus()
		return
	if action=="cancel":
		race.open_meet.cancel_ticket()
		return
	if action!="now": return
	session.close_menu()
	var reason: String = race.start_block_reason()
	if not reason.is_empty():
		if open_board(): board.set_message(reason)
		return
	var identity: String = race.OPEN_ROSTER.IDS[race.open_meet.visitor_serial%race.OPEN_ROSTER.IDS.size()]
	if not race.open_meet.request(identity):
		if open_board(): board.set_message("Não foi possível alinhar. Verifique o carro e as faixas de largada.")

func _open_instruments() -> void:
	if not session.modal or not is_instance_valid(layer) or not layer.visible or race.active: return
	if not is_instance_valid(instrument_shop):
		instrument_shop=DRAG_INSTRUMENT_SHOP.new()
		layer.add_child(instrument_shop)
		instrument_shop.style_requested.connect(_request_style)
		instrument_shop.close_requested.connect(_close_instruments)
	board.hide()
	instrument_shop.show()
	_refresh_instruments()
	_layout()

func _refresh_instruments() -> void:
	instrument_shop.show_styles(STYLES.data(session.state.world_state),race.snapshot().wins.size(),session.state.economy.balance)

func _close_instruments() -> void:
	instrument_shop.hide()
	board.show()
	board.show_progress(race.snapshot())
	board.instruments_button.grab_focus()

func _request_style(identity: String) -> void:
	if not is_instance_valid(instrument_shop) or not instrument_shop.is_visible_in_tree() or not layer.visible: return
	if not session.modal or race.active or session.controller.save_invalid or session.is_transition_blocked(): return
	if session.world.gameplay.health<=0 or session.rescue_pending or session.arrest_pending: return
	var result := STYLES.select(session.state.world_state,session.state.economy,identity)
	if not result.ok:
		var messages := {"unknown_style":"Painel indisponível.","invalid_state":"Não foi possível acessar os painéis.","not_owned":"Compre este painel para equipar.","locked":"Vença mais adversários para liberar este painel.","insufficient_funds":"Saldo insuficiente.","transaction_refused":"Não foi possível concluir a compra."}
		instrument_shop.set_message(messages.get(result.reason,"Não foi possível equipar este painel."))
		return
	var saved := true
	if result.changed: saved=session.save_game()
	_refresh_instruments()
	instrument_shop.set_message("Painel equipado." if saved else "Painel equipado nesta sessão. Salvamento pendente.")

func _request_race(identity: String) -> void:
	# The board cannot choose a locked rival or create a victory/reward.
	if not PROGRESS.can_race(session.state.world_state,identity): return
	session.close_menu()
	var reason: String=race.start_block_reason()
	if not reason.is_empty():
		if open_board(): board.set_message(reason)
		return
	if not race.start_rival(identity):
		if open_board(): board.set_message("Aguarde a pista ficar livre e tente novamente.")

func _open_takeshi() -> void:
	if not session.modal or not is_instance_valid(layer) or not layer.visible or race.active: return
	session.close_menu()
	race.takeshi_controller.open()

func _open_night(identity: String) -> void:
	if not session.modal or race.active or not is_instance_valid(layer) or not layer.visible: return
	if not PROGRESS.can_race(session.state.world_state,identity): return
	session.close_menu()
	race.night_controller.open(identity)

func _request_return(identity: String) -> void:
	if not session.modal or race.active or not is_instance_valid(layer) or not layer.visible: return
	if not PROGRESS.can_race(session.state.world_state,identity): return
	session.close_menu()
	var reason: String=race.start_block_reason()
	if not reason.is_empty():
		if open_board(): board.set_message(reason)
		return
	if not race.start_return_pass(identity):
		if open_board(): board.set_message("Não foi possível alinhar. Verifique o carro e as faixas de largada.")

func _open_challenges() -> void:
	if not session.modal or race.active or not is_instance_valid(layer) or not layer.visible: return
	session.close_menu()
	race.challenge_controller.open()

func _open_loaner() -> void:
	if not session.modal or race.active or not is_instance_valid(layer) or not layer.visible: return
	session.close_menu()
	race.loaner_controller.open()

func _completed(result: Dictionary) -> void:
	if str(result.get("rival_id",""))=="takeshi":
		race.takeshi_controller.completed.call_deferred(result.duplicate(true))
		return
	if result.get("first_win",false): pending_strike=str(result.rival_id)
	_show_result.call_deferred(result.duplicate(true))

func _show_result(result: Dictionary) -> void:
	if race.active or session.modal or not result.get("finished",false): return
	if session.world.gameplay.health<=0 or session.rescue_pending or session.arrest_pending: return
	if not is_instance_valid(results_layer):
		results_layer=CanvasLayer.new()
		results_layer.layer=70
		add_child(results_layer)
		var dimmer := ColorRect.new()
		dimmer.color=Color(.015,.02,.025,.62)
		dimmer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		results_layer.add_child(dimmer)
		results=RESULTS.new()
		results_layer.add_child(results)
		results.action_requested.connect(_result_action)
		get_viewport().size_changed.connect(_layout_results)
	session._menu("Resultado da arrancada")
	session.panel.hide()
	session.menu_closed=_dismiss_results
	results_layer.show()
	if result.get("first_win",false) and str(result.get("rival_id",""))!="takeshi":
		var wins: int = race.snapshot().wins.size()
		for identity in STYLES.IDS:
			if int(STYLES.CATALOG[identity].price)>0 and int(STYLES.CATALOG[identity].wins)==wins:
				result["instrument_unlock"]=str(STYLES.CATALOG[identity].name)
	results.show_result(result,str(race.rival_config(str(result.rival_id)).name))
	_layout_results()

func show_takeshi_result(result: Dictionary) -> void:
	_show_result(result)

func _layout_results() -> void:
	if not is_instance_valid(results): return
	var available := get_viewport().get_visible_rect().size
	var factor := minf(1.0,minf((available.x-32)/740.0,(available.y-32)/480.0))
	results.scale=Vector2.ONE*factor
	results.position=(available-Vector2(740,480)*factor)*.5

func _dismiss_results() -> void:
	if is_instance_valid(results_layer): results_layer.hide()

func _result_action(action: String) -> void:
	if result_busy or not session.modal or not is_instance_valid(results_layer) or not results_layer.visible: return
	if action=="stay":
		session.close_menu()
		return
	if action not in ["rematch","entry","night_continue","night_repeat","night_overview","challenge_continue","challenge_overview"]: return
	result_busy=true
	results.set_busy(true)
	var identity: String=str(race.last_result.get("rival_id",""))
	var returned: bool=await race.return_to_entry()
	result_busy=false
	if not is_instance_valid(results) or not results_layer.visible: return
	results.set_busy(false)
	if not returned:
		results.set_message("Entrada ocupada. Tente novamente ou escolha Ficar aqui.")
		return
	session.close_menu()
	if action=="challenge_overview":
		race.challenge_controller.open(identity)
		return
	if action=="challenge_continue":
		race.challenge_controller.selected=identity
		var step := int(race.last_result.get("challenge_step",0))
		race.challenge_controller.selected_step=1 if step==0 and race.last_result.get("challenge_success",false) else step
		if not race.challenge_controller.request_next(): race.challenge_controller.open(identity)
		return
	if action=="night_overview":
		race.night_controller.open(identity)
		return
	if action in ["night_continue","night_repeat"]:
		race.night_controller.selected=identity
		if not race.night_controller.request_next():
			if race.night_controller.open(identity): race.night_controller.panel.set_message("Aguarde a pista ficar livre para continuar a noite.")
		return
	var started := true
	if action=="rematch":
		started=race.start_return_pass(identity) if race.last_result.get("return_mode",false) else race.start_rival(identity)
	if not started:
		if open_board():
			board.select_rival(identity)
			board.set_message("Aguarde a pista ficar livre para a revanche.")
