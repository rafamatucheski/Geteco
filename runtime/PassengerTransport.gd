extends Node
## V1 TaxiService/TaxiDestinations and UrbanTransit/UrbanPlayerRide adapters.
## One requested vehicle; physical road travel, no in-flight save or fare invented.
const PRESENTATION := preload("res://runtime/UrbanTransitPresentation.gd")
const PLACES := preload("res://world/places/PlaceCatalog.gd")
const ROUTER := preload("res://gameplay/dispatch/DispatchRoadRouter.gd")
var session
var car: CharacterBody3D
var route: Curve3D
var router = ROUTER.new()
var riding := false
var stopping := false
var kind := ""
var destination := ""
var bus_stop := 0
var bus_destination := 0
var _origin_stop := -1
var _source := Vector3.ZERO
var _saved := {}
var _stalled := 0.0
var _before := Vector3.ZERO
var _dwell := 0.0
var _requested_exit := false
var _notice_clock := 0.0
var _exit_probe := 0.0
var _blocked_exit_age := 0.0
var _retired: Array[CharacterBody3D] = []
var taxis

func _ready() -> void:
	taxis = preload("res://runtime/TaxiService.gd").new()
	taxis.name = "TaxiService"
	add_child(taxis)
	taxis.configure(self)

func configure(owner_session) -> void:
	session = owner_session
	process_mode = Node.PROCESS_MODE_PAUSABLE

func _eligible() -> bool:
	return session.ready_for_play and not session.rescue_pending and not session.controller.save_invalid and session.state.region_id == "harbor" and session.state.place_id.is_empty() and not session.world.driving.occupied and session.world.gameplay.health > 0 and session.world.gameplay.stars == 0 and not session.arrival.active and session.state.campaign.active_id.is_empty() and not session.vehicle_transition_busy and session.activities.can_rest()

func _service_open() -> bool:
	var hour: float = float(session.state.world_state.get("time",.32))*24.0
	if session.weather != null: hour = session.weather.time_of_day*24.0
	return hour < 2.0 or hour >= 5.0

func _station() -> int:
	var presentation = session.controller.urban_transit
	if presentation == null: return -1
	for index in presentation.definitions.size():
		if presentation.definitions[index].get("deleted",false): continue
		if session.world.player.position.distance_to(presentation.definitions[index].position) < 9.0: return index
	return -1

func nearest_action() -> Dictionary:
	if riding and _blocked_exit_age >= 15: return {"id":"passenger_transport","label":"Saída bloqueada · pedir resgate","target":"exit"}
	if riding: return {"id":"passenger_transport","label":"Pedir desembarque","target":"exit"}
	if not _eligible() or session.modal: return {}
	var urban = _urban_service()
	if urban != null and urban.boardable_bus() != null:
		return {"id":"passenger_transport","label":"Embarcar · linha 510","target":"urban_board"}
	if is_instance_valid(car) and car.health > 0:
		if session.world.player.position.distance_to(car.position) < 7:
			return {"id":"passenger_transport","label":"Embarcar como passageiro","target":"board"}
	if taxis != null and taxis.nearest() != null:
		return {"id":"passenger_transport","label":"Táxi · corrida ou roubo","target":"taxi"}
	var index := _station()
	if index >= 0: return {"id":"passenger_transport","label":"Transporte","target":"offer"}
	return {}

func perform(target: String) -> bool:
	if nearest_action().get("target","") != target: return false
	if target == "taxi": return taxis.offer(taxis.nearest())
	if target == "urban_board": return _board_urban(_urban_service().boardable_bus())
	if target == "exit": request_exit(); return true
	if target == "board":
		if kind == "taxi" and taxis != null: return taxis.offer(car)
		session._menu("Transporte · "+destination)
		session._button("Embarcar",func(): session.close_menu(); _board())
		session._button("Dispensar veículo",_dismiss)
		session._button("Fechar",session.close_menu)
		_focus()
		return true
	_origin_stop = _station()
	_source = session.world.player.position
	session._menu("Transporte")
	session._button("Táxi",_destinations.bind("taxi"))
	if _origin_stop < PRESENTATION.STOPS.size(): session._button("Ônibus · linha 510",_destinations.bind("bus"))
	if is_instance_valid(car): session._button("Dispensar veículo",_dismiss)
	session._button("Fechar",session.close_menu)
	_focus()
	return true

