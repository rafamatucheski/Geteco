extends Node3D
## Jessica's encounter, real bank-haul proof and physical passenger getaway.
## Campaign owns order/reward. Robberies owns cash, crimes and bank re-opening.
const PROGRESS := preload("res://systems/campaign/JessicaProgress.gd")
const CAR_SPEC := preload("res://gameplay/jessica/JessicaCarSpec.gd")
const ACTOR := preload("res://gameplay/jessica/JessicaActor.gd")
const MODEL := preload("res://gameplay/jessica/JessicaModel.gd")
const NEON := preload("res://gameplay/jessica/JessicaNeon.gd")
const DRIVER := preload("res://gameplay/jessica/JessicaGetawayDriver.gd")
const ROUTER := preload("res://gameplay/dispatch/DispatchRoadRouter.gd")
const FLEET_STATE := preload("res://runtime/FleetState.gd")
const INTERIOR := preload("res://gameplay/VehicleInterior.gd")
const PLACES := preload("res://world/places/PlaceCatalog.gd")
const SERVICE_BUILDINGS := preload("res://world/editing/WorldServiceBuildings.gd")
const GETAWAY_VIA := Vector3(84.75,0,70)
const GETAWAY_MARKET := Vector3(175,0,79.833333)
var session
var actor: CharacterBody3D
var car: CharacterBody3D
var riding := false
var safe_destination := Vector3.INF
var route: Curve3D
var route_native := false
var route_legs: Dictionary = {}
var driver = DRIVER.new()
var _neon: Node3D
var _driver_model: Node3D
var _saved_vehicle: Dictionary = {}
var _pending_progress: Dictionary = {}
var _saved_player: Dictionary = {}
var _dialogue: Dictionary = {}
var _bank_definition_cache: Dictionary = {}
var _bank_source_row: Dictionary = {}
var _poll := 0.0
var _notice := 0.0
var _before := Vector3.ZERO
var _travelled := 0.0
var _stalled := 0.0
var _generation := 0
var _cancel_reason := ""
var _exit_probe := 0.0
var _blocked_exit_age := 0.0
var _debrief_open := false
var _return_proof: Dictionary = {}
var last_failure_diagnostic: Dictionary = {}
var last_exit_diagnostic: Dictionary = {}

func configure(owner_session) -> void:
	session = owner_session
	name = "JessicaRuntime"
	process_mode = Node.PROCESS_MODE_PAUSABLE
	if not _pending_progress.is_empty():
		var existing: Dictionary = session.state.world_state.get("jessica",_pending_progress)
		if existing != _pending_progress:
			session.controller.save_invalid = true
			return
		session.state.world_state.jessica = _pending_progress.duplicate(true)
		_pending_progress.clear()
	if _saved_vehicle.is_empty(): _saved_vehicle = session.state.world_state.get("jessica_vehicle",{}).duplicate(true)
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/campaign/jessica-dialogue.json"))
	if parsed is Dictionary: _dialogue = parsed

func _progress() -> Dictionary:
	return PROGRESS.data(session.state.world_state)

func _campaign_active() -> bool:
	return session != null and session.state.campaign.active_id == "jessica_bank"

func _eligible() -> bool:
	return session != null and session.ready_for_play and not session.controller.save_invalid and not session.rescue_pending and not session.arrest_pending and session.world.gameplay.health > 0 and session.state.region_id == "harbor" and session.state.place_id.is_empty() and not session.world.driving.occupied and not session.is_transition_blocked()

func _bank() -> Dictionary:
	return session.robberies.data if session != null and session.robberies != null else {}

func bank_job_available() -> bool:
	if session == null or _bank().is_empty(): return false
	var bank := _bank()
	return session.robberies.can_enter_bank() and not bank.bank_failed and not bank.bank_alarm and bank.bank_pending == 0 and PROGRESS.bank_mask(bank) != 7

func begin_bank_job() -> bool:
	# Journal preflight must not fabricate a meeting or a robbery acceptance.
	if session == null: return false
	if session.state.campaign.active_id.is_empty(): return bank_job_available()
	if not _campaign_active(): return false
	if _progress().bank_phase == "accepted": return true
	if session.state.campaign.step != 0 or not _contact_valid() or not is_instance_valid(car) or car.health <= 0: return false
	return PROGRESS.begin_bank_job(session.state.world_state,_bank())

func objective() -> String:
	if not _campaign_active(): return ""
	match _progress().bank_phase:
		"":
			if not bank_job_available(): return "Aguarde a reabertura do North Pier e procure Jessica na rua do banco."
			return "Encontre Jessica junto ao Jetta branco na rua do North Pier."
		"accepted": return "Entre no North Pier, recolha dinheiro do cofre e saia vivo."
		"escaped": return "Entre pela porta do passageiro do Jetta branco. Jessica conduz a fuga."
		"riding":
			if not _cancel_reason.is_empty(): return "Aguarde o Jetta parar para interromper a fuga em segurança."
			if session.world.gameplay.stars > 0 and _route_finished(): return "Aguarde a perseguição acabar para desembarcar."
			return "Fuja com Jessica até a rua da oficina."
		"returned": return "Converse com Jessica depois da fuga."
	return ""

func target_position() -> Vector3:
	if _campaign_active() and _progress().bank_phase == "accepted": return _bank_definition().entry_position
	if riding: return _safe_point()
	if _campaign_active() and _progress().bank_phase == "escaped" and is_instance_valid(car): return passenger_point()
	if is_instance_valid(actor): return actor.global_position
	if not _saved_vehicle.is_empty(): return Vector3(_saved_vehicle.position[0],_saved_vehicle.position[1],_saved_vehicle.position[2])
	return _bank_parking()

func _bank_parking() -> Vector3:
	return _bank_definition().exterior_position+Vector3(0,.12,18.4)

