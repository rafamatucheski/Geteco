extends Node
## Physical queue adapter; progression receives only measured, completed passes.
const PROGRESS := preload("res://activities/desert_drag/DragRivalChallengeProgress.gd")
const CATALOG := preload("res://activities/desert_drag/DragRivalChallengeCatalog.gd")
const TELEMETRY := preload("res://activities/desert_drag/DragRivalChallengeTelemetry.gd")
const PANEL := preload("res://activities/desert_drag/DragRivalChallengePanel.gd")
const GARAGE := preload("res://runtime/desert/DesertGarageState.gd")
const CARS := preload("res://gameplay/desert_cars/DesertCarCatalog.gd")
const ADAPTER := preload("res://gameplay/desert_cars/DesertCarAdapter.gd")
const TUNING := preload("res://gameplay/desert_cars/DesertTuning.gd")
const FLEET := preload("res://runtime/FleetCatalog.gd")
const WINS := preload("res://systems/campaign/RaceWins.gd")
var race: Node3D
var session
var selected := "digo"
var selected_step := -1
var layer: CanvasLayer
var panel: Control
var tuning_panel: CanvasLayer
var busy := false
var _armed: Dictionary = {}
var _telemetry: RefCounted

func configure(owner_race: Node3D) -> void:
	race=owner_race
	session=race.session

func _available() -> bool:
	return is_instance_valid(session) and session.ready_for_play and not race.active and not session.controller.save_invalid and not session.is_transition_blocked() and session.state.region_id=="desert" and session.state.place_id.is_empty() and session.world.gameplay.health>0 and not session.rescue_pending and not session.arrest_pending

func _car() -> CharacterBody3D:
	return session.world.driving.car as CharacterBody3D if session.world.driving.occupied else null

func status() -> Dictionary:
	var identity := str(_armed.get("rival_id",selected))
	return PROGRESS.status(session.state.world_state,identity,int(_armed.get("step",selected_step)))

func objective_text() -> String:
	return str(CATALOG.goal(str(_armed.get("rival_id",selected)),int(_armed.get("step",maxi(0,selected_step)))).get("objective",""))

func live_status() -> String:
	if _armed.is_empty() or not is_instance_valid(_telemetry): return ""
	var key := str(_armed.rival_id)+":"+str(int(_armed.step))
	var clean_launch: bool=_telemetry.launch in ["BOA LARGADA","LARGADA IDEAL"]
	var launch_note := "Largada boa" if clean_launch else ("Prepare a largada" if _telemetry.launch.is_empty() else "Largada fora da faixa")
	match key:
		"digo:0": return launch_note+" · complete 201 m"
		"digo:1": return "Trocas boas %d / 2 · erros %d"%[_telemetry.good_shifts,_telemetry.bad_shifts]
		"raul:0": return "Trocas boas %d / 3 · erros %d"%[_telemetry.good_shifts,_telemetry.bad_shifts]
		"livia:0": return "Patinagem %.0f%% / 25%%"%(_telemetry.spin60_seconds/maxf(.001,_telemetry.first60_seconds)*100.0)
		"livia:1": return String(TranslationServer.translate("%s · nitro %.1f s · limite %.1f / 0,5 s"))%[launch_note,_telemetry.nitro_seconds,_telemetry.limiter_seconds]
		"raul:1": return "Limitador final %.2f / 0,35 s"%_telemetry.late_limiter_seconds
		"jessica:0": return "Complete 402 m para registrar a marca"
		"jessica:1": return "Repita %.3f s · tolerância ±0,30 s"%float(_reference_seconds)
		"nadir:0": return "Sem nitro · usado %.1f s"%_telemetry.nitro_seconds
		"nadir:1": return "Conserve 90%% · atual %.0f%%"%(_telemetry.tail_min_speed/maxf(.001,_telemetry.tail_entry_speed)*100.0) if _telemetry.tail_entry_speed>0.0 else "Conserve velocidade nos 100 m finais"
		"rauhz:0": return String(TranslationServer.translate("%s · trocas %d / 2 · erros %d"))%[launch_note,_telemetry.good_shifts,_telemetry.bad_shifts]
		"rauhz:1": return "Trocas %d / 3 · erros %d · limite %.1f / 0,5 s"%[_telemetry.good_shifts,_telemetry.bad_shifts,_telemetry.limiter_seconds]
	return ""

