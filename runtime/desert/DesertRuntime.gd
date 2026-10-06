extends Node3D
const DRAG := preload("res://activities/desert_drag/DesertDrag.gd")
const PROGRESS := preload("res://activities/desert_drag/DesertDragProgress.gd")
const STORY := preload("res://runtime/desert/DesertCampaign.gd")
const STORY_STATE := preload("res://runtime/desert/DesertStoryState.gd")
const GARAGE := preload("res://runtime/desert/DesertGarageState.gd")
const ADAPTER := preload("res://gameplay/desert_cars/DesertCarAdapter.gd")
const CARS := preload("res://gameplay/desert_cars/DesertCarCatalog.gd")
const PANEL := preload("res://gameplay/desert_cars/DesertTuningPanel.gd")
const DIGO := preload("res://systems/campaign/DigoProgress.gd")
const RESIDENT := preload("res://runtime/desert/DesertCharacter.gd")
const FRONTIER := preload("res://runtime/desert/DesertFrontierRuntime.gd")
var session
var drag: Node3D
var story: Node3D
var frontier: Node3D
var discoveries: Node3D
var contracts: Node3D
var village_life: Node
var tuning_panel: CanvasLayer
var tuning_car: CharacterBody3D
var _room: Node3D
var _resident: Node3D
var owned_cars: Dictionary = {}
var _tick := 0.0
func configure(owner_session) -> void:
	session = owner_session
	name = "DesertRuntime"
	drag = DRAG.new()
	add_child(drag)
	drag.configure(session)
	drag.race_completed.connect(_race_completed)
	story = STORY.new()
	add_child(story)
	story.configure(session)
	frontier=FRONTIER.new()
	add_child(frontier)
	frontier.configure(session)
	discoveries=preload("res://runtime/desert/expansion/DesertDiscoveries.gd").new()
	add_child(discoveries)
	discoveries.configure(session)
	contracts=preload("res://runtime/desert/DesertContracts.gd").new()
	add_child(contracts)
	contracts.configure(session)
	var locals := preload("res://runtime/desert/DesertLocals.gd").new()
	add_child(locals)
	locals.configure(session)
	village_life = preload("res://runtime/desert/DesertVillageLife.gd").new()
	add_child(village_life)
	village_life.configure(session)
	tuning_panel = PANEL.new()
	add_child(tuning_panel)
	tuning_panel.purchase_requested.connect(_buy_part)
	tuning_panel.remove_requested.connect(_remove_part)
	tuning_panel.closed.connect(_close_tuning)
	PROGRESS.claim_rewards(session.state.world_state,session.state.economy)
func busy() -> bool: return is_instance_valid(drag) and drag.active
func save_block_reason() -> String:
	var reason: String = drag.save_block_reason() if is_instance_valid(drag) else ""
	if not reason.is_empty(): return reason
	return frontier.save_block_reason() if is_instance_valid(frontier) else ""
func cancel_attempt() -> void:
	if is_instance_valid(drag): drag.cancel_attempt()
	if is_instance_valid(frontier): frontier.cancel_attempt()
	if is_instance_valid(tuning_panel): tuning_panel.close_panel()
func _process(delta: float) -> void:
	if session != null and session.ready_for_play:
		var active_camera := get_viewport().get_camera_3d()
		for kit in get_tree().get_nodes_in_group("desert_car_neon"):
			kit.update(session.weather.time_of_day,active_camera,session.state.place_id.is_empty(),delta)
	_tick += delta
	if _tick < .3 or session == null or not session.ready_for_play: return
	_tick = 0.0
	var desert_region: Node3D = session.controller.regions.get("desert")
	if is_instance_valid(desert_region):
		desert_region.set_environment_activity(session.state.region_id=="desert" and session.state.place_id.is_empty(),session.world.player.global_position)
	_reconcile_owned_cars()
	if not busy():
		var garage: Dictionary = GARAGE.data(session.state.world_state)
		for car in session.controller.vehicles:
			if not is_instance_valid(car) or car.get_meta("desert_drag_rival",false): continue
			var saved: Dictionary = garage.vehicles.get(car.vehicle_id,{})
			if not saved.is_empty() and saved.archetype==car.archetype and (not car.has_meta("desert_powertrain") or car.get_meta("desert_parts",{}) != saved.parts):
				var saved_health: float = car.health
				ADAPTER.attach(car,saved.parts)
				car.restore_health(minf(saved_health,car.max_health))
	_reconcile_resident()
	if is_instance_valid(tuning_car) and (session.world.gameplay.health<=0 or session.state.place_id!="desert_digo"):
		tuning_panel.close_panel()