func _bank_definition() -> Dictionary:
	# O streaming de contatos consulta a 4 Hz mesmo antes de a Jessica ser liberada. Montar
	# o catálogo inteiro de lugares ali repetia trabalho de mapa sem relação a cada consulta.
	# Compara uma cópia da linha do banco para que mudanças vivas do editor (inclusive no lugar)
	# e recargas do disco ainda movam o encontro e o alvo da missão aceita.
	var source_row := SERVICE_BUILDINGS.row_for("harbor_bank")
	if _bank_definition_cache.is_empty() or source_row != _bank_source_row:
		_bank_definition_cache = PLACES.get_definition("harbor_bank")
		_bank_source_row = source_row.duplicate(true)
	return _bank_definition_cache

func _safe_point() -> Vector3:
	if safe_destination.is_finite(): return safe_destination
	return session.world.maciota_place.tour_parking

func _contact_valid() -> bool:
	if not _eligible() or session.world.gameplay.stars > 0 or not is_instance_valid(actor): return false
	if actor.global_position.distance_to(session.world.player.global_position) > 3.2: return false
	return _clear_segment(session.world.player.global_position,actor.global_position,[session.world.player.get_rid(),actor.get_rid()])

func _clear_segment(from: Vector3, to: Vector3, exclude: Array[RID]) -> bool:
	var ray := PhysicsRayQueryParameters3D.create(from+Vector3.UP*.9,to+Vector3.UP*.9,7,exclude)
	return session.world.get_world_3d().direct_space_state.intersect_ray(ray).is_empty()

func passenger_point() -> Vector3:
	if not is_instance_valid(car): return Vector3.INF
	return car.to_global(Vector3(car.half_width+.63,.04,-.16))

func _boardable() -> bool:
	if not _eligible() or not _campaign_active() or _progress().bank_phase != "escaped": return false
	if not is_instance_valid(car) or car.health <= 0 or car.has_meta("awaiting_ground") or absf(car.speed) > .3: return false
	var player = session.world.player
	return player.global_position.distance_to(passenger_point()) < 2.2 and _clear_segment(player.global_position,passenger_point(),[player.get_rid(),car.get_rid()])

func nearest_action() -> Dictionary:
	if riding:
		return {"id":"jessica","target":"exit","label":"Interromper a fuga" if _blocked_exit_age < 15 else "Saída bloqueada · pedir resgate"}
	if session == null or session.modal: return {}
	if _boardable(): return {"id":"jessica","target":"board","label":"Embarcar com Jessica","position":passenger_point()}
	if not _contact_valid(): return {}
	if is_instance_valid(car) and car.health <= 0: return {"id":"jessica","target":"repair","label":"Recuperar o Jetta","position":actor.global_position}
	if _campaign_active() and session.state.campaign.step == 0: return {"id":"jessica","target":"agree","label":"Conversar com Jessica","position":actor.global_position}
	if _campaign_active() and _progress().bank_phase == "returned": return {"id":"jessica","target":"debrief","label":"Conversar com Jessica","position":actor.global_position}
	if not session.state.campaign.active_id.is_empty(): return {}
	return {"id":"jessica","target":"talk","label":"Conversar com Jessica","position":actor.global_position}

func perform(target: String) -> bool:
	if nearest_action().get("target","") != target: return false
	match target:
		"exit":
			if _blocked_exit_age >= 15:
				session._menu("Saída bloqueada")
				session._button("Continuar aguardando",session.close_menu)
				session._button("Pedir resgate",session._on_death)
				return true
			var cancelled := cancel_attempt("requested_exit")
			if cancelled: session.mission_world.cancel_attempt("requested_exit")
			return true
		"board": return _board()
		"repair": return _recover_car()
		"debrief": _show_debrief(); return true
		"agree":
			if not bank_job_available():
				session.show_message("Jessica: o North Pier ainda não reabriu. Volta quando as portas estiverem livres.")
				return true
			var lines := _lines("bank_offer")
			if not _progress().met: lines = _lines("first_meeting")+lines
			var generation := _generation
			_face_player()
			actor.set_talking(true)
			session.show_dialogue(lines,func():
				if is_instance_valid(actor): actor.set_talking(false)
				if generation != _generation or not _contact_valid() or not _campaign_active(): return
				var before := _progress()
				if not begin_bank_job(): session.show_message("O serviço não está disponível agora."); return
				if not session.mission_world._event("jessica_bank_agreed","jessica",{"jessica_agreed":true}): session.state.world_state.jessica = before)
			return true
		"talk":
			var key := "after_job" if _progress().bank_complete else "first_meeting"
			_face_player()
			actor.set_talking(true)
			var generation := _generation
			session.show_dialogue(_lines(key),func():
				if is_instance_valid(actor): actor.set_talking(false)
				if generation == _generation and _contact_valid(): PROGRESS.mark_met(session.state.world_state); session.save_game())
			return true
	return false

func _face_player() -> void:
	if not is_instance_valid(actor): return
	var toward: Vector3 = session.world.player.global_position-actor.global_position
	actor.rotation.y = atan2(toward.x,toward.z)

func _lines(key: String) -> Array:
	var lines: Array = []
	var language := "en" if TranslationServer.get_locale().begins_with("en") else "pt"
	for line in _dialogue.get(key,[]): lines.append({"speaker":line.speaker,"message":line[language]})
	return lines

func _physics_process(delta: float) -> void:
	if session == null or not session.ready_for_play or not is_finite(delta) or delta <= 0: return
	if riding: _tick_ride(delta)
	_poll -= delta
	if _poll > 0: return
	_poll = .25
	if _campaign_active() and _progress().bank_phase == "accepted": _observe_bank_escape()
	if riding: return
	_stream_contact()
	if is_instance_valid(car) and not car.is_queued_for_deletion(): _saved_vehicle = FLEET_STATE.capture(car,"harbor")
	if _campaign_active() and _progress().bank_phase == "returned" and not session.modal: _show_debrief()

func _process(delta: float) -> void:
	if session == null or not is_instance_valid(_neon) or not session.ready_for_play: return
	var clock: float = session.weather.time_of_day if session.weather != null else float(session.state.world_state.get("time",.32))
	_neon.update(clock,session.world.camera,session.state.place_id.is_empty() and session.state.region_id == "harbor",delta)