var _reference_seconds := 0.0

func can_start(identity: String) -> bool:
	var value := PROGRESS.data(session.state.world_state)
	return not _armed.is_empty() and _armed.get("rival_id","")==identity and PROGRESS.validate_snapshot(value) and value.current==_armed and PROGRESS.accessible(value,identity)

func validate_dispatch(car: Node) -> String:
	if not is_instance_valid(car) or _armed.is_empty() or not can_start(str(_armed.get("rival_id",""))): return "A inscrição do desafio não está mais válida."
	var candidate := {"vehicle_id":str(car.vehicle_id),"profile":race.powertrain_profile_for_vehicle(car),"parts":preload("res://activities/desert_drag/DragNightProgress.gd").mechanical_parts(CARS.parts_for_vehicle(car))}
	return "" if PROGRESS.same_preparation(_armed,candidate) else "Carro ou acerto mudou na fila. Inscreva-se novamente no desafio."

func open(identity: String = "") -> bool:
	if not _available() or session.modal: return false
	if identity.is_empty(): identity=PROGRESS.current_rival(session.state.world_state)
	if identity not in CATALOG.IDS: return false
	selected=identity
	selected_step=-1
	if not is_instance_valid(layer): _build()
	var paid := PROGRESS.claim_rewards(session.state.world_state,session.state.economy)
	# A saved registration never resumes by itself after loading a checkpoint.
	if _armed.is_empty() and not PROGRESS.data(session.state.world_state).current.is_empty(): PROGRESS.cancel(session.state.world_state); session.save_game()
	elif paid>0: session.save_game()
	session._menu("Desafios dos rivais")
	session.panel.hide()
	session.menu_closed=dismiss
	layer.show()
	_refresh()
	_layout()
	panel.buttons.start.grab_focus()
	return true

func _build() -> void:
	layer=CanvasLayer.new()
	layer.layer=71
	add_child(layer)
	var dimmer := ColorRect.new()
	dimmer.color=Color(.02,.025,.03,.78)
	dimmer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(dimmer)
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
	var value := PROGRESS.status(session.state.world_state,selected,selected_step)
	selected_step=int(value.get("step",0))
	var car := _car()
	value["has_car"]=is_instance_valid(car) and car.health>0 and not car.engine_disabled
	value["car_name"]=str(FLEET.spec(car.archetype).get("label",car.archetype)) if is_instance_valid(car) else "Entre em um carro para correr"
	value["owned"]=value.get("reward_part","") in GARAGE.vehicle(session.state.world_state,car.vehicle_id,car.archetype).owned if is_instance_valid(car) else false
	panel.show_state(value)

func dismiss() -> void:
	if is_instance_valid(layer): layer.hide()
	if is_instance_valid(tuning_panel): tuning_panel.hide()

func _action(action: String) -> void:
	if busy or not _available() or not session.modal or not is_instance_valid(layer) or not layer.visible: return
	if action=="back": session.close_menu(); race.board_controller.open_board(); return
	if action.begins_with("rival:"):
		selected=action.trim_prefix("rival:")
		selected_step=-1
		_refresh()
		return
	if action.begins_with("step:"): selected_step=action.trim_prefix("step:").to_int(); _refresh(); return
	if action=="prepare": _open_preparation(); return
	if action=="install": _receive_or_install(); return
	if action!="start": return
	busy=true
	panel.set_busy(true)
	var car := _car()
	var returned := is_instance_valid(car) and car.global_position.distance_to(race.staging_point)<=15.0
	if is_instance_valid(car) and not returned: returned=await race.return_to_entry()
	busy=false
	if not is_instance_valid(panel) or not layer.visible: return
	_refresh()
	if not returned: panel.set_message("Libere a entrada e tente novamente."); return
	session.close_menu()
	if not request_next():
		var step := selected_step
		if open(selected): selected_step=step; _refresh(); panel.set_message("Confira o carro, a referência e sua inscrição na fila.")