func _reconcile_owned_cars() -> void:
	var records: Dictionary = session.state.world_state.get("desert_fleet",{})
	for id in records:
		var found: CharacterBody3D
		for car in session.controller.vehicles:
			if is_instance_valid(car) and not car.is_queued_for_deletion() and car.vehicle_id==id:
				found=car
				break
		if is_instance_valid(found):
			_track_owned(found)
			continue
		var record: Dictionary = records[id]
		if record.region!=session.state.region_id or not session.state.place_id.is_empty(): continue
		var point := Vector3(record.position[0],record.position[1],record.position[2])
		if point.distance_to(session.world.player.global_position)>85: continue
		session.controller.region.prepare_collision_at(point)
		var car: CharacterBody3D = session.controller.spawn_vehicle(record.archetype,point,float(record.yaw),float(record.get("heavy_crush_ratio",1.0)))
		if not is_instance_valid(car): continue
		car.vehicle_id=id
		car.equipment_state=record.get("equipment",{}).duplicate(true)
		car.paint_color=Color.html(record.paint)
		var tuning: Dictionary = GARAGE.vehicle(session.state.world_state,id,car.archetype)
		ADAPTER.attach(car,tuning.parts)
		car.restore_health(float(record.health))
		if int(record.get("punctured_tires",0))>0: preload("res://gameplay/police_response/ground/TirePuncture.gd").puncture(car,int(record.punctured_tires))
		_track_owned(car)
func _track_owned(car: CharacterBody3D) -> void:
	if owned_cars.get(car.vehicle_id)==car: return
	owned_cars[car.vehicle_id]=car
	car.tree_exiting.connect(_store_owned.bind(car))
func _store_owned(car: CharacterBody3D) -> void:
	if not is_instance_valid(car) or not is_instance_valid(session): return
	if not session.state.world_state.has("desert_fleet"): session.state.world_state.desert_fleet={}
	session.state.world_state.desert_fleet[car.vehicle_id]=preload("res://runtime/FleetState.gd").capture(car,session.state.region_id)
func write_snapshot() -> void:
	for car in owned_cars.values():
		if is_instance_valid(car): _store_owned(car)
func _reconcile_resident() -> void:
	var room: Node3D = session.room if session.state.place_id in ["desert_bank","desert_digo"] else null
	if room==_room: return
	if is_instance_valid(_resident): _resident.queue_free()
	_resident = null
	_room = room
	if not is_instance_valid(room): return
	var local := Vector3(-1.5,.04,-3.45) if session.state.place_id=="desert_bank" else Vector3(8.4,.04,-1.2)
	if not session.position_clear(room.to_global(local)): _room=null; return
	if session.state.place_id=="desert_bank":
		_resident = RESIDENT.new()
		_resident.identity_id = "irene"
	else: _resident = preload("res://gameplay/digo/DigoActor.gd").new()
	_resident.position = local
	room.add_child(_resident)
func nearest_action() -> Dictionary:
	if session.state.region_id!="desert": return {}
	if busy(): return drag.nearest_action()
	var contract_action: Dictionary=contracts.nearest_action()
	if not contract_action.is_empty(): return contract_action
	var secret_action: Dictionary=frontier.nearest_action()
	if not secret_action.is_empty(): return secret_action
	var discovery_action: Dictionary=discoveries.nearest_action()
	if not discovery_action.is_empty(): return discovery_action
	if session.state.place_id=="desert_digo" and not session.world.driving.occupied and is_instance_valid(session.room):
		if session.world.player.global_position.distance_to(session.room.to_global(Vector3(8.4,0,1.65)))<1.8:
			return {"id":"desert","target":"workshop","label":"Preparar carro com Digo"}
	var action: Dictionary = story.nearest_action()
	if not action.is_empty(): return action
	if session.state.place_id.is_empty() and not session.world.driving.occupied and session.world.player.global_position.distance_to(Vector3(-315,0,-913))<1.8:
		return {"id":"desert","target":"rest","label":"Descansar até as 20h"}
	return drag.nearest_action()
