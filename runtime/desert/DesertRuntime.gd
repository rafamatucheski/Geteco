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
const REST := preload("res://runtime/RestUntil.gd")
const RACE_WINS := preload("res://systems/campaign/RaceWins.gd")
const RESIDENT := preload("res://runtime/desert/DesertCharacter.gd")
const FRONTIER := preload("res://runtime/desert/DesertFrontierRuntime.gd")
const MEET := preload("res://runtime/desert/drag_meet/DragMeetLife.gd")
const DIGO_ROUTINE := preload("res://runtime/desert/DesertDigoRoutine.gd")
const WORKSHOP_DRIVE := preload("res://runtime/desert/DigoWorkshopDrive.gd")
const WORKSHOP_MUSIC := preload("res://audio/workshop/DigoWorkshopMusic.gd")
var session
var extras: Node
var drag: Node3D
var story: Node3D
var frontier: Node3D
var canyon: Node3D
var discoveries: Node3D
var contracts: Node3D
var village_life: Node
var meet_life: Node3D
var digo_routine: Node3D
var tuning_panel: CanvasLayer
var tuning_car: CharacterBody3D
var workshop_drive: Node3D
var workshop_music: Node
var entrance_toll: Node
var heist: Node3D
var _room: Node3D
var _resident: Node3D
var _workshop_site := "town"
var owned_cars: Dictionary = {}
var _tick := 0.0
func configure(owner_session) -> void:
	session = owner_session
	name = "DesertRuntime"
	workshop_drive = WORKSHOP_DRIVE.new()
	add_child(workshop_drive)
	workshop_drive.configure(session)
	workshop_music = WORKSHOP_MUSIC.new()
	workshop_music.name = "DigoWorkshopMusic"
	add_child(workshop_music)
	heist=preload("res://gameplay/desert_heist/DesertHeist.gd").new()
	add_child(heist)
	heist.configure(session)
	entrance_toll=preload("res://runtime/desert/entrance/DesertToll.gd").new()
	add_child(entrance_toll)
	entrance_toll.configure(session)
	drag = DRAG.new()
	add_child(drag)
	drag.configure(session)
	drag.race_completed.connect(_race_completed)
	story = STORY.new()
	add_child(story)
	story.configure(session)
	meet_life = MEET.new()
	add_child(meet_life)
	meet_life.configure(session)
	digo_routine = DIGO_ROUTINE.new()
	add_child(digo_routine)
	digo_routine.configure(session)
	frontier=FRONTIER.new()
	add_child(frontier)
	frontier.configure(session)
	canyon=preload("res://runtime/desert/canyon/CanyonEncounter.gd").new()
	add_child(canyon)
	canyon.configure(session)
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
	tuning_panel.loadout_requested.connect(_apply_loadout)
	tuning_panel.preview_requested.connect(_preview_tuning)
	tuning_panel.preview_closed.connect(_restore_tuning_preview)
	tuning_panel.view_requested.connect(workshop_drive.focus_slot)
	tuning_panel.camera_action.connect(workshop_drive.camera_action)
	tuning_panel.orbit_requested.connect(workshop_drive.orbit_by)
	tuning_panel.closed.connect(_close_tuning)
	PROGRESS.claim_rewards(session.state.world_state,session.state.economy)
	if preload("res://runtime/desert/DesertActivitiesPolicy.gd").enabled():
		extras=preload("res://runtime/desert/DesertActivities.gd").new()
		add_child(extras)
		extras.configure(session)
func busy() -> bool: return (is_instance_valid(drag) and drag.active) or (is_instance_valid(extras) and extras.busy())
func controls_locked() -> bool: return (is_instance_valid(drag) and drag.active) or (is_instance_valid(extras) and extras.controls_locked())
func save_block_reason() -> String:
	if is_instance_valid(heist) and not heist.save_block_reason().is_empty(): return heist.save_block_reason()
	if is_instance_valid(entrance_toll) and not entrance_toll.save_block_reason().is_empty(): return entrance_toll.save_block_reason()
	if is_instance_valid(extras):
		var extra_reason: String=extras.save_block_reason()
		if not extra_reason.is_empty(): return extra_reason
	var reason: String = drag.save_block_reason() if is_instance_valid(drag) else ""
	if not reason.is_empty(): return reason
	if is_instance_valid(canyon) and not canyon.save_block_reason().is_empty(): return canyon.save_block_reason()
	return frontier.save_block_reason() if is_instance_valid(frontier) else ""
