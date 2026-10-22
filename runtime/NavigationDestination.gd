extends RefCounted
## Shared read-only destination for the minimap and world map. Never advances a quest.
const NAMES := {"maciota":"Maciota", "helena":"North Pier · Helena", "harbor_parcel":"Encomenda no porto", "ferrugem":"Ferrugem", "neco":"Neco", "neco_bay":"Baia do Neco", "ashbend_start":"Telefone dos Cobras", "ashbend_finish":"Chegada nas docas", "ashbend_resident":"Moradora de Ashbend", "resident_encounter":"Moradora de Ashbend", "cobra_supply":"Quadra dos Cobras", "supply_encounter":"Quadra dos Cobras", "boss_encounter":"Líder dos Cobras", "cobra_leader_house":"Casa do líder", "transfer_document":"Lista de Vicente", "jessica":"Jessica", "jessica_jetta":"Jetta de Jessica", "harbor_bank":"North Pier"}

static func destination(point: Vector3, title: String, kind: String, region: String, text := "", source := "mission") -> Dictionary:
	if not point.is_finite(): return {}
	return {"point":point,"title":title,"kind":kind,"region":region,"text":text,"source":source}

static func resolve(session) -> Dictionary:
	var state = session.state
	var result := {}
	if not state.campaign.active_id.is_empty():
		var mission = session.mission_world
		var id: String = state.campaign.target_id()
		var title: String = NAMES.get(id,"Checkpoint" if id.begins_with("ashbend_gate_") else "Objetivo da missão")
		var kind := "bank" if id in ["helena","harbor_bank"] else "workshop" if id in ["neco","neco_bay","ferrugem","maciota"] else "objective"
		if id.begins_with("ashbend_gate_"):
			title="Checkpoint %d/4" % (id.trim_prefix("ashbend_gate_").to_int()+1)
			kind="race"
		if id == "story_tow_vehicle":
			title = "Guincho do Neco" if mission._needs_tow_truck() else "Caminhonete da cliente"
			kind = "tow" if mission._needs_tow_truck() else "objective"
		result = destination(mission.target_position(),title,kind,"harbor",mission.objective())
	elif state.intro.stage != "complete":
		result = destination(session.world.maciota_place.entry_position,"Maciota","workshop","harbor",state.intro.objective())
	if session.arrival != null and session.arrival.active:
		result = destination(session.arrival.target,"Maciota","workshop","harbor",session.arrival.objective_text)
	if session.freight_active:
		result = destination(session.freight_target,"Entrega de carga","port","harbor",session.hud_objective)
	if session.urban_operations != null and is_instance_valid(session.urban_operations.village_quest) and state.campaign.active_id.is_empty() and state.intro.stage == "complete" and not session.arrival.active and not session.freight_active:
		var quest = session.urban_operations.village_quest
		if not quest.objective().is_empty() and quest.commerce.data.hostility <= 0:
			var point: Vector3 = quest.PUMP_POINT if quest.data.belt and quest.data.crank else quest.CRANK_POINT if quest.data.belt else quest.BELT_POINT
			result = destination(point,"Bomba do Tonico" if quest.data.belt and quest.data.crank else "Manivela" if quest.data.belt else "Correia","workshop","harbor",quest.objective())
	if session.desert != null and state.region_id == "desert":
		var text: String = session.desert.objective()
		result = destination(session.desert.target_position(),"Destino no deserto","objective","desert",text) if not text.is_empty() else {}
		var frontier = session.desert.frontier
		if is_instance_valid(frontier) and is_instance_valid(frontier.roadside) and not frontier.roadside.courier.is_empty():
			var route: Dictionary = frontier.roadside.courier.route
			result = destination(route.point,str(route.name),"port","desert",frontier.roadside.objective())
	if session.mountain_activities != null:
		var pack = session.mountain_activities
		var text: String = pack.objective()
		if not text.is_empty(): result = destination(pack.target_position(),str(pack.TITLES.get(pack.tracked,"Atividade da montanha")),"objective","mountain",text)
	if session.fishing != null and session.fishing.active:
		result = destination(session.fishing.target_position(),"Lago Sereno","fishing","harbor",session.fishing.objective())
	var transit = session.world.production.get("urban_transit")
	if result.is_empty() and transit != null and is_instance_valid(transit.urban_service) and is_instance_valid(transit.urban_service.driver_work):
		var stop: Vector3 = transit.urban_service.driver_work.target_position()
		if stop.is_finite(): result = destination(stop,"Próxima parada","bus",state.region_id,"Siga para a próxima parada.","work")
	# Explicitly marking a place selects the GPS destination. Campaign objectives
	# and progression stay intact; clearing the pin restores their navigation.
	var waypoint: Vector2 = session.world.get_meta("map_waypoint",Vector2.INF)
	if waypoint.is_finite(): result = destination(Vector3(waypoint.x,0,waypoint.y),str(session.world.get_meta("map_waypoint_title","Destino marcado")),"waypoint",str(session.world.get_meta("map_waypoint_region",state.region_id)),"","waypoint")
	return result