func request_next() -> bool:
	if not _available() or session.modal: return false
	var reason: String=race.start_block_reason()
	if not reason.is_empty(): session.show_message(reason); return false
	if is_instance_valid(race.open_meet) and not race.open_meet.pending.is_empty(): session.show_message("Sua inscrição já está na fila."); return false
	var car := _car()
	if not is_instance_valid(car): return false
	var value := PROGRESS.status(session.state.world_state,selected,selected_step)
	if value.is_empty(): return false
	selected_step=int(value.step)
	var begun := PROGRESS.begin(session.state.world_state,selected,selected_step,car.vehicle_id,car.archetype,race.powertrain_profile_for_vehicle(car),CARS.parts_for_vehicle(car))
	if not begun.ok: session.show_message(str(begun.reason)); return false
	_armed=begun.entry.duplicate(true)
	if not race.start_challenge_pass(selected,float(value.distance)):
		cancel_attempt("start_blocked")
		return false
	return true

func begin_attempt(_car_node: Node) -> void:
	_telemetry=TELEMETRY.new()
	_telemetry.course=float(CATALOG.goal(str(_armed.get("rival_id",selected)),int(_armed.get("step",0))).get("distance",800.0))
	_reference_seconds=float(PROGRESS.data(session.state.world_state).reference.get("seconds",0.0))

func observe(drive: RefCounted, offset: float, delta: float) -> void:
	if not _armed.is_empty() and is_instance_valid(_telemetry): _telemetry.observe(drive,offset,delta)

func record_finish(player_seconds: float, rival_seconds: float, car: Node) -> Dictionary:
	if _armed.is_empty() or not is_instance_valid(car) or not is_instance_valid(_telemetry): return {}
	var result := PROGRESS.record_finish(session.state.world_state,int(_armed.id),str(car.vehicle_id),race.powertrain_profile_for_vehicle(car),CARS.parts_for_vehicle(car),player_seconds,rival_seconds,float(race.distance),_telemetry.snapshot())
	_armed.clear()
	_telemetry=null
	if result.is_empty(): return result
	result["reward_paid"]=PROGRESS.claim_rewards(session.state.world_state,session.state.economy)
	result["reward_pending"]=PROGRESS.pending_reward(session.state.world_state,session.state.economy.snapshot())
	result["challenge_status"]=PROGRESS.status(session.state.world_state,str(result.rival_id))
	return result

func cancel_attempt(_reason: String = "cancelled") -> void:
	_armed.clear()
	_telemetry=null
	PROGRESS.cancel(session.state.world_state)

func _receive_or_install() -> void:
	var car := _car()
	if not is_instance_valid(car): return
	var value := PROGRESS.status(session.state.world_state,selected)
	if not value.get("mastered",false): return
	var part := str(value.reward_part)
	var owned: bool=part in GARAGE.vehicle(session.state.world_state,car.vehicle_id,car.archetype).owned
	if not owned:
		if not PROGRESS.grant_part(session.state.world_state,selected,car.vehicle_id,car.archetype): panel.set_message("Não foi possível entregar a peça neste carro."); return
		_refresh()
		panel.set_message("Peça recebida. Escolha Instalar peça quando quiser aplicar este acerto.")
	else:
		var result := GARAGE.buy(session.state.world_state,session.state.economy,car.vehicle_id,car.archetype,part,WINS.count(session.state.world_state,session.state.campaign.snapshot()))
		if not result.ok: panel.set_message(str(result.reason)); return
		ADAPTER.attach(car,result.parts)
		_refresh()
		panel.set_message("Peça instalada. As outras peças continuam disponíveis na preparação.")
	session.save_game()