func _menu_valid() -> bool:
	return _eligible() and _station() == _origin_stop and session.world.player.position.distance_to(_source) < 2

func _destinations(service: String) -> void:
	if not _menu_valid(): session.close_menu(); return
	if is_instance_valid(car):
		session.close_menu()
		session.show_message("Embarque ou dispense o veículo que já está esperando.")
		return
	kind = service
	session._menu("Destino")
	if service == "taxi":
		session._button("Ponto de táxi · Rodoviária",_request.bind(Vector3(143,0,78.125),"Rodoviária",-1))
		for place in PLACES.definitions():
			if place.region != "harbor": continue
			var point: Vector3 = place.get("return_position",place.entry_position)
			session._button(str(place.get("original_name",place.id)),_request.bind(point,str(place.get("original_name",place.id)),-1))
	for index in PRESENTATION.STOPS.size():
		if index == _origin_stop or not _stop_enabled(index): continue
		var stop: Dictionary = PRESENTATION.STOPS[index]
		session._button(str(stop.name),_request.bind(_stop_point(index),str(stop.name),index))
	session._button("Fechar",session.close_menu)
	_focus()

func _focus() -> void:
	for child in session.column.get_children():
		if child is Button: child.grab_focus.call_deferred(); break

func _stop_point(index: int) -> Vector3:
	var presentation = session.controller.urban_transit
	if presentation != null and index >= 0 and index < PRESENTATION.STOPS.size():
		return presentation.definitions[index].stop_point
	var point: Vector2 = PRESENTATION.STOPS[index].point
	return Vector3(point.x,0,point.y)/16.0

func _stop_enabled(index: int) -> bool:
	var presentation = session.controller.urban_transit
	return presentation != null and index >= 0 and index < PRESENTATION.STOPS.size() and not presentation.definitions[index].get("deleted",false)

func _next_stop(index: int) -> int:
	for offset in range(1,PRESENTATION.STOPS.size()+1):
		var next := (index+offset)%PRESENTATION.STOPS.size()
		if _stop_enabled(next): return next
	return -1

func _request(point: Vector3, label: String, stop_index: int) -> void:
	if not _menu_valid(): session.close_menu(); return
	session.close_menu()
	if kind == "bus" and not _service_open(): session.show_message("Ônibus: 05:00 às 02:00."); return
	if kind == "bus":
		var urban = _urban_service()
		if urban == null or urban.route == null:
			session.show_message("Serviço da linha 510 indisponível."); return
		if not urban.stops.any(func(stop): return stop.id==_origin_stop) or not urban.stops.any(func(stop): return stop.id==stop_index):
			session.show_message("Esta parada não está sendo atendida pela linha 510."); return
		urban.requested_destination = stop_index
		session.show_message("Aguarde a linha 510 na plataforma · "+label)
		return
	if is_instance_valid(car): session.show_message("Embarque ou dispense o veículo que já está esperando."); return
	_retired = _retired.filter(func(vehicle): return is_instance_valid(vehicle) and not vehicle.is_queued_for_deletion())
	if _retired.size() >= 2:
		session.show_message("Veículos anteriores ainda próximos. Afaste-se antes de solicitar outro."); return
	router.configure(session.controller.traffic_routes)
	bus_stop = _origin_stop
	bus_destination = stop_index
	var next := _next_stop(bus_stop)
	if kind == "bus" and (next < 0 or next == bus_stop):
		session.show_message("A linha precisa de pelo menos duas paradas."); return
	var goal := _stop_point(next) if kind == "bus" else point
	var plan: Dictionary = router.plan(session.world.player.position,goal)
	if not plan.ok or float(plan.get("end_gap",INF)) > 20:
		session.show_message("Não há trajeto viário até esse destino."); return
	route = plan.curve
	var spawn: Vector3 = route.sample_baked(0,true)+Vector3.UP*.12
	if spawn.distance_to(session.world.player.position) > 22:
		session.show_message("Aproxime-se da rua para embarcar."); return
	var direction := route.sample_baked(minf(1,route.get_baked_length()),true)-route.sample_baked(0,true)
	car = session.controller.spawn_vehicle("route_city" if kind == "bus" else "taxi_yellow",spawn,atan2(-direction.x,-direction.z))
	if not is_instance_valid(car): session.show_message("Ponto de embarque ocupado. Aguarde."); return
	car.vehicle_id = "passenger_transport"
	car.set_meta("passenger_transport",true)
	car.set_meta("taxi_service",true)
	car.traffic = false
	car.controlled = false
	destination = label
	session.show_message("Veículo pronto. Aproxime-se da lateral e pressione E para embarcar.")