func cancel_attempt() -> void:
	if is_instance_valid(heist): heist.cancel_attempt()
	if is_instance_valid(entrance_toll): entrance_toll.cancel_attempt()
	if is_instance_valid(extras): extras.cancel_attempt()
	if is_instance_valid(drag): drag.cancel_attempt()
	if is_instance_valid(frontier): frontier.cancel_attempt()
	if is_instance_valid(canyon): canyon.cancel_attempt()
	if is_instance_valid(tuning_panel) and tuning_panel.visible: tuning_panel.discard_and_close()
func _process(delta: float) -> void:
	if session != null and session.ready_for_play:
		var active_camera := get_viewport().get_camera_3d()
		for kit in get_tree().get_nodes_in_group("desert_car_neon"):
			kit.update(session.weather.time_of_day,active_camera,session.state.place_id.is_empty(),delta)
	_tick += delta
	if _tick < .3 or session == null or not session.ready_for_play: return
	_tick = 0.0
	workshop_music.sync(session.state.region_id=="desert" and session.state.place_id=="desert_digo" and is_instance_valid(session.room),session.world.production.world_audio)
	if session.state.place_id == "desert_digo" and is_instance_valid(session.room):
		preload("res://world/desert/DigoWorkshopMaterials.gd").update_lighting(session.room.model,session.weather.get_city_lighting_factor())
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
	if is_instance_valid(tuning_car) and (session.world.gameplay.health<=0 or not _at_workshop()):
		tuning_panel.discard_and_close()
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
		car.restore_body_dents(record.get("body_dents",[]),record.get("breakaway_parts",{}),record.get("broken_glass",[]))
		car.restore_blood_stains(int(record.get("blood_stains",0)))
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
	if is_instance_valid(heist): heist.write_snapshot()
	if is_instance_valid(workshop_drive): workshop_drive.write_snapshot()
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
	if is_instance_valid(workshop_drive):
		var workshop_action: Dictionary = workshop_drive.nearest_action()
		if not workshop_action.is_empty(): return workshop_action
	if is_instance_valid(heist):
		var cargo_action: Dictionary=heist.nearest_action()
		if not cargo_action.is_empty(): return cargo_action
	if is_instance_valid(entrance_toll):
		var toll_action: Dictionary=entrance_toll.nearest_action()
		if not toll_action.is_empty(): return toll_action
	if is_instance_valid(drag) and drag.active: return drag.nearest_action()
	if is_instance_valid(extras):
		var extra_action: Dictionary=extras.nearest_action()
		if not extra_action.is_empty(): return extra_action
	if session.state.region_id!="desert": return {}
	if is_instance_valid(canyon):
		var canyon_action: Dictionary=canyon.nearest_action()
		if not canyon_action.is_empty(): return canyon_action
	var digo_action: Dictionary = digo_routine.nearest_action()
	if not digo_action.is_empty(): return digo_action
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
	if session.state.place_id.is_empty() and not session.world.driving.occupied and session.world.player.global_position.distance_to(Vector3(-315,0,-573))<1.8:
		return {"id":"desert","target":"rest","label":"Descansar até as 20h"}
	return drag.nearest_action()
