extends Node
## Hail the actual street/rank car. PassengerTransport owns the physical journey.
const PLACES := preload("res://world/places/PlaceCatalog.gd")
var session
var transport
var rank
var offered: CharacterBody3D
var saved_traffic := false
var saved_brake := false
var source := Vector3.ZERO
var side := 1
var used_bays := {}

func configure(owner_transport) -> void:
	transport = owner_transport; session = transport.session
	rank = preload("res://runtime/TaxiRank.gd").new()
	rank.name = "TaxiRank"; rank.configure(self)
	add_child(rank)

static func light(vehicle, p_available: bool) -> void:
	if is_instance_valid(vehicle.visual) and vehicle.visual.has_node("TaxiLivery"):
		vehicle.visual.get_node("TaxiLivery").set_available(p_available)

func available(vehicle) -> bool:
	if not is_instance_valid(vehicle) or vehicle.is_queued_for_deletion(): return false
	return vehicle.archetype == "taxi_yellow" and vehicle.health > 0 and not vehicle.controlled and not vehicle.get_meta("taxi_stolen",false) and not vehicle.get_meta("taxi_unattended",false) and (vehicle.traffic or vehicle.get_meta("taxi_service",false)) and vehicle.is_visible_in_tree()

func nearest() -> CharacterBody3D:
	var closest: CharacterBody3D
	var distance := 5.0
	for vehicle in session.controller.vehicles:
		if not available(vehicle): continue
		var separation: float = vehicle.position.distance_to(session.world.player.position)
		if separation < distance and absf(vehicle.speed) <= 11:
			closest = vehicle; distance = separation
	return closest

func offer(vehicle, door_side := 1) -> bool:
	if not available(vehicle) or transport.riding or not transport._eligible(): return false
	if absf(vehicle.speed) > 11: return false
	if is_instance_valid(transport.car) and transport.car != vehicle:
		session.show_message("Há um veículo esperando seu embarque."); return true
	if is_instance_valid(offered): return true
	if session.world.player.position.distance_to(vehicle.position) > 6: return false
	var q := PhysicsRayQueryParameters3D.create(session.world.player.position+Vector3.UP,vehicle.position+Vector3.UP,7,[session.world.player.get_rid(),vehicle.get_rid()])
	if not session.world.get_world_3d().direct_space_state.intersect_ray(q).is_empty(): return false
	offered = vehicle; side = door_side
	vehicle.set_meta("taxi_service",true)
	source = session.world.player.position
	saved_traffic = vehicle.traffic; saved_brake = vehicle.brake_input
	vehicle.traffic = false; vehicle.brake_input = true
	session._menu("Táxi")
	session.menu_closed = cancel
	if transport.car == vehicle and transport.route != null:
		session._button("Embarcar · "+transport.destination,board_waiting)
	else: session._button("Pegar corrida",destinations)
	session._button("Roubar o táxi",steal)
	session._button("Fechar",session.close_menu)
	return true

func board_waiting() -> void:
	if not valid_offer(): session.close_menu(); return
	offered = null; session.menu_closed = Callable(); session.close_menu()
	transport._board()

func valid_offer() -> bool:
	return available(offered) and transport._eligible() and session.world.player.position.distance_to(source) < 2 and session.world.player.position.distance_to(offered.position) < 7

func cancel() -> void:
	if is_instance_valid(offered) and offered.health > 0:
		offered.traffic = saved_traffic; offered.brake_input = saved_brake
	offered = null

func destinations() -> void:
	if not valid_offer(): session.close_menu(); return
	session._menu("Destino")
	session._button("Ponto de táxi · Rodoviária",request.bind(Vector3(143,0,78.125),"Rodoviária"))
	for place in PLACES.definitions():
		if place.region != "harbor": continue
		var title := str(place.get("original_name",place.id))
		session._button(title,request.bind(place.get("return_position",place.entry_position),title))
	for index in preload("res://runtime/UrbanTransitPresentation.gd").STOPS.size():
		if transport._stop_enabled(index):
			var title: String = preload("res://runtime/UrbanTransitPresentation.gd").STOPS[index].name
			session._button(title,request.bind(transport._stop_point(index),title))
	session._button("Fechar",session.close_menu)