func _observe_bank_escape() -> void:
	if not _eligible(): return
	var progress := _progress()
	var bank := _bank()
	if bank.bank_failed: return
	if int(bank.bank_cycle) != progress.bank_cycle:
		session.mission_world.cancel_attempt("bank_cycle_changed")
		session.show_message("O banco mudou o turno de segurança. Procure Jessica para reorganizar o serviço.")
		return
	var mask := PROGRESS.bank_mask(bank)
	if (mask & (7 ^ int(progress.baseline_mask))) == 0: return
	var receipt := "bank_haul:%d:%d" % [progress.bank_cycle,mask]
	var paid: bool = session.state.economy.has_reward_receipt(receipt)
	var proof := {"cycle":progress.bank_cycle,"mask":mask,"receipt":receipt,"receipt_paid":paid,
		"alive":session.world.gameplay.health > 0,"outside_bank":session.state.place_id.is_empty(),"bank_failed":bank.bank_failed}
	if not PROGRESS.report_world_event(session.state.world_state,"bank_escaped",proof): return
	if not session.mission_world._event("jessica_bank_haul_escaped","harbor_bank",{
		"bank_cycle":progress.bank_cycle,"bank_haul_mask":mask,"bank_haul_receipt":receipt,"bank_receipt_paid":paid,
		"secured_bank_haul":true,"outside_bank":true}): session.state.world_state.jessica = progress

func _stream_contact() -> void:
	var unlocked: bool = session.state.campaign.snapshot().completed.has("cobra_race") or _campaign_active()
	var exterior: bool = session.state.region_id == "harbor" and session.state.place_id.is_empty()
	var point := _bank_parking() if _saved_vehicle.is_empty() else Vector3(_saved_vehicle.position[0],_saved_vehicle.position[1],_saved_vehicle.position[2])
	if is_instance_valid(car): point = car.global_position
	var nearby: bool = exterior and session.world.player.global_position.distance_to(point) < 70
	if not unlocked or not nearby:
		if is_instance_valid(actor): actor.queue_free(); actor = null
		if is_instance_valid(car) and not car.controlled and (not exterior or session.world.player.global_position.distance_to(point) > 100): _retire_car()
		return
	if not is_instance_valid(car): _ensure_car()
	if not is_instance_valid(car) or car.has_meta("awaiting_ground") or car.is_queued_for_deletion(): return
	if not is_instance_valid(actor):
		var destination := car.to_global(Vector3(car.half_width+.7,.04,-.70))
		if not session.position_clear(destination): return
		actor = ACTOR.new()
		actor.position = destination
		actor.rotation.y = car.rotation.y
		add_child(actor)
		_match_dante_height()
	elif not actor.visible and session.position_clear(actor.global_position):
		actor.collision_layer = 2
		actor.collision_mask = 7
		actor.show()

func _ensure_car() -> void:
	var matches: Array = []
	for existing in session.controller.vehicles:
		if is_instance_valid(existing) and not existing.is_queued_for_deletion() and existing.vehicle_id == CAR_SPEC.ID: matches.append(existing)
	if matches.size() > 1:
		session.controller.save_invalid = true
		return
	if matches.size() == 1:
		car = matches[0]
		if car.archetype != CAR_SPEC.ID: session.controller.save_invalid = true; car = null; return
	elif not _saved_vehicle.is_empty():
		var point := Vector3(_saved_vehicle.position[0],_saved_vehicle.position[1],_saved_vehicle.position[2])
		car = session.controller.spawn_vehicle(CAR_SPEC.ID,point,float(_saved_vehicle.yaw))
		if car == null: return
		car.health = float(_saved_vehicle.health)
		car.restore_body_dents(_saved_vehicle.get("body_dents",[]),_saved_vehicle.get("breakaway_parts",{}),_saved_vehicle.get("broken_glass",[]))
		car.restore_blood_stains(int(_saved_vehicle.get("blood_stains",0)))
		car.paint_color = Color.html(_saved_vehicle.get("paint","f1f0eaff"))
		car.equipment_state = _saved_vehicle.get("equipment",{}).duplicate(true)
	else:
		for offset in [0.0,6.0,-6.0,12.0,-12.0]:
			car = session.controller.spawn_vehicle(CAR_SPEC.ID,_bank_parking()+Vector3(offset,0,0),-PI*.5)
			if car != null: break
		if car == null: return
		car.paint_color = Color("f1f0ea")
	car.vehicle_id = CAR_SPEC.ID
	car.set_meta("owner_id","jessica")
	car.set_meta("personal_vehicle",true)
	car.set_meta("race_owned",true)
	car.set_meta("region_id","harbor")
	car.remove_from_group("drivable")
	var exiting := _on_car_exiting.bind(car)
	if not car.tree_exiting.is_connected(exiting): car.tree_exiting.connect(exiting)
	_neon = NEON.install(car)
	_saved_vehicle = FLEET_STATE.capture(car,"harbor")

func _on_car_exiting(owned_car: CharacterBody3D) -> void:
	# Captura antes de o corpo/equipamento saírem da árvore, incluindo a limpeza de destroços
	# entre consultas de proximidade. O streaming nunca cria um Jetta novo sem dano.
	if is_instance_valid(owned_car): _saved_vehicle = FLEET_STATE.capture(owned_car,"harbor")
	if owned_car == car:
		car = null
		_neon = null

func _match_dante_height() -> void:
	# Mede uma vez no spawn. O corpo feminino fixo fica mais esguio na mesma altura.
	var bounds := AABB()
	var first := true
	for part in session.world.player.visual.find_children("*","MeshInstance3D",true,false):
		if part.mesh == null: continue
		var relative: Transform3D = session.world.player.global_transform.affine_inverse()*part.global_transform
		var box: AABB = relative*part.get_aabb()
		bounds = box if first else bounds.merge(box)
		first = false
	if not first and bounds.size.y > 1.4 and bounds.size.y < 2.0:
		actor.visual.scale = Vector3.ONE*(bounds.size.y/1.76)