func perform(action: Dictionary) -> bool:
	if str(action.get("target","")).begins_with("contract:"): return contracts.perform(action)
	if str(action.get("target","")).begins_with("secret:"): return frontier.perform(action)
	if str(action.get("target","")).begins_with("discovery:"): return discoveries.perform(action)
	if action.get("id","")=="desert_drag": return drag.perform(str(action.get("target","")))
	if action.get("id","")=="desert_story": return story.perform(str(action.get("target","")))
	if action.get("id","")!="desert" or nearest_action().get("target","")!=action.get("target",""): return false
	if action.target=="workshop": return _workshop()
	if action.target=="rest":
		if session.world.gameplay.stars>0 or not session.save_block_reason().is_empty(): session.show_message("Encerre a atividade e despiste a polícia antes de descansar."); return false
		var hours := fposmod(20.0/24.0-session.weather.time_of_day,1.0)
		session.activities.advance_time(hours*600.0)
		if session.weather.time_of_day+hours>=1.0: session.state.world_state.moon_day = session.weather.moon_day()+1
		session.weather.time_of_day = 20.0/24.0
		session.state.world_state.time = session.weather.time_of_day
		session.weather._update()
		session.save_game()
		return true
	return false
func _race_completed(result: Dictionary) -> void:
	PROGRESS.claim_rewards(session.state.world_state,session.state.economy)
	story.race_finished(result)
	session.save_game()
func _nearby_car() -> CharacterBody3D:
	var car: CharacterBody3D = session.world.driving.car
	if not is_instance_valid(car) or car.health<=0 or car.engine_disabled: return null
	if car.global_position.distance_to(Vector3(-140,0,-943))>55 or car.half_width>1.45 or car.half_length>3.1: return null
	return car
func _workshop() -> bool:
	if not DIGO.workshop_unlocked(session.state.world_state):
		session.show_dialogue([{"speaker":"Digo","message":"Vamos correr primeiro. Complete a prova comigo, ganhando ou perdendo, e a gente prepara seu carro."}])
		return true
	tuning_car = _nearby_car()
	session._menu("Digo")
	if not PROGRESS.pending_rewards(session.state.world_state,session.state.economy.snapshot()).is_empty():
		session._button("Receber prêmios pendentes",_claim_rewards)
	if is_instance_valid(tuning_car):
		session._button("Preparar "+str(preload("res://runtime/FleetCatalog.gd").spec(tuning_car.archetype).get("label","carro")),_open_tuning)
		for preset in ["rua","drag","terra"]:
			session._button("Salvar ajuste: "+preset,_preset.bind(preset,true))
			session._button("Aplicar ajuste: "+preset,_preset.bind(preset,false))
	else: session._button("Estacione seu carro no pátio para preparar",session.close_menu)
	for id in CARS.IDS:
		var spec: Dictionary = CARS.spec(id)
		session._button("%s · R$ %d"%[spec.label,spec.price],_buy_car.bind(id))
	session._button("Fechar",session.close_menu)
	return true
func _claim_rewards() -> void:
	var paid := PROGRESS.claim_rewards(session.state.world_state,session.state.economy)
	session.close_menu()
	session.show_message("Prêmios recebidos: R$ %d"%paid if paid>0 else "Libere espaço na carteira para receber os prêmios.")
	if paid>0: session.save_game()
func _open_tuning() -> void:
	if not is_instance_valid(tuning_car): session.close_menu(); return
	session.panel.hide()
	session.menu_closed = _dismiss_tuning
	var record := GARAGE.vehicle(session.state.world_state,tuning_car.vehicle_id,tuning_car.archetype)
	tuning_panel.show_vehicle(CARS.profile_for_vehicle(tuning_car),record.parts,record.owned,PROGRESS.data(session.state.world_state).wins.size(),session.state.economy.balance)