func request(point: Vector3, title: String) -> void:
	if not valid_offer(): session.close_menu(); return
	if absf(offered.speed) > .2: session.show_message("Aguarde o táxi parar."); return
	transport.router.configure(session.controller.traffic_routes)
	var heading: Vector3 = -offered.global_basis.z
	var plan: Dictionary = transport.router.plan(offered.position+heading*7,point,heading)
	if not plan.get("ok",false) or float(plan.get("end_gap",INF)) > 20:
		session.show_message("Não há trajeto viário até esse destino."); return
	var route := Curve3D.new()
	route.set_meta("traffic_open",true)
	route.bake_interval = .35
	var start: Vector3 = offered.position; start.y = 0
	var join: Vector3 = plan.curve.sample_baked(0)
	if start.distance_to(join) > 14:
		session.show_message("Aguarde o táxi se aproximar da rua."); return
	route.add_point(start,Vector3.ZERO,heading*2.5)
	route.add_point(join,-heading*2.5)
	for i in range(1,plan.curve.point_count):
		route.add_point(plan.curve.get_point_position(i),plan.curve.get_point_in(i),plan.curve.get_point_out(i))
	if not _merge_clear(offered,route,start.distance_to(join)):
		session.show_message("Saída do táxi ocupada. Aguarde a passagem."); return
	var vehicle = offered
	offered = null; session.menu_closed = Callable(); session.close_menu()
	vehicle.set_meta("taxi_service",true)
	vehicle.set_meta("passenger_transport",true)
	vehicle.traffic = false; vehicle.brake_input = true
	transport.car = vehicle; transport.route = route; transport.kind = "taxi"; transport.destination = title
	if not transport._board():
		session.show_message("Corrida pronta. Aproxime-se da lateral e pressione E.")

func _merge_clear(vehicle, route: Curve3D, distance: float) -> bool:
	var previous: Vector3 = route.sample_baked(0)
	for step in range(1,ceili(distance/.5)+1):
		var at: Vector3 = route.sample_baked(minf(step*.5,distance))
		var direction := at-previous
		if direction.length_squared() < .001: continue
		var yaw := atan2(-direction.x,-direction.z)
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = vehicle.shape.shape
		query.transform = Transform3D(Basis(Vector3.UP,yaw),at+Vector3.UP*(vehicle.shape.position.y+.16))
		query.collision_mask = 7
		query.exclude = [vehicle.get_rid(),session.world.player.get_rid()]
		if not session.world.get_world_3d().direct_space_state.intersect_shape(query,1).is_empty(): return false
		previous = at
	return true

func boarded(vehicle) -> void:
	light(vehicle,false)
	rank.depart(vehicle,false)
	vehicle.remove_from_group("drivable")

func steal() -> void:
	if not valid_offer(): session.close_menu(); return
	var vehicle = offered
	offered = null; session.menu_closed = Callable(); session.close_menu()
	var driving = session.world.driving
	var option: Dictionary = driving._entry_option()
	if option.get("car") != vehicle:
		vehicle.traffic = saved_traffic; vehicle.brake_input = saved_brake
		session.show_message("Aproxime-se da porta para roubar o táxi."); return
	vehicle.traffic = saved_traffic
	driving._begin_entry(vehicle,int(option.side))

func driver_entry(vehicle) -> void:
	# This also covers theft while wanted, when the passenger menu is unavailable.
	var rank_car: bool = vehicle.get_meta("taxi_rank",false)
	if rank_car:
		session.world.gameplay.report_observed_crime(15,vehicle.global_position,"theft",vehicle)
		vehicle.traffic = false
	elif available(vehicle):
		# The native Driving path ejects the seated driver and records the crime.
		vehicle.traffic = true
	vehicle.set_meta("taxi_stolen",true); vehicle.remove_meta("passenger_transport")
	light(vehicle,false); rank.depart(vehicle,true)
	if transport.car == vehicle: transport.car = null; transport.route = null

func release(vehicle) -> void:
	if not is_instance_valid(vehicle): return
	vehicle.add_to_group("drivable")
	vehicle.remove_meta("passenger_transport")
	vehicle.set_meta("taxi_service",true)
	vehicle.brake_input = true
	light(vehicle,available(vehicle))