func _retire_car() -> void:
	if not is_instance_valid(car): return
	_saved_vehicle = FLEET_STATE.capture(car,"harbor")
	car.collision_layer = 0
	car.collision_mask = 0
	car.set_physics_process(false)
	session.controller.vehicles.erase(car)
	car.queue_free()
	car = null
	_neon = null

func _board() -> bool:
	if not _boardable(): return false
	var plan := _plan_getaway()
	route_native = bool(plan.get("native",false))
	if not plan.ok or float(plan.get("end_gap",INF)) > 12 or plan.curve.get_baked_length() < 25:
		session.show_message("Jessica: ainda não temos uma saída livre até a oficina.")
		return false
	var progress := _progress()
	var proof := {"vehicle_id":car.vehicle_id,"alive":car.health > 0 and session.world.gameplay.health > 0,"passenger":true,"door_clear":true}
	if not PROGRESS.report_world_event(session.state.world_state,"getaway_boarded",proof): return false
	if not session.mission_world._event("jessica_getaway_boarded","jessica_jetta",{"correct_vehicle":true,"passenger":true,"door_clear":true,"in_vehicle":true}):
		session.state.world_state.jessica = progress
		return false
	var player = session.world.player
	_saved_player = {"layer":player.collision_layer,"mask":player.collision_mask,"physics":player.is_physics_processing(),"visible":player.visible,"locked":player.input_locked,
		"visual_transform":player.visual.transform,"body_basis":player.global_basis,
		"pose":player._capture_pose() if is_instance_valid(player.skeleton) else []}
	player.input_locked = true
	player.velocity = Vector3.ZERO
	player.collision_layer = 0
	player.collision_mask = 0
	player.set_physics_process(false)
	player.hide()
	if is_instance_valid(actor): actor.hide(); actor.collision_layer = 0; actor.collision_mask = 0
	route = plan.curve
	car.route = route
	car.route_distance = 0
	driver.setup(car,route)
	driver.placement_validator = func(point: Vector3, yaw: float) -> bool: return session.controller.vehicle_position_clear(car,point,yaw)
	car.ensure_equipment(session.world)
	_create_driver_model()
	_before = car.global_position
	_travelled = 0
	_stalled = 0
	_cancel_reason = ""
	_exit_probe = 0
	_blocked_exit_age = 0
	riding = true
	session.world.camera.target = car
	session.show_dialogue(_lines("getaway"))
	return true