func _board() -> bool:
	if not _eligible() or not is_instance_valid(car) or car.health <= 0 or absf(car.speed) > .2: return false
	if kind == "bus" and not _service_open(): session.show_message("Ônibus: 05:00 às 02:00."); return false
	var actor: CharacterBody3D = session.world.player
	var accessible := false
	for side in [-1,1]:
		var door: Vector3 = car.to_global(Vector3(side*(car.half_width+.6),0,.15))
		if actor.position.distance_to(door) > 2: continue
		var ray := PhysicsRayQueryParameters3D.create(actor.position+Vector3.UP*.9,door+Vector3.UP*.9,7,[actor.get_rid(),car.get_rid()])
		if session.world.get_world_3d().direct_space_state.intersect_ray(ray).is_empty(): accessible = true
	if not accessible: session.show_message("Aproxime-se de uma lateral livre do veículo."); return false
	if kind == "taxi" and taxis != null: taxis.boarded(car)
	_saved = {"layer":actor.collision_layer,"mask":actor.collision_mask,"physics":actor.is_physics_processing(),"visible":actor.visible,"locked":actor.input_locked}
	actor.input_locked = true
	actor.velocity = Vector3.ZERO
	actor.collision_layer = 0
	actor.collision_mask = 0
	actor.set_physics_process(false)
	actor.hide()
	riding = true
	stopping = false
	_requested_exit = false
	_stalled = 0
	_dwell = 0
	_notice_clock = 0
	_exit_probe = 0
	_blocked_exit_age = 0
	_before = car.position
	car.route = route
	car.route_distance = 0
	car.traffic = true
	session.world.camera.target = car
	session.show_message(destination+" · E ou F para pedir desembarque")
	return true

func request_exit() -> void:
	if not riding or session.rescue_pending: return
	if _blocked_exit_age >= 15:
		session._menu("Saída bloqueada")
		session._button("Continuar aguardando",session.close_menu)
		session._button("Pedir resgate",session._on_death)
		_focus()
		return
	_requested_exit = true
	if kind == "taxi": _brake()
	session.show_message("Desembarque solicitado." if kind == "taxi" else "Desembarque na próxima parada.")

func _brake() -> void:
	if kind == "urban_bus": _requested_exit = true; return
	stopping = true
	_dwell = 0
	if not is_instance_valid(car): return
	car.traffic = false
	car.controlled = false
	car.external_input = false
	car.brake_input = true

func _physics_process(delta: float) -> void:
	if not riding or session == null or not session.ready_for_play: return
	if kind == "urban_bus": _tick_urban(delta); return
	if not is_instance_valid(car):
		session._on_death()
		return
	if session.rescue_pending or session.modal: return
	session.world.player.position = car.position
	if car.health <= 0: _brake()
	# Measure progress per simulated second, independent of the frame rate.
	var travelled := Vector2(car.position.x-_before.x,car.position.z-_before.z).length()
	if travelled < .1*delta and not stopping and _dwell <= 0: _stalled += delta
	else: _stalled = 0
	_before = car.position
	if _stalled > 25: _brake(); session.show_message("Percurso bloqueado. Tentando desembarque seguro.")
	if not stopping and car.route_distance >= route.get_baked_length()-1.3 and absf(car.speed) < .3:
		if kind == "bus":
			bus_stop = _next_stop(bus_stop)
			if bus_stop < 0: _brake(); return
			if _requested_exit or bus_stop == bus_destination or not _service_open(): _brake()
			else:
				var plan: Dictionary = router.plan(car.position,_stop_point(_next_stop(bus_stop)),-car.global_basis.z)
				if not plan.ok or float(plan.get("end_gap",INF)) > 20: _brake()
				else:
					route = plan.curve; car.route = route; car.route_distance = 0; _dwell = 3
		else: _brake()
	if _dwell > 0:
		_dwell = maxf(0,_dwell-delta)
		car.traffic = _dwell <= 0
	if stopping and absf(car.speed) < .2:
		_exit_probe -= delta
		if _exit_probe > 0: return
		_exit_probe = .25
		if not _leave():
			_blocked_exit_age += .25
			_notice_clock -= .25
			if _notice_clock <= 0: session.show_message("Saída ocupada. Aguardando passagem livre."); _notice_clock = 4

