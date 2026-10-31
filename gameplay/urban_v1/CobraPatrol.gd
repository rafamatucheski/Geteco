extends Node
## Patrulha limitada ao orçamento do trânsito existente; nenhum spawn por agressão.
const DRIVER := preload("res://gameplay/dispatch/DispatchDriver.gd")
const GUARD := preload("res://gameplay/urban_v1/CobraPatrolGuard.gd")
var session
var car: CharacterBody3D
var pilot: RefCounted
var hostile := false
var stolen := false
var deployed := false
var crew: Array = []
var passengers: Array[Node3D] = []
var lost := 0.0
var plan_clock := 0.0
var shot_clock := 1.2
var shots := 0
var destination := Vector3.INF
var car_magazine := 12
var car_reload := 0.0

static func select_car(owner_session, point: Vector3) -> bool:
	if owner_session.state.region_id != "harbor" or owner_session.state.campaign.cobra_status().defeated: return false
	var count: int = owner_session.get_tree().get_nodes_in_group("cobra_patrol").size()
	if count >= 3: return false
	if count == 0: return true
	return randf() < (.5 if point.distance_to(Vector3(481,0,106))<120 else .14)

static func attach(owner_session, vehicle) -> Node:
	var patrol = load("res://gameplay/urban_v1/CobraPatrol.gd").new()
	patrol.session = owner_session
	patrol.car = vehicle
	vehicle.add_child(patrol)
	return patrol

func _ready() -> void:
	name = "CobraPatrol"
	add_to_group("cobra_patrol")
	car.vehicle_id = "cobra_patrol_"+str(Time.get_ticks_usec())
	car.paint_color = Color(preload("res://runtime/MuscleFleet.gd").COBRA_PAINTS.pick_random()) if car.archetype in preload("res://runtime/MuscleFleet.gd").IDS else Color("202d26")
	car.set_meta("gang_damage_handler",Callable(self,"provoke"))
	car.set_meta("gang_theft_handler",Callable(self,"vehicle_stolen"))
	var cabin: Dictionary = preload("res://gameplay/VehicleInterior.gd").spec(car)
	for index in 2:
		var model := preload("res://gameplay/CobraModel.gd").new()
		model.tier = index
		model.seated = true
		model.seat_armed = true
		model.position = Vector3(cabin.sx, cabin.floor, cabin.sz)
		if index==1: model.position.x = -model.position.x
		car.add_child(model)
		model.fit_seat(car, cabin, index == 0)
		passengers.append(model)
		# No lowrider os dois sobem e descem com a carroceria quando a hidráulica dança no sinal.
		if car.get("hydraulics") != null: car.hydraulics.add_rider(model)

func provoke(source: Node) -> void:
	if car.health<=0 and not deployed: return
	var driving = session.world.driving
	if source!=session.world.player and not (driving.occupied and source==driving.car): return
	_alert()
	# Apenas aliados já presentes e próximos ouvem a agressão.
	for ally in get_tree().get_nodes_in_group("cobra_patrol"):
		if ally!=self and not ally.stolen and ally.car.global_position.distance_to(car.global_position)<65: ally._alert()

func _alert() -> void:
	if car.health<=0 and not deployed: return
	hostile = true
	car.set_meta("gang_hostile",true)
	lost = 0
	if deployed:
		for actor in crew:
			if is_instance_valid(actor) and not actor.dead:
				actor.last_known = session.world.player.global_position
				actor.alerted = true
				actor.set_engaged(true)
		return
	if pilot==null:
		pilot = DRIVER.new()
		pilot.setup(car,13.0,2.0)
		pilot.disable_overtaking()
	plan_clock = 0

func vehicle_stolen(side: int) -> void:
	# Chamado uma vez a partir do fluxo real de embarque, incluindo tentativas canceladas.
	provoke(session.world.player)
	stolen = true
	car.remove_meta("gang_damage_handler")
	car.remove_meta("gang_theft_handler")
	if pilot!=null: car.set_external_driver(false)
	pilot = null
	_deploy(side)