func _plan_getaway(via_foundry := true) -> Dictionary:
	# O itinerário padrão Foundry/Quay usa as ruas largas de superfície. O candidato
	# antigo Union/Market continua disponível para diagnóstico explícito de rota.
	# Projeta cada waypoint na faixa dirigida antes das buscas nativas.
	var router = ROUTER.new()
	router.configure(session.controller.traffic_routes)
	var union_lane: Dictionary = router.nearest_edge(GETAWAY_VIA,false,Vector3.BACK)
	var market_lane: Dictionary = router.nearest_edge(GETAWAY_MARKET,false,Vector3.RIGHT)
	var first_requested: Vector3 = GETAWAY_VIA
	if via_foundry:
		# Deriva a faixa leste da Foundry do grafo real e da rua atual do banco;
		# nunca inventa uma faixa Z fixa nem contorna o controlador do cruzamento da Quay.
		first_requested = Vector3(175,0,car.global_position.z)
		union_lane = router.nearest_edge(first_requested,false,Vector3.RIGHT)
		market_lane = router.nearest_edge(Vector3(186,0,45),false,Vector3.BACK)
	var bay: Vector3 = session.world.maciota_place.tour_parking
	# Mantém a baia do M8 ocupada pelo Maciota. A vaga oeste vizinha tem saídas
	# livres para pedestre e fica dentro do raio de doze metros da oficina.
	var parking: Vector3 = Vector3(bay.x-3.25,0,session.world.maciota_place.to_global(session.world.maciota_place.exterior_origin).z+2.9)
	var corridor_z: float = session.world.maciota_place.entry_position.z+1.2
	var road_turn_radius: float = 5.6
	var quay_target: Vector3 = Vector3(186.0 if via_foundry else 189.75,0.0,corridor_z-road_turn_radius)
	var quay_lane: Dictionary = router.nearest_edge(quay_target,false,Vector3.BACK)
	route_legs = {"itinerary":"foundry_quay" if via_foundry else "union_market_quay",
		"start":str(car.global_position),"start_heading":str(-car.global_basis.z),
		"first_lane":_lane_diagnostic(union_lane),"second_lane":_lane_diagnostic(market_lane),"third_lane":_lane_diagnostic(quay_lane)}
	if union_lane.is_empty() or market_lane.is_empty() or quay_lane.is_empty(): return {"ok":false,"reason":"getaway_lane_missing","diagnostics":route_legs.duplicate(true)}
	var first: Dictionary = router.plan(car.global_position,union_lane.closest,-car.global_basis.z)
	var first_native: bool = router._native != null
	if not first.get("ok",false): return {"ok":false,"reason":"union_route_missing","diagnostics":route_legs.duplicate(true)}
	var first_curve: Curve3D = first.curve
	var first_length: float = first_curve.get_baked_length()
	var first_end: Vector3 = first_curve.sample_baked(first_length,true)
	var direction: Vector3 = first_curve.sample_baked(maxf(0,first_length-1.0),true).direction_to(first_end)
	var second: Dictionary = router.plan(first_end,market_lane.closest,direction)
	var second_native: bool = router._native != null
	if not second.get("ok",false): return {"ok":false,"reason":"market_route_missing","diagnostics":route_legs.duplicate(true)}
	var second_curve: Curve3D = second.curve
	var second_length: float = second_curve.get_baked_length()
	var second_end: Vector3 = second_curve.sample_baked(second_length,true)
	var second_direction: Vector3 = second_curve.sample_baked(maxf(0,second_length-1.0),true).direction_to(second_end)
	var third: Dictionary = router.plan(second_end,quay_lane.closest,second_direction)
	var third_native: bool = router._native != null
	if not third.get("ok",false): return {"ok":false,"reason":"quay_route_missing","diagnostics":route_legs.duplicate(true)}
	var third_curve: Curve3D = third.curve
	var first_seam: Dictionary = _route_seam(first_curve,second_curve)
	var second_seam: Dictionary = _route_seam(second_curve,third_curve)
	route_legs.first_native = first_native
	route_legs.second_native = second_native
	route_legs.third_native = third_native
	route_legs.first_seam = first_seam
	route_legs.second_seam = second_seam
	route_legs.legs = [_curve_diagnostic(first_curve),_curve_diagnostic(second_curve),_curve_diagnostic(third_curve)]
	route_legs.road_ids = [_plan_road_ids(router,first),_plan_road_ids(router,second),_plan_road_ids(router,third)]
	route_legs.second_start_projection = _lane_diagnostic(router.nearest_edge(first_end,false,direction))
	route_legs.third_start_projection = _lane_diagnostic(router.nearest_edge(second_end,false,second_direction))
	# A reamostragem nativa da curva pode deixar um pequeno desvio de projeção na mesma faixa.
	# Recusa lacuna, salto de altura ou tangente oposta; nunca move o corpo para casar.
	if not first_seam.clear or not second_seam.clear:
		return {"ok":false,"reason":"getaway_route_seam","diagnostics":route_legs.duplicate(true)}
	var combined: Curve3D = Curve3D.new()
	combined.bake_interval = minf(first_curve.bake_interval,minf(second_curve.bake_interval,third_curve.bake_interval))
	for leg: Curve3D in [first_curve,second_curve,third_curve]:
		for i in leg.point_count:
			var point: Vector3 = leg.get_point_position(i)
			if combined.point_count > 0 and combined.get_point_position(combined.point_count-1).distance_squared_to(point) < .0001: continue
			combined.add_point(point,leg.get_point_in(i),leg.get_point_out(i))
	var access_offset: float = combined.get_baked_length()
	var road_end: Vector3 = combined.get_point_position(combined.point_count-1)
	var radius: float = corridor_z-road_end.z
	var court_radius: float = corridor_z-parking.z
	var arrival_direction: Vector3 = third_curve.sample_baked(maxf(0,third_curve.get_baked_length()-1.0),true).direction_to(road_end)
	if radius < 5.0 or court_radius < 6.5 or arrival_direction.dot(Vector3.BACK) < .95:
		return {"ok":false,"reason":"workshop_access_geometry","diagnostics":route_legs.duplicate(true)}
	# Southbound Quay -> westbound service corridor. Both turns are sampled
	# arcs that fit Vehicle's steering radius; body motion remains physical.
	var road_center: Vector3 = Vector3(road_end.x-radius,road_end.y,road_end.z)
	for i in range(1,13):
		var angle: float = PI*.5*float(i)/12.0
		combined.add_point(road_center+Vector3(radius*cos(angle),0,radius*sin(angle)))
	var court_start: Vector3 = Vector3(parking.x+court_radius,road_end.y,corridor_z)
	var straight_start: Vector3 = combined.get_point_position(combined.point_count-1)
	if straight_start.x < court_start.x: return {"ok":false,"reason":"workshop_corridor_missing","diagnostics":route_legs.duplicate(true)}
	var length: float = straight_start.distance_to(court_start)
	for i in range(1,ceili(length)+1): combined.add_point(straight_start.lerp(court_start,minf(1,float(i)/length)))
	var court_center: Vector3 = Vector3(court_start.x,road_end.y,parking.z)
	for i in range(1,17):
		var angle: float = PI*.5*float(i)/16.0
		combined.add_point(court_center+Vector3(-court_radius*sin(angle),0,court_radius*cos(angle)))
	var end: Vector3 = combined.get_point_position(combined.point_count-1)
	combined.set_meta("traffic_open",true)
	combined.set_meta("traffic_endpoint",end)
	combined.set_meta("getaway_access_offset",access_offset)
	var gap: float = Vector2(end.x,end.z).distance_to(Vector2(_safe_point().x,_safe_point().z))
	route_legs = {"itinerary":"foundry_quay" if via_foundry else "union_market_quay",
		"via_requested":[first_requested.x,first_requested.y,first_requested.z],
		"via_lane":[union_lane.closest.x,union_lane.closest.y,union_lane.closest.z],
		"market_lane":[market_lane.closest.x,market_lane.closest.y,market_lane.closest.z],
		"quay_lane":[quay_lane.closest.x,quay_lane.closest.y,quay_lane.closest.z],"corridor_z":corridor_z,
		"end":[end.x,end.y,end.z],"first_native":first_native,"second_native":second_native,"third_native":third_native,
		"first_length":first_length,"second_length":second_length,"third_length":third_curve.get_baked_length(),
		"road_ids":[_plan_road_ids(router,first),_plan_road_ids(router,second),_plan_road_ids(router,third)],
		"access_offset":access_offset,"access_length":combined.get_baked_length()-access_offset,
		"seams":[first_seam,second_seam],"seam_distance":maxf(float(first_seam.distance),float(second_seam.distance)),
		"seam_direction_dot":minf(float(first_seam.direction_dot),float(second_seam.direction_dot)),"safe_distance":gap}
	return {"ok":true,"curve":combined,"end_gap":gap,"native":first_native and second_native and third_native}

func _lane_diagnostic(lane: Dictionary) -> Dictionary:
	if lane.is_empty(): return {}
	var edge: Dictionary = lane.get("edge",{})
	return {"closest":str(lane.get("closest",Vector3.INF)),"distance":lane.get("distance",INF),
		"road_id":edge.get("id",""),"from":edge.get("from",-1),"to":edge.get("to",-1),
		"width":edge.get("width",0),"lanes":edge.get("lanes",1)}

func _curve_diagnostic(road: Curve3D) -> Dictionary:
	var length: float = road.get_baked_length()
	var start: Vector3 = road.sample_baked(0,true)
	var end: Vector3 = road.sample_baked(length,true)
	return {"start":str(start),"end":str(end),"length":length,"points":road.point_count,
		"start_tangent":str(start.direction_to(road.sample_baked(minf(1.0,length),true))),
		"end_tangent":str(road.sample_baked(maxf(0,length-1.0),true).direction_to(end)),"bake_interval":road.bake_interval}