func _close_tuning() -> void:
	if session==null: return
	_dismiss_tuning()
	session.menu_closed = Callable()
	session.close_menu()
func _dismiss_tuning() -> void:
	if is_instance_valid(tuning_panel): tuning_panel.hide()
	tuning_car = null
func _buy_part(part: String) -> void:
	if not is_instance_valid(tuning_car) or tuning_car!=_nearby_car() or not DIGO.workshop_unlocked(session.state.world_state): return
	var result := GARAGE.buy(session.state.world_state,session.state.economy,tuning_car.vehicle_id,tuning_car.archetype,part,PROGRESS.data(session.state.world_state).wins.size())
	if not result.ok: tuning_panel.set_message(str(result.reason)); return
	ADAPTER.attach(tuning_car,result.parts)
	session.save_game()
	_open_tuning()
func _remove_part(slot: String) -> void:
	if not is_instance_valid(tuning_car) or tuning_car!=_nearby_car(): return
	var saved := GARAGE.data(session.state.world_state)
	var record := GARAGE.vehicle(session.state.world_state,tuning_car.vehicle_id,tuning_car.archetype)
	record.parts.erase(slot)
	saved.vehicles[tuning_car.vehicle_id] = record
	session.state.world_state.desert_garage = saved
	ADAPTER.attach(tuning_car,record.parts)
	session.save_game()
	_open_tuning()
func _preset(id: String, save_current: bool) -> void:
	if not is_instance_valid(tuning_car) or tuning_car!=_nearby_car(): session.close_menu(); return
	var saved := GARAGE.data(session.state.world_state)
	var record := GARAGE.vehicle(session.state.world_state,tuning_car.vehicle_id,tuning_car.archetype)
	if save_current: record.presets[id] = record.parts.duplicate(true)
	elif record.presets.has(id): record.parts = record.presets[id].duplicate(true)
	else: session.show_message("Nenhum ajuste salvo nesse espaço."); return
	saved.vehicles[tuning_car.vehicle_id] = record
	session.state.world_state.desert_garage = saved
	ADAPTER.attach(tuning_car,record.parts)
	session.close_menu()
	session.save_game()
func _buy_car(id: String) -> void:
	var saved := GARAGE.data(session.state.world_state)
	if saved.purchased.has(id): session.show_message("Você já comprou este carro."); return
	var spec: Dictionary = CARS.spec(id)
	if session.state.economy.balance<int(spec.price): session.show_message("Saldo insuficiente."); return
	var point := Vector3(-123,.1,-940)
	session.controller.region.prepare_collision_at(point)
	var car: CharacterBody3D = session.controller.spawn_vehicle(id,point,PI)
	if not is_instance_valid(car): session.show_message("Libere a vaga de entrega no pátio."); return
	if not session.controller.vehicle_position_clear(car,point,PI):
		car.queue_free()
		session.show_message("Libere a vaga de entrega no pátio.")
		return
	if not session.state.economy.spend(int(spec.price),"desert_car:"+id): car.queue_free(); return
	car.vehicle_id = "desert_owned_"+id
	_track_owned(car)
	_store_owned(car)
	saved.purchased[id] = car.vehicle_id
	session.state.world_state.desert_garage = saved
	session.close_menu()
	session.show_message("Carro entregue no pátio do Digo.")
	session.save_game()
func objective() -> String:
	if busy(): return drag.objective()
	var job: String=contracts.objective()
	return job if not job.is_empty() else story.objective()
func target_position() -> Vector3:
	if busy(): return drag.target_position()
	return contracts.target_position() if not contracts.objective().is_empty() else story.target_position()
static func validate_world(value: Dictionary, economy: Dictionary) -> bool:
	if value.has("desert_secrets") and not preload("res://runtime/desert/DesertSecretState.gd").valid(value.desert_secrets): return false
	if value.has("desert_bandits") and not preload("res://runtime/desert/DesertBanditEncounter.gd").valid_state(value.desert_bandits): return false
	if value.has("desert_story") and not STORY_STATE.valid(value.desert_story): return false
	if not PROGRESS.validate_wallet(PROGRESS.data(value),economy): return false
	if value.has("desert_garage") and not GARAGE.valid(value.desert_garage,economy): return false
	return true