func perform(action: Dictionary) -> bool:
	if action.get("id","")=="desert" and str(action.get("target","")).begins_with("digo_drive_"):
		return workshop_drive.perform(str(action.target))
	if str(action.get("target","")).begins_with("cargo_heist:"): return heist.perform(action)
	if action.get("id","")=="desert" and action.get("target","")=="entrance_toll": return entrance_toll.perform()
	if str(action.get("target","")).begins_with("canyon_cache:"): return canyon.perform(action)
	if is_instance_valid(extras) and extras.handles(action): return extras.perform(action)
	if str(action.get("target","")).begins_with("contract:"): return contracts.perform(action)
	if str(action.get("target","")).begins_with("secret:"): return frontier.perform(action)
	if str(action.get("target","")).begins_with("discovery:"): return discoveries.perform(action)
	if action.get("id","")=="desert_drag": return drag.perform(str(action.get("target","")))
	if action.get("id","")=="desert_story": return story.perform(str(action.get("target","")))
	if action.get("id","")!="desert" or nearest_action().get("target","")!=action.get("target",""): return false
	if action.target=="workshop":
		_workshop_site = "town"
		return _workshop()
	if action.target=="digo_workshop":
		if not digo_routine.begin_conversation(): return false
		_workshop_site = "meet"
		if not DIGO.workshop_unlocked(session.state.world_state): return _workshop()
		session.show_dialogue([{"speaker":"Digo","message":"Fala, Dante. Tô acertando esse motor. Trouxe algum carro pra gente preparar?"}],func():
			if _at_workshop() and session.world.gameplay.health>0: _workshop())
		return true
	if action.target=="rest":
		if REST.blocked(session): session.show_message("Encerre a atividade e despiste a polícia antes de descansar."); return false
		REST.until(session,20.0)
		return true
	return false
func _race_completed(result: Dictionary) -> void:
	PROGRESS.claim_rewards(session.state.world_state,session.state.economy)
	if not result.get("night",false) and not result.get("challenge",false): story.race_finished(result)
	session.save_game()
func _nearby_car() -> CharacterBody3D:
	if not _at_workshop(): return null
	var car: CharacterBody3D = session.world.driving.car
	if not is_instance_valid(car) or car.health<=0 or car.engine_disabled: return null
	if _workshop_site=="town" and session.state.place_id=="desert_digo" and str(car.get_meta("garage_place",""))=="desert_digo": return car
	var yard := DIGO_ROUTINE.workshop_point() if _workshop_site=="meet" else Vector3(-140,0,-603)
	if car.global_position.distance_to(yard)>55 or car.half_width>1.45 or car.half_length>3.1: return null
	return car
func _at_workshop() -> bool:
	if session.state.region_id!="desert": return false
	if _workshop_site=="meet":
		return session.state.place_id.is_empty() and session.world.player.global_position.distance_to(DIGO_ROUTINE.workshop_point())<24
	return session.state.place_id=="desert_digo"
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
		if spec.get("race_only",false): continue
		session._button("%s · R$ %d"%[spec.label,spec.price],_buy_car.bind(id))
	session._button("Fechar",session.close_menu)
	return true
func _claim_rewards() -> void:
	var paid := PROGRESS.claim_rewards(session.state.world_state,session.state.economy)
	session.close_menu()
	session.show_message(String(TranslationServer.translate("Prêmios recebidos: R$ %d"))%paid if paid>0 else "Libere espaço na carteira para receber os prêmios.")
	if paid>0: session.save_game()
func _open_tuning() -> void:
	if not is_instance_valid(tuning_car): session.close_menu(); return
	session.panel.hide()
	session.menu_closed = _dismiss_tuning
	var record := GARAGE.vehicle(session.state.world_state,tuning_car.vehicle_id,tuning_car.archetype)
	var live: bool = session.state.place_id=="desert_digo" and session.world.driving.occupied and str(tuning_car.get_meta("garage_place",""))=="desert_digo"
	tuning_panel.set_live_vehicle(tuning_car if live else null)
	if live and not workshop_drive.open_service_view(tuning_car):
		session.close_menu()
		return
	tuning_panel.show_vehicle(ADAPTER.profile_of(tuning_car),record.parts,record.owned,_race_wins(),session.state.economy.balance,{"archetype":tuning_car.archetype,"paint":tuning_car.paint_color})
func _race_wins() -> int:
	return RACE_WINS.count(session.state.world_state,session.state.campaign.snapshot())
func _close_tuning() -> void:
	if session==null: return
	_dismiss_tuning()
	session.menu_closed = Callable()
	session.close_menu()
