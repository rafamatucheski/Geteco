extends Node
## UI and physical-entry adapter for a durable night. Never synthesizes finishes.
const PROGRESS := preload("res://activities/desert_drag/DragNightProgress.gd")
const PANEL := preload("res://activities/desert_drag/DragNightPanel.gd")
const GARAGE := preload("res://runtime/desert/DesertGarageState.gd")
const CARS := preload("res://gameplay/desert_cars/DesertCarCatalog.gd")
const ADAPTER := preload("res://gameplay/desert_cars/DesertCarAdapter.gd")
const TUNING := preload("res://gameplay/desert_cars/DesertTuning.gd")
const WINS := preload("res://systems/campaign/RaceWins.gd")
const FLEET := preload("res://runtime/FleetCatalog.gd")
const CATALOG := preload("res://activities/desert_drag/DragNightCatalog.gd")
var race: Node3D
var session
var layer: CanvasLayer
var panel: Control
var tuning_panel: CanvasLayer
var selected := "digo"
var selected_category := "livre"
var busy := false
var _armed: Dictionary = {}

func configure(owner_race: Node3D) -> void:
	race=owner_race
	session=race.session

func _available() -> bool:
	return is_instance_valid(session) and session.ready_for_play and not race.active and not session.controller.save_invalid and not session.is_transition_blocked() and session.state.region_id=="desert" and session.state.place_id.is_empty() and session.world.gameplay.health>0 and not session.rescue_pending and not session.arrest_pending

func _car() -> CharacterBody3D:
	if not session.world.driving.occupied: return null
	return session.world.driving.car as CharacterBody3D

func status() -> Dictionary:
	var step := PROGRESS.next_pass(session.state.world_state)
	if step.is_empty(): return {"active":false}
	step["active"]=true
	return step

func open(identity: String = "") -> bool:
	if not _available() or session.modal: return false
	if not identity.is_empty(): selected=identity
	var episode := PROGRESS.current(session.state.world_state)
	if not episode.is_empty(): selected=str(episode.rival_id); selected_category=str(episode.get("category","livre"))
	if not race.can_race(selected): return false
	if not is_instance_valid(layer): _build()
	var paid := PROGRESS.claim_rewards(session.state.world_state,session.state.economy)
	if paid>0: session.save_game()
	session._menu("Noite de Acerto")
	session.panel.hide()
	session.menu_closed=dismiss
	layer.show()
	panel.show()
	_refresh()
	_layout()
	return true

func _build() -> void:
	layer=CanvasLayer.new()
	layer.layer=71
	add_child(layer)
	var backdrop := ColorRect.new()
	backdrop.color=Color(.02,.025,.03,.78)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(backdrop)
	panel=PANEL.new()
	layer.add_child(panel)
	panel.action_requested.connect(_action)
	get_viewport().size_changed.connect(_layout)
	layer.hide()

func _layout() -> void:
	if not is_instance_valid(panel): return
	var extent := get_viewport().get_visible_rect().size
	var factor := minf(1.0,minf((extent.x-24.0)/900.0,(extent.y-24.0)/640.0))
	panel.scale=Vector2.ONE*factor
	panel.position=(extent-Vector2(900,640)*factor)*.5

func _refresh() -> void:
	var step := PROGRESS.next_pass(session.state.world_state)
	var episode := PROGRESS.current(session.state.world_state)
	var shown := step.duplicate(true)
	shown["has_episode"]=not episode.is_empty()
	shown["results"]=episode.get("results",[])
	shown["rival_id"]=selected
	shown["category"]=str(episode.get("category",selected_category))
	var car := _car()
	var presets := {}
	var vehicle_name := "Entre em um carro para correr"
	if is_instance_valid(car):
		presets=GARAGE.vehicle(session.state.world_state,car.vehicle_id,car.archetype).presets
		vehicle_name=str(FLEET.spec(car.archetype).get("label",car.archetype))
		shown["preparation_value"]=CATALOG.preparation_value(CARS.parts_for_vehicle(car))
	panel.show_state(shown,str(race.rival_config(selected).get("name",selected)),vehicle_name,presets)

func dismiss() -> void:
	if is_instance_valid(layer): layer.hide()
	if is_instance_valid(tuning_panel): tuning_panel.hide()

func _same_car() -> bool:
	var car := _car()
	if not is_instance_valid(car) or car.health<=0 or car.engine_disabled: return false
	var episode := PROGRESS.current(session.state.world_state)
	return episode.is_empty() or (episode.vehicle_id==car.vehicle_id and episode.archetype==car.archetype and episode.profile==race.powertrain_profile_for_vehicle(car))