func _plan_road_ids(router, plan: Dictionary) -> Array[String]:
	var ids: Array[String] = []
	var nodes: Array = plan.get("nodes",[])
	for i in range(nodes.size()-1):
		var edge: Dictionary = router.routes._edge(int(nodes[i]),int(nodes[i+1]))
		var id: String = str(edge.get("id",""))
		if not ids.has(id): ids.append(id)
	return ids

func _route_seam(incoming: Curve3D, outgoing: Curve3D) -> Dictionary:
	var incoming_length: float = incoming.get_baked_length()
	var end: Vector3 = incoming.sample_baked(incoming_length,true)
	var start: Vector3 = outgoing.sample_baked(0,true)
	var before: Vector3 = incoming.sample_baked(maxf(0,incoming_length-1.0),true).direction_to(end)
	var after: Vector3 = start.direction_to(outgoing.sample_baked(minf(1.0,outgoing.get_baked_length()),true))
	var distance: float = end.distance_to(start)
	var height: float = absf(end.y-start.y)
	var direction_dot: float = before.dot(after)
	return {"clear":distance <= .75 and height <= .15 and direction_dot >= .95,
		"distance":distance,"height":height,"direction_dot":direction_dot,
		"incoming_end":str(end),"outgoing_start":str(start),"incoming_tangent":str(before),"outgoing_tangent":str(after)}

func _create_driver_model() -> void:
	INTERIOR.attach(car)
	INTERIOR.open_view(car)
	_driver_model = MODEL.new()
	_driver_model.name = "JessicaDriver"
	_driver_model.position = Vector3(-.36,.05,-.08)
	_driver_model.rotation.y = PI
	_driver_model.sit_amount = 1.0
	_driver_model.seat_height = .36
	car.add_child(_driver_model)
	_seat_passenger()

func _seat_passenger() -> void:
	# Reaproveita o rig real do Dante e o encaixe de cabine da produção; sem ator
	# ou viewport duplicados. A posse de colisão/controle independe da visibilidade.
	var player = session.world.player
	var cabin: Dictionary = INTERIOR.spec(car)
	if cabin.is_empty(): return
	INTERIOR.seat_driver(player,car,0.0)
	var passenger: Dictionary = cabin.duplicate(true)
	passenger.sx = absf(float(cabin.sx))
	var state: Dictionary = player.get_meta("seated_state",{})
	var origin: Vector3 = state.get("origin",Vector3.ZERO)
	origin.x += float(passenger.sx)-float(cabin.sx)
	state.origin = origin
	player.set_meta("seated_state",state)
	player.visual.position = origin
	var targets: Dictionary = INTERIOR._limb_targets(passenger)
	var lap_y: float = float(passenger.floor)+float(passenger.hip)+.17
	var lap_z: float = float(passenger.sz)-.21
	var hands := {
		"Left":Transform3D(Basis.IDENTITY,Vector3(float(passenger.sx)-.13,lap_y,lap_z)),
		"Right":Transform3D(Basis.IDENTITY,Vector3(float(passenger.sx)+.13,lap_y,lap_z))}
	player.pose_seated_limbs(targets.feet,hands)
	player.show()

func _route_finished() -> bool:
	return is_instance_valid(car) and route != null and car.route_distance >= route.get_baked_length()-1.5 and car.global_position.distance_to(route.sample_baked(route.get_baked_length(),true)) < 3.0 and absf(car.speed) < .3 and car.is_on_floor() and _inside_courtyard() and car.global_position.distance_to(_safe_point()) <= 12

func _tick_ride(delta: float) -> void:
	if not is_instance_valid(car):
		session._on_death()
		return
	if session.rescue_pending or session.arrest_pending or session.world.gameplay.health <= 0:
		driver.tick(delta,true)
		return
	if session.world.player.seated: INTERIOR.follow(session.world.player,car,delta)
	else: session.world.player.global_position = car.global_position
	var travelled := Vector2(car.global_position.x-_before.x,car.global_position.z-_before.z).length()
	_travelled += travelled
	_before = car.global_position
	if travelled < .08*delta and not session.modal and not _route_finished() and not driver.waiting_for_traffic: _stalled += delta
	else: _stalled = 0
	if car.health <= 0 and _cancel_reason.is_empty(): _cancel_reason = "getaway_vehicle_destroyed"
	if (_stalled > 25 or driver.traffic_wait_expired) and _cancel_reason.is_empty():
		_cancel_reason = "getaway_traffic_flow_blocked" if driver.traffic_wait_expired else "getaway_blocked"
		if session.world.get_meta("jessica_diagnostics",false):
			last_failure_diagnostic = getaway_debug()
			print("JESSICA_GETAWAY_BLOCKED ",JSON.stringify(last_failure_diagnostic))
		session.show_message("Percurso bloqueado. Jessica está procurando um lugar seguro para parar.")
	driver.tick(delta,session.modal or not _cancel_reason.is_empty())
	if is_instance_valid(_driver_model):
		_driver_model.hand_targets = [car.to_global(Vector3(-.48,.79,-.49)),car.to_global(Vector3(-.22,.79,-.49))]
	if session.modal or absf(car.speed) > .3: return
	_exit_probe -= delta
	if _exit_probe > 0: return
	_exit_probe = .25
	if not _cancel_reason.is_empty():
		var reason := _cancel_reason
		if _leave(false): session.mission_world.cancel_attempt(reason); session.show_message("Fuga interrompida. Reorganize-se antes de tentar novamente.")
	elif _route_finished() and session.world.gameplay.stars == 0:
		if _leave(true): _show_debrief()