func _dismiss_tuning() -> void:
	_restore_tuning_preview()
	if is_instance_valid(workshop_drive): workshop_drive.close_service_view()
	if is_instance_valid(tuning_panel): tuning_panel.hide()
	tuning_car = null

func _preview_tuning(parts: Dictionary) -> void:
	if not is_instance_valid(tuning_car) or not is_instance_valid(workshop_drive) or not session.world.driving.occupied: return
	preload("res://gameplay/desert_cars/TuningAppearance.gd").preview_vehicle(tuning_car,parts)

func _restore_tuning_preview() -> void:
	if not is_instance_valid(tuning_car): return
	var record := GARAGE.vehicle(session.state.world_state,tuning_car.vehicle_id,tuning_car.archetype)
	preload("res://gameplay/desert_cars/TuningAppearance.gd").preview_vehicle(tuning_car,record.parts)

func _apply_loadout(parts: Dictionary) -> void:
	if not is_instance_valid(tuning_car) or tuning_car!=_nearby_car() or not DIGO.workshop_unlocked(session.state.world_state): return
	var result := GARAGE.apply_loadout(session.state.world_state,session.state.economy,tuning_car.vehicle_id,tuning_car.archetype,parts,_race_wins())
	if not result.ok: tuning_panel.set_message(str(result.reason)); return
	ADAPTER.attach(tuning_car,result.parts)
	tuning_panel.confirm_application()
	session.save_game()
	_open_tuning()
func _buy_part(part: String) -> void:
	if not is_instance_valid(tuning_car) or tuning_car!=_nearby_car() or not DIGO.workshop_unlocked(session.state.world_state): return
	var result := GARAGE.buy(session.state.world_state,session.state.economy,tuning_car.vehicle_id,tuning_car.archetype,part,_race_wins())
	if not result.ok: tuning_panel.set_message(str(result.reason)); return
	ADAPTER.attach(tuning_car,result.parts)
	tuning_panel.confirm_application()
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
	if CARS.spec(id).get("race_only",false): return
	var saved := GARAGE.data(session.state.world_state)
	if saved.purchased.has(id): session.show_message("Você já comprou este carro."); return
	var spec: Dictionary = CARS.spec(id)
	if session.state.economy.balance<int(spec.price): session.show_message("Saldo insuficiente."); return
	if not _at_workshop(): session.close_menu(); return
	var point := DIGO_ROUTINE.parking_point() if _workshop_site=="meet" else Vector3(-123,.1,-600)
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
	if is_instance_valid(heist) and not heist.objective().is_empty(): return heist.objective()
	if is_instance_valid(drag) and drag.active: return drag.objective()
	if is_instance_valid(extras) and not extras.objective().is_empty(): return extras.objective()
	var job: String=contracts.objective()
	return job if not job.is_empty() else story.objective()
func target_position() -> Vector3:
	if is_instance_valid(heist) and not heist.objective().is_empty(): return heist.target_position()
	if is_instance_valid(drag) and drag.active: return drag.target_position()
	if is_instance_valid(extras) and not extras.objective().is_empty(): return extras.target_position()
	return contracts.target_position() if not contracts.objective().is_empty() else story.target_position()
static func validate_world(value: Dictionary, economy: Dictionary) -> bool:
	if value.has(WORKSHOP_DRIVE.KEY) and not WORKSHOP_DRIVE.valid(value[WORKSHOP_DRIVE.KEY]): return false
	if not preload("res://runtime/desert/canyon/CanyonState.gd").validate_wallet(value,economy): return false
	if value.has("desert_secrets") and not preload("res://runtime/desert/DesertSecretState.gd").valid(value.desert_secrets): return false
	if value.has("desert_bandits") and not preload("res://runtime/desert/DesertBanditEncounter.gd").valid_state(value.desert_bandits): return false
	if value.has("desert_story") and not STORY_STATE.valid(value.desert_story): return false
	if not PROGRESS.validate_wallet(PROGRESS.data(value),economy): return false
	if value.has("desert_garage") and not GARAGE.valid(value.desert_garage,economy): return false
	return true