func _action(action: String) -> void:
	if busy or not _available() or not session.modal or not layer.visible: return
	if action=="back":
		session.close_menu()
		race.board_controller.open_board()
		return
	if action=="abandon":
		var episode := PROGRESS.current(session.state.world_state)
		# Remove the queued entry before disarming its context. Otherwise its
		# eventual dispatch would fall through to an ordinary ranked 800 m race.
		if not episode.is_empty() and _armed.get("episode_id",-1)==episode.id and is_instance_valid(race.open_meet) and race.open_meet.pending==episode.rival_id:
			race.open_meet.cancel_ticket(false,"Noite encerrada.")
		PROGRESS.abandon(session.state.world_state)
		race.cancel_waiting_context("night_abandoned")
		session.save_game()
		_refresh()
		return
	if action.begins_with("category:"):
		var category := action.trim_prefix("category:")
		if category in CATALOG.CATEGORIES and PROGRESS.current(session.state.world_state).is_empty(): selected_category=category; _refresh()
		return
	if not _same_car():
		panel.set_message("Volte com o carro inscrito ou encerre a noite para trocar.")
		return
	if action=="continue":
		busy=true
		panel.set_busy(true)
		var ready: bool=await _return_if_needed()
		busy=false
		if not is_instance_valid(panel) or not layer.visible: return
		_refresh()
		if not ready:
			panel.set_message("Concentração ocupada. Libere a entrada e tente novamente.")
			return
		var car := _car()
		var category := str(PROGRESS.current(session.state.world_state).get("category",selected_category))
		if not CATALOG.fits_category(CARS.parts_for_vehicle(car),category):
			panel.set_message("Acerto R$ %d: remova peças para entrar em %s."%[CATALOG.preparation_value(CARS.parts_for_vehicle(car)),str(CATALOG.CATEGORIES[category].name)])
			return
		session.close_menu()
		if not request_next():
			if open(selected): panel.set_message("Aguarde a pista ficar livre ou confira o carro inscrito.")
		return
	if action=="prepare":
		_open_preparation()
		return
	if action.begins_with("preset:"):
		_apply_preset(action.trim_prefix("preset:"))

func _return_if_needed() -> bool:
	var car := _car()
	if not is_instance_valid(car): return false
	if car.global_position.distance_to(race.staging_point)<=15.0: return true
	return await race.return_to_entry()

func request_next() -> bool:
	if not _available() or session.modal or not _same_car(): return false
	var reason: String=race.start_block_reason()
	if not reason.is_empty(): session.show_message(reason); return false
	if is_instance_valid(race.open_meet) and not race.open_meet.pending.is_empty():
		session.show_message("Sua inscrição já está na fila.")
		return false
	var car := _car()
	var category := str(PROGRESS.current(session.state.world_state).get("category",selected_category))
	if not CATALOG.fits_category(CARS.parts_for_vehicle(car),category):
		session.show_message("Este acerto vale R$ %d. Remova peças para respeitar %s."%[CATALOG.preparation_value(CARS.parts_for_vehicle(car)),str(CATALOG.CATEGORIES[category].name)])
		return false
	if PROGRESS.current(session.state.world_state).is_empty():
		var begun := PROGRESS.begin(session.state.world_state,selected,car.vehicle_id,car.archetype,race.powertrain_profile_for_vehicle(car),selected_category)
		if not begun.ok: session.show_message(str(begun.reason)); return false
		session.save_game()
	var step := PROGRESS.next_pass(session.state.world_state)
	if step.is_empty(): return false
	selected=str(step.rival_id)
	var episode := PROGRESS.current(session.state.world_state)
	if int(step.step)==2 and PROGRESS.mechanical_parts(episode.results[1].parts)!=PROGRESS.mechanical_parts(CARS.parts_for_vehicle(car)):
		session.show_message("Restaure o acerto da primeira passagem de 402 m para continuar.")
		return false
	_armed=step.duplicate(true)
	if not race.start_night_pass(str(step.rival_id),float(step.distance)):
		_armed.clear()
		return false
	return true

func validate_dispatch(car: Node) -> String:
	if not is_instance_valid(car) or _armed.is_empty(): return "A inscrição da noite não está mais válida."
	var episode := PROGRESS.current(session.state.world_state)
	if episode.is_empty() or episode.id!=_armed.get("episode_id",-1) or episode.vehicle_id!=str(car.vehicle_id) or episode.profile!=race.powertrain_profile_for_vehicle(car): return "Volte com o carro inscrito na noite."
	var parts := CARS.parts_for_vehicle(car)
	var category := str(episode.get("category","livre"))
	if not CATALOG.fits_category(parts,category): return "O acerto mudou na fila e ultrapassa o teto da categoria."
	if int(_armed.get("step",0))==2 and PROGRESS.mechanical_parts(episode.results[1].parts)!=PROGRESS.mechanical_parts(parts): return "Restaure o acerto da primeira passagem de 402 m."
	return ""