func getaway_debug() -> Dictionary:
	var value := {"driver":driver.debug_snapshot(),"stalled":_stalled,"travelled":_travelled,
		"modal":session.modal,"dialogue_open":session.dialogue_open,"position_transition":session.has_position_transition(),
		"player_position":str(session.world.player.global_position),"player_layer":session.world.player.collision_layer,
		"player_mask":session.world.player.collision_mask,"player_visible":session.world.player.visible}
	if is_instance_valid(actor):
		value.actor = {"position":str(actor.global_position),"layer":actor.collision_layer,"mask":actor.collision_mask,"visible":actor.visible}
	if not is_instance_valid(car): return value
	var contacts: Array = []
	for i in car.get_slide_collision_count():
		var contact = car.get_slide_collision(i)
		var body = contact.get_collider()
		contacts.append({"path":str(body.get_path()) if body is Node else str(body),"position":str(contact.get_position()),"normal":str(contact.get_normal())})
	value.vehicle = {"position":str(car.global_position),"velocity":str(car.velocity),"speed":car.speed,
		"physics":car.is_physics_processing(),"controlled":car.controlled,"external_input":car.external_input,
		"input_locked":car.input_locked,"engine_disabled":car.engine_disabled,"brake":car.brake_input,
		"throttle":car.throttle_input,"steer":car.steer_input,"awaiting_ground":car.has_meta("awaiting_ground"),
		"on_floor":car.is_on_floor(),"layer":car.collision_layer,"mask":car.collision_mask,"contacts":contacts}
	return value

func _exit_point(side: int, occupied := Vector3.INF) -> Vector3:
	if not is_instance_valid(car): return Vector3.INF
	for lateral in [0.0,.6,1.2]:
		for along in [-.16,.9,-1.2]:
			var point: Vector3 = car.to_global(Vector3(side*(car.half_width+.63+lateral),.04,along))
			if occupied.is_finite() and point.distance_to(occupied) < .8: continue
			var capsule := CapsuleShape3D.new()
			capsule.radius = .30
			capsule.height = 1.7
			var query := PhysicsShapeQueryParameters3D.new()
			query.shape = capsule
			query.collision_mask = 7
			var excluded: Array[RID] = [car.get_rid(),session.world.player.get_rid()]
			if is_instance_valid(actor): excluded.append(actor.get_rid())
			query.exclude = excluded
			query.transform = Transform3D(Basis.IDENTITY,point+Vector3.UP*.86)
			if not session.world.get_world_3d().direct_space_state.intersect_shape(query,1).is_empty(): continue
			var start: Vector3 = car.to_global(Vector3(side*(car.half_width+.04),.04,along))
			query.transform.origin = start+Vector3.UP*.86
			query.motion = point-start
			var sweep: PackedFloat32Array = session.world.get_world_3d().direct_space_state.cast_motion(query)
			if sweep[0] < 1.0: continue
			var ground := PhysicsRayQueryParameters3D.create(point+Vector3.UP*.3,point-Vector3.UP*.3,1)
			if session.world.get_world_3d().direct_space_state.intersect_ray(ground).is_empty(): continue
			return point
	return Vector3.INF

func _leave(completed: bool) -> bool:
	if not riding or not is_instance_valid(car) or absf(car.speed) > .3: return false
	var passenger := _exit_point(1)
	var driver_exit := _exit_point(-1,passenger)
	if not passenger.is_finite() or not driver_exit.is_finite():
		_blocked_exit_age += .25
		_notice -= .25
		if _notice <= 0: session.show_message("Saída ocupada. Aguardando espaço para desembarcar."); _notice = 4
		return false
	var proof := {"vehicle_id":car.vehicle_id,"alive":session.world.gameplay.health > 0 and car.health > 0,
		"route_finished":_route_finished(),"safe_exit":true,"exterior":session.state.region_id == "harbor" and session.state.place_id.is_empty(),
		"inside_courtyard":_inside_courtyard(),
		"wanted":session.world.gameplay.stars,"travelled":_travelled,"safe_distance":car.global_position.distance_to(_safe_point())}
	if completed and not PROGRESS.report_world_event(session.state.world_state,"safe_return",proof): return false
	last_exit_diagnostic = {"before_stop":_parking_state(),"passenger":str(passenger),"driver_exit":str(driver_exit)}
	_stop_car()
	last_exit_diagnostic.after_stop = _parking_state()
	_restore_player(passenger)
	last_exit_diagnostic.after_passenger = _parking_state()
	riding = false
	if is_instance_valid(actor):
		actor.global_position = driver_exit
		actor.force_update_transform()
		actor.collision_layer = 2
		actor.collision_mask = 7
		actor.show()
	last_exit_diagnostic.after_driver = _parking_state()
	if completed: _return_proof = proof
	else: PROGRESS.cancel_attempt(session.state.world_state,_cancel_reason if not _cancel_reason.is_empty() else "cancelled")
	_cancel_reason = ""
	return true

func _inside_courtyard() -> bool:
	if not is_instance_valid(car): return false
	var garage = session.world.maciota_place
	var bounds: AABB = garage.courtyard_bounds
	# Verifica a pegada completa no yaw real, em vez de só o
	# centro ou a proximidade da porta de pedestre da oficina.
	for x in [-car.half_width,car.half_width]:
		for z in [-car.half_length,car.half_length]:
			var point: Vector3 = garage.to_local(car.to_global(Vector3(x,.01,z)))-garage.exterior_origin
			if not bounds.has_point(point): return false
	return true

func _show_debrief() -> void:
	if _debrief_open or session.modal or not _campaign_active() or _progress().bank_phase != "returned" or not _contact_valid(): return
	_debrief_open = true
	var generation := _generation
	_face_player()
	actor.set_talking(true)
	session.show_dialogue(_lines("bank_debrief"),func():
		_debrief_open = false
		if is_instance_valid(actor): actor.set_talking(false)
		if generation != _generation or not _contact_valid() or not _campaign_active(): return
		var previous := _progress()
		if not PROGRESS.report_world_event(session.state.world_state,"bank_debrief",{"at_jessica":true,"alive":true,"wanted":session.world.gameplay.stars}): return
		var extras := {"correct_vehicle":is_instance_valid(car) and car.health > 0 and car.vehicle_id == CAR_SPEC.ID,
			"route_finished":true,"safe_exit":true,"travelled":float(_return_proof.get("travelled",0)),
			"inside_courtyard":_inside_courtyard(),
			"safe_distance":float(_return_proof.get("safe_distance",INF)),"on_foot":true,"wanted_level":session.world.gameplay.stars}
		if not session.mission_world._event("jessica_safe_return","maciota",extras): session.state.world_state.jessica = previous)