func _physics_process(delta: float) -> void:
	if not session.ready_for_play: return
	for model in passengers:
		# Depois do desembarque o modelo é do guarda; o rabecão libera os dois juntos enquanto a patrulha
		# (filha do carro) continua viva. Sem isto o erro abortava este quadro inteiro, a cada passo de
		# física (9.155 erros no teste de 16/10), e a patrulha nunca era recolhida.
		if not is_instance_valid(model): continue
		if model.get_parent() != car: continue
		model.process_mode = Node.PROCESS_MODE_INHERIT if model.is_visible_in_tree() else Node.PROCESS_MODE_DISABLED
		model.rest_in_seat(delta)
	var gameplay = session.world.gameplay
	if not hostile and car.global_position.distance_to(session.world.player.global_position)>120 and not session.world.production._on_screen(car.global_position,3):
		if stolen: queue_free()
		elif deployed: car.queue_free()
		return
	var outside: bool = session.state.place_id.is_empty() and session.state.region_id==str(car.get_meta("region_id","harbor"))
	if not outside or gameplay.health<=0 or session.state.campaign.cobra_status().defeated:
		if hostile: _stand_down()
		for actor in crew:
			if is_instance_valid(actor):
				actor.hide()
				actor.collision_layer = 0
				actor.set_physics_process(false)
		return
	if car.health<=0 and not deployed:
		# Uma explosão não produz ocupantes novos e ilesos.
		for model in passengers:
			if is_instance_valid(model): model.hide()
		deployed = true
		hostile = false
		pilot = null
	for actor in crew:
		if is_instance_valid(actor) and not actor.dead:
			actor.show()
			actor.collision_layer = 2
			actor.set_physics_process(true)
	if not hostile: return
	var target: Node3D = gameplay.pursuit_target()
	var separation := car.global_position.distance_to(target.global_position)
	if deployed:
		for actor in crew:
			if is_instance_valid(actor) and not actor.dead: separation = minf(separation,actor.global_position.distance_to(target.global_position))
	lost = lost+delta if separation>55 else 0.0
	if lost>12:
		_stand_down()
		return
	if deployed:
		if crew.size()<2 and car.health>0: _deploy(1)
		var alive := false
		for actor in crew:
			if is_instance_valid(actor) and not actor.dead:
				alive = true
				actor.show()
				actor.collision_layer = 2
				actor.set_physics_process(true)
		if not alive: hostile = false
		return
	if not car.is_visible_in_tree() or not car.is_physics_processing(): return
	plan_clock -= delta
	if plan_clock<=0:
		plan_clock = 1.5
		if not destination.is_finite() or destination.distance_to(target.global_position)>5 or pilot.route==null:
			destination = target.global_position
			# O roteador por faixa atende também dois pontos no mesmo trecho.
			# O antigo route_between retornava null ao escolher o mesmo cruzamento.
			var route: Dictionary = session.world.dispatch.router.plan(car.global_position,destination,-car.global_basis.z)
			if route.ok: pilot.set_route(route.curve)
	pilot.hold(separation<10 and not session.world.driving.occupied)
	pilot.tick(delta)
	if separation<14 and absf(car.speed)<.5 and not session.world.driving.occupied:
		_deploy(1)
		return
	shot_clock -= delta
	if car_reload > 0.0:
		car_reload = maxf(0.0, car_reload - delta)
		if car_reload <= 0.0: car_magazine = 12
	if separation<27 and shot_clock<=0 and not gameplay.player.input_locked:
		_fire(target)

func _fire(target: Node3D) -> void:
	shot_clock = 1.1
	if deployed or car_reload > 0.0: return
	if car_magazine <= 0:
		car_reload = preload("res://gameplay/CombatAudio.gd").reload_seconds("pistol")
		session.world.gameplay.police_reload(car, "pistol")
		return
	var target_side := signf(car.to_local(target.global_position).x)
	var driver_side := signf(passengers[0].position.x)
	var index := 0 if target_side == driver_side else 1
	var model: Node3D = passengers[index]
	model.aim_from_seat(target.global_position, 1.0)
	var gameplay = session.world.gameplay
	if preload("res://gameplay/CobraGunfire.gd").fire(gameplay, car, model, target, "pistol", 12.0, model.global_position + Vector3.UP * .7):
		shots += 1
		car_magazine -= 1

func _deploy(_thief_side: int) -> void:
	if car.health<=0: return
	if not stolen:
		car.set_external_driver(false)
		car.traffic = false
		pilot = null
	deployed = true
	while crew.size()<2:
		var index := crew.size()
		var point := Vector3.INF
		# Cada ocupante usa a porta do próprio assento; nunca o move através da cabine.
		var side := int(signf(car.to_local(passengers[index].global_position).x))
		for clearance in [.2, .4, .65]:
			var seat_local: Vector3 = car.to_local(passengers[index].global_position)
			var candidate := car.to_global(Vector3(float(side) * (car.half_width + .54 + clearance), .1, seat_local.z))
			candidate.y = car.global_position.y+.1
			var occupied := false
			for actor in crew:
				if is_instance_valid(actor) and actor.global_position.distance_to(candidate)<1: occupied=true
			if not occupied and session.position_clear(candidate): point=candidate; break
		if not point.is_finite(): return
		var actor := GUARD.new()
		actor.configure(session.world.gameplay,index)
		actor.visual = passengers[index]
		actor.territory = self
		actor.position = point
		session.world.add_child(actor)
		actor.set_meta("region_id",car.get_meta("region_id","harbor"))
		actor.last_known = session.world.player.global_position
		actor.alerted = true
		actor.set_engaged(hostile)
		crew.append(actor)
		actor.begin_exit(car, passengers[index], point, side)

func _stand_down() -> void:
	hostile = false
	car.remove_meta("gang_hostile")
	lost = 0
	if pilot!=null:
		car.set_external_driver(false)
		pilot = null
	if not stolen and not deployed and car.health>0:
		# O grafo ativo muda na viagem; nunca aplique ruas da montanha a um carro do porto.
		var same_region: bool = session.state.region_id==str(car.get_meta("region_id","harbor"))
		car.route = session.world.production.ambient_traffic_routes.route_near(car.global_position) if same_region else null
		if car.route!=null:
			car.route_distance = car.route.get_closest_offset(car.global_position)
			car.traffic = true
		elif not same_region:
			car.traffic = false
			car.set_physics_process(false)
	for actor in crew:
		if is_instance_valid(actor): actor.set_engaged(false)

func _exit_tree() -> void:
	for actor in crew:
		if is_instance_valid(actor): actor.queue_free()