func rival_parts(identity: String) -> Dictionary:
	var episode := PROGRESS.current(session.state.world_state)
	return CATALOG.rival_preparation(race.rival_parts(identity),str(episode.get("category",selected_category)))

func record_finish(player_seconds: float, rival_seconds: float, car: Node) -> Dictionary:
	if _armed.is_empty() or not is_instance_valid(car): return {}
	var category := str(_armed.get("category","livre"))
	var result := PROGRESS.record_finish(session.state.world_state,int(_armed.episode_id),int(_armed.step),str(car.vehicle_id),race.powertrain_profile_for_vehicle(car),CARS.parts_for_vehicle(car),player_seconds,rival_seconds if is_finite(rival_seconds) else -1.0,float(race.distance))
	_armed.clear()
	if result.is_empty(): return result
	result["night_category"]=category
	result["night_category_label"]=str(CATALOG.CATEGORIES[category].name)
	result["reward_paid"]=PROGRESS.claim_rewards(session.state.world_state,session.state.economy)
	result["reward_pending"]=PROGRESS.pending_reward_amount(session.state.world_state,session.state.economy.snapshot())
	return result

func cancel_attempt(_reason: String = "cancelled") -> void:
	_armed.clear()

func _can_prepare() -> bool:
	return _available() and session.modal and _same_car() and int(PROGRESS.next_pass(session.state.world_state).get("step",0))!=2

func _open_preparation() -> void:
	if not _can_prepare(): return
	if not is_instance_valid(tuning_panel):
		tuning_panel=preload("res://gameplay/desert_cars/DesertTuningPanel.gd").new()
		add_child(tuning_panel)
		tuning_panel.layer=72
		tuning_panel.mechanic_name="Acerto da noite"
		tuning_panel.purchase_requested.connect(_equip_part)
		tuning_panel.remove_requested.connect(_remove_part)
		tuning_panel.closed.connect(_close_preparation)
	layer.hide()
	_refresh_preparation()

func _refresh_preparation() -> void:
	var car := _car()
	if not is_instance_valid(car): session.close_menu(); return
	var record := GARAGE.vehicle(session.state.world_state,car.vehicle_id,car.archetype)
	tuning_panel.show_vehicle(ADAPTER.profile_of(car),record.parts,record.owned,WINS.count(session.state.world_state,session.state.campaign.snapshot()),session.state.economy.balance,{"archetype":car.archetype,"paint":car.paint_color})
	tuning_panel.set_message("Reinstale peças que já possui. Novas peças estão na oficina do Digo.")

func _close_preparation() -> void:
	session.close_menu()
	open(selected)

func _equip_part(part: String) -> void:
	if not _can_prepare() or not is_instance_valid(tuning_panel) or not tuning_panel.visible: return
	var car := _car()
	var record := GARAGE.vehicle(session.state.world_state,car.vehicle_id,car.archetype)
	if part not in record.owned:
		tuning_panel.set_message("Adquira esta peça na oficina do Digo antes de instalar.")
		return
	var result := GARAGE.buy(session.state.world_state,session.state.economy,car.vehicle_id,car.archetype,part,WINS.count(session.state.world_state,session.state.campaign.snapshot()))
	if not result.ok: tuning_panel.set_message(str(result.reason)); return
	ADAPTER.attach(car,result.parts)
	session.save_game()
	_refresh_preparation()

func _remove_part(slot: String) -> void:
	if not _can_prepare() or not is_instance_valid(tuning_panel) or not tuning_panel.visible or slot not in TUNING.SLOTS: return
	var car := _car()
	var record := GARAGE.vehicle(session.state.world_state,car.vehicle_id,car.archetype)
	record.parts.erase(slot)
	_save_preparation(car,record)
	_refresh_preparation()

func _save_preparation(car: CharacterBody3D, record: Dictionary) -> void:
	var saved := GARAGE.data(session.state.world_state)
	saved.vehicles[car.vehicle_id]=record
	session.state.world_state.desert_garage=saved
	ADAPTER.attach(car,record.parts)
	session.save_game()

func _apply_preset(identity: String) -> void:
	if not _can_prepare() or identity not in ["rua","drag","terra"]: return
	var car := _car()
	var record := GARAGE.vehicle(session.state.world_state,car.vehicle_id,car.archetype)
	if not record.presets.has(identity): panel.set_message("Esse ajuste ainda não foi salvo na oficina."); return
	record.parts=record.presets[identity].duplicate(true)
	_save_preparation(car,record)
	_refresh()
	panel.set_message("Ajuste "+identity+" aplicado.")