func _stop_car() -> void:
	if not is_instance_valid(car): return
	car.route = null
	car.traffic = false
	car.set_external_driver(false)
	car._release_junction()
	car.speed = 0
	car.horizontal_velocity = Vector3.ZERO
	car.velocity = Vector3.ZERO
	if is_instance_valid(_driver_model): _driver_model.queue_free(); _driver_model = null
	INTERIOR.close_view(car)
	_saved_vehicle = FLEET_STATE.capture(car,"harbor")

func _restore_player(destination := Vector3.INF) -> void:
	if _saved_player.is_empty(): return
	var player = session.world.player
	# Solta a pose do veículo antes que qualquer apresentação de revivência/morte do ator possa
	# tomar o esqueleto. Restaura só o estado que pertence a esta carona.
	player.release_seated(false)
	if _saved_player.has("pose") and not _saved_player.pose.is_empty(): player._apply_pose(_saved_player.pose)
	if _saved_player.has("visual_transform"): player.visual.transform = _saved_player.visual_transform
	if _saved_player.has("body_basis"): player.global_basis = _saved_player.body_basis
	# Aplica a pose exterior validada enquanto este corpo de passageiro ainda está
	# fora da colisão. Religá-lo no assento sobrepõe por um instante o
	# veículo e faz a recuperação cinemática empurrar o carro estacionado de lado.
	if destination.is_finite():
		player.teleport(destination)
		player.force_update_transform()
	player.collision_layer = _saved_player.layer
	player.collision_mask = _saved_player.mask
	player.set_physics_process(_saved_player.physics)
	player.visible = _saved_player.visible
	player.input_locked = _saved_player.locked or session.rescue_pending or session.arrest_pending or session.world.gameplay.health <= 0
	player.velocity = Vector3.ZERO
	session.world.camera.target = player
	_saved_player.clear()

func _parking_state() -> Dictionary:
	if not is_instance_valid(car): return {}
	return {"position":str(car.global_position),"yaw":car.rotation.y,"velocity":str(car.velocity),
		"horizontal":str(car.horizontal_velocity),"layer":car.collision_layer,"mask":car.collision_mask,
		"crash_slide":str(car.get_meta("crash_slide",Vector3.ZERO)),"crash_spin":car.get_meta("crash_spin",0),
		"player_position":str(session.world.player.global_position),"player_layer":session.world.player.collision_layer}

func cancel_attempt(reason := "cancelled") -> bool:
	_generation += 1
	_debrief_open = false
	if riding:
		_cancel_reason = reason
		if is_instance_valid(car): driver.tick(.001,true)
		return _leave(false)
	if is_instance_valid(actor): actor.set_talking(false)
	return PROGRESS.cancel_attempt(session.state.world_state,reason) or _progress().bank_phase in ["","complete"]

func cancel_for_transition() -> void:
	# Caller already owns a checked rescue/region transition; never choose its position.
	_generation += 1
	_stop_car()
	_restore_player()
	riding = false
	_cancel_reason = ""
	_debrief_open = false
	PROGRESS.cancel_attempt(session.state.world_state,"world_transition")
	if is_instance_valid(actor): actor.hide(); actor.collision_layer = 0; actor.collision_mask = 0

func _recover_car() -> bool:
	if not _contact_valid() or not is_instance_valid(car) or car.health > 0 or riding or absf(car.speed) > .3: return false
	var emergency = session.world.gameplay.emergency
	if is_instance_valid(emergency):
		for fire in emergency.fires:
			if not is_instance_valid(fire) or fire.intensity <= 0: continue
			var local: Vector3 = car.to_local(fire.global_position)
			if absf(local.x) < car.half_width+1.4 and absf(local.z) < car.half_length+1.4 and absf(local.y) < 3:
				session.show_message("Espere o incêndio ser apagado antes de recuperar o Jetta.")
				return false
	car.repair()
	car.engine_disabled = false
	session.show_message("Jetta recuperado. Procure Jessica para reorganizar o serviço.")
	session.save_game()
	return true

func vehicle_snapshot() -> Dictionary:
	return FLEET_STATE.capture(car,"harbor") if is_instance_valid(car) and not car.is_queued_for_deletion() else _saved_vehicle.duplicate(true)

func snapshot() -> Dictionary:
	return {"version":1,"progress":_progress(),"vehicle":vehicle_snapshot()}

static func validate_snapshot(value: Dictionary) -> bool:
	var version: Variant = value.get("version")
	if typeof(version) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(version)) or float(version) != 1: return false
	if not value.get("progress") is Dictionary or not PROGRESS.validate_snapshot(value.progress): return false
	# No in-flight save: a seated player's transient collision/pose owner cannot be inferred.
	if value.progress.bank_phase in ["riding","returned"]: return false
	if not value.get("vehicle") is Dictionary: return false
	if value.vehicle.is_empty(): return value.progress.bank_phase in ["","complete"]
	return validate_vehicle(value.vehicle)

static func validate_vehicle(value: Dictionary) -> bool:
	return value.get("archetype") == CAR_SPEC.ID and value.get("vehicle_id") == CAR_SPEC.ID and value.get("region") == "harbor" and not value.get("was_driven",false) and FLEET_STATE.validate(value)

func restore_snapshot(value: Dictionary) -> bool:
	if not validate_snapshot(value): return false
	if riding or is_instance_valid(car): return snapshot() == value
	if session != null:
		if session.state.world_state.has("jessica") and session.state.world_state.jessica != value.progress: return false
		session.state.world_state.jessica = value.progress.duplicate(true)
	else: _pending_progress = value.progress.duplicate(true)
	_saved_vehicle = value.vehicle.duplicate(true)
	return true