func _open_preparation() -> void:
	if not is_instance_valid(_car()): return
	if not is_instance_valid(tuning_panel):
		tuning_panel=preload("res://gameplay/desert_cars/DesertTuningPanel.gd").new()
		add_child(tuning_panel)
		tuning_panel.layer=72
		tuning_panel.mechanic_name="Oficina da reta"
		tuning_panel.owned_only=true
		tuning_panel.purchase_requested.connect(_equip_part)
		tuning_panel.remove_requested.connect(_remove_part)
		tuning_panel.loadout_requested.connect(_apply_preparation)
		tuning_panel.closed.connect(_close_preparation)
	layer.hide()
	_refresh_preparation()

func _refresh_preparation() -> void:
	var car := _car()
	if not is_instance_valid(car): return
	var record := GARAGE.vehicle(session.state.world_state,car.vehicle_id,car.archetype)
	tuning_panel.show_vehicle(ADAPTER.profile_of(car),record.parts,record.owned,WINS.count(session.state.world_state,session.state.campaign.snapshot()),session.state.economy.balance,{"archetype":car.archetype,"paint":car.paint_color})
	tuning_panel.set_message("Instale peças que já possui. Novas peças à venda ficam na oficina do Digo.")

func _close_preparation() -> void:
	var step := selected_step
	session.close_menu()
	if open(selected): selected_step=step; _refresh()

func _can_prepare() -> bool:
	return _available() and session.modal and is_instance_valid(tuning_panel) and tuning_panel.visible and is_instance_valid(_car())

func _equip_part(part: String) -> void:
	if not _can_prepare(): return
	var car := _car()
	var record := GARAGE.vehicle(session.state.world_state,car.vehicle_id,car.archetype)
	if part not in record.owned: tuning_panel.set_message("Adquira a peça na oficina ou conquiste-a nos desafios."); return
	var result := GARAGE.buy(session.state.world_state,session.state.economy,car.vehicle_id,car.archetype,part,WINS.count(session.state.world_state,session.state.campaign.snapshot()))
	if not result.ok: tuning_panel.set_message(str(result.reason)); return
	ADAPTER.attach(car,result.parts)
	session.save_game()
	_refresh_preparation()

func _apply_preparation(parts: Dictionary) -> void:
	if not _can_prepare(): return
	var car := _car()
	var record := GARAGE.vehicle(session.state.world_state,car.vehicle_id,car.archetype)
	if TUNING.clean_parts(parts) != parts: tuning_panel.set_message("Ajuste inválido."); return
	for part in parts.values():
		if part not in record.owned:
			tuning_panel.set_message("Adquira a peça na oficina ou conquiste-a nos desafios.")
			return
	var result := GARAGE.apply_loadout(session.state.world_state,session.state.economy,car.vehicle_id,car.archetype,parts,WINS.count(session.state.world_state,session.state.campaign.snapshot()))
	if not result.ok: tuning_panel.set_message(str(result.reason)); return
	ADAPTER.attach(car,result.parts)
	session.save_game()
	_refresh_preparation()

func _remove_part(slot: String) -> void:
	if not _can_prepare() or slot not in TUNING.SLOTS: return
	var car := _car()
	var garage := GARAGE.data(session.state.world_state)
	var record := GARAGE.vehicle(session.state.world_state,car.vehicle_id,car.archetype)
	record.parts.erase(slot)
	garage.vehicles[car.vehicle_id]=record
	session.state.world_state.desert_garage=garage
	ADAPTER.attach(car,record.parts)
	session.save_game()
	_refresh_preparation()