func _leave() -> bool:
	# Reuse the production door capsule and swept exit check without changing ownership.
	var driving = session.world.driving
	var previous = driving.car
	driving.car = car
	var point: Vector3 = driving.exit_position()
	driving.car = previous
	if not point.is_finite(): return false
	_restore_actor()
	session.world.player.teleport(point)
	riding = false
	stopping = false
	car.route = null
	_retire()
	if session.save_game(): session.show_message("Desembarque concluído.")
	return true

func _restore_actor() -> void:
	if _saved.is_empty(): return
	var actor = session.world.player
	actor.collision_layer = _saved.layer
	actor.collision_mask = _saved.mask
	actor.set_physics_process(_saved.physics)
	actor.visible = _saved.visible
	actor.input_locked = _saved.locked
	actor.velocity = Vector3.ZERO
	session.world.camera.target = actor
	_saved.clear()

func cancel_for_transition() -> void:
	if taxis != null: taxis.cancel()
	if kind == "urban_bus":
		if is_instance_valid(car): car.player_aboard = false
		_restore_actor()
		riding = false; stopping = false; car = null; route = null; kind = ""
		return
	if is_instance_valid(car): _brake()
	_restore_actor()
	riding = false
	stopping = false
	# Caller is unloading the scene/region or performing a checked rescue.
	_retire()

func _retire() -> void:
	if is_instance_valid(car):
		if kind == "taxi" and taxis != null: taxis.release(car)
		car.traffic = false
		car.route = null
		_retired.append(car)
	car = null
	route = null
	destination = ""

func _dismiss() -> void:
	session.close_menu()
	if riding or not is_instance_valid(car): return
	# Leave the physical parked vehicle for normal distance-based cleanup.
	_retire()

func _urban_service():
	var presentation = session.controller.urban_transit
	return presentation.urban_service if presentation != null else null

func _board_urban(bus) -> bool:
	if bus == null or not _eligible(): return false
	var urban = _urban_service()
	if urban.boardable_bus() != bus: return false
	var actor = session.world.player
	# A clear segment to the open gate is mandatory even inside the action radius.
	var target: Vector3 = bus.door_point()
	var query := PhysicsRayQueryParameters3D.create(actor.global_position+Vector3.UP*.9,target+Vector3.UP*.9,1,[actor.get_rid()])
	if not session.world.get_world_3d().direct_space_state.intersect_ray(query).is_empty(): return false
	_saved = {"layer":actor.collision_layer,"mask":actor.collision_mask,"physics":actor.is_physics_processing(),"visible":actor.visible,"locked":actor.input_locked}
	actor.input_locked=true; actor.velocity=Vector3.ZERO
	actor.collision_layer=0; actor.collision_mask=0; actor.set_physics_process(false); actor.hide()
	car=bus; kind="urban_bus"; riding=true; stopping=false; _requested_exit=false
	_blocked_exit_age=0; _notice_clock=0
	bus.player_aboard=true
	bus_destination=urban.requested_destination
	urban.requested_destination=-1
	session.world.camera.target=bus
	session.show_message("Linha 510 · E ou F para pedir desembarque")
	return true

func _tick_urban(delta: float) -> void:
	if not is_instance_valid(car): session._on_death(); return
	session.world.player.position=car.global_position
	var urban = _urban_service()
	if urban == null: return
	if car.health<=0:
		# A damaged service cannot strand a hidden player permanently.
		session._on_death(); return
	if car.service_state!="exchange": return
	var stop_id: int=urban.stops[car.service_stop].id
	if not _requested_exit and stop_id!=bus_destination and _service_open(): return
	var point: Vector3=urban.exit_point(car)
	if not point.is_finite():
		car.dwell=maxf(car.dwell,2)
		_blocked_exit_age+=delta
		_notice_clock-=delta
		if _notice_clock<=0: session.show_message("Saída ocupada. Aguardando passagem livre."); _notice_clock=4
		return
	car.player_aboard=false; car.dwell=maxf(car.dwell,3)
	_restore_actor()
	session.world.player.teleport(point)
	riding=false; stopping=false; car=null; route=null; kind=""
	session.save_game()
