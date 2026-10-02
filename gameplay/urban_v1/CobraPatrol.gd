extends Node
## Patrulha limitada ao orçamento do trânsito existente; nenhum spawn por agressão.
const DRIVER := preload("res://gameplay/dispatch/DispatchDriver.gd")
const GUARD := preload("res://gameplay/urban_v1/CobraLocalGuard.gd")
const LOOK := preload("res://gameplay/urban_v1/CobraAppearance.gd")
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
	car.paint_color = Color("202d26")
	car.set_meta("gang_damage_handler",Callable(self,"provoke"))
	car.set_meta("gang_theft_handler",Callable(self,"vehicle_stolen"))
	for index in 2:
		var model := preload("res://assets/gameplay/cobra_0.scn").instantiate() as Node3D
		LOOK.dress(model)
		LOOK.arms(model,true)
		model.scale = Vector3.ONE*.95
		model.position = car.to_local(car.driver_seat_anchor())-Vector3.UP*.62
		if index==1: model.position.x = -model.position.x
		for side in ["left","right"]:
			var leg := model.find_child(side+"_upper_leg",true,false) as Node3D
			if leg: leg.rotation.x = PI*.5
		car.add_child(model)
		passengers.append(model)

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
	# Called once from the actual boarding flow, including cancelled attempts.
	provoke(session.world.player)
	stolen = true
	car.remove_meta("gang_damage_handler")
	car.remove_meta("gang_theft_handler")
	if pilot!=null: car.set_external_driver(false)
	pilot = null
	_deploy(side)

func _physics_process(delta: float) -> void:
	if not session.ready_for_play: return
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
		for model in passengers: model.hide()
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
			pilot.set_route(session.world.production.traffic_routes.route_between(car.global_position,destination))
	pilot.hold(separation<10 and not session.world.driving.occupied)
	pilot.tick(delta)
	if separation<14 and absf(car.speed)<.5 and not session.world.driving.occupied:
		_deploy(1)
		return
	shot_clock -= delta
	if separation<27 and shot_clock<=0 and not gameplay.player.input_locked:
		_fire(target)

func _fire(target: Node3D) -> void:
	shot_clock = 1.1
	var side := 1.0 if car.to_local(target.global_position).x>=0 else -1.0
	var origin := car.to_global(Vector3(side*(car.half_width+.08),1.05,0))
	var endpoint := target.global_position+Vector3.UP*.85
	var ray := PhysicsRayQueryParameters3D.create(origin,endpoint,7,[car.get_rid()])
	var hit := car.get_world_3d().direct_space_state.intersect_ray(ray)
	if hit.is_empty() or hit.collider!=target: return
	var gameplay = session.world.gameplay
	gameplay._trace(origin,hit.position,.065,.014)
	gameplay._damage(hit.collider,12.0,car)
	gameplay._sound("pistol",origin)
	gameplay.npc_gunfire.emit(origin,origin.direction_to(endpoint),car)
	shots += 1

func _deploy(thief_side: int) -> void:
	if car.health<=0: return
	if not stolen:
		car.set_external_driver(false)
		car.traffic = false
		pilot = null
	deployed = true
	while crew.size()<2:
		var index := crew.size()
		var point := Vector3.INF
		for side in [-1,1]:
			for offset in [1.25,2.5,-2.0]:
				var candidate: Vector3 = car.driver_door_anchor(side)+car.global_basis.z*offset
				candidate += car.global_basis.x*float(side)*(.65 if side==thief_side else .4)
				candidate.y = car.global_position.y+.1
				var occupied := false
				for actor in crew:
					if is_instance_valid(actor) and actor.global_position.distance_to(candidate)<1: occupied=true
				if not occupied and session.position_clear(candidate): point=candidate; break
			if point.is_finite(): break
		if not point.is_finite(): return
		var actor := GUARD.new()
		actor.configure(session.world.gameplay,index)
		actor.territory = self
		actor.position = point
		session.world.add_child(actor)
		actor.set_meta("region_id",car.get_meta("region_id","harbor"))
		actor.last_known = session.world.player.global_position
		actor.alerted = true
		actor.set_engaged(hostile)
		crew.append(actor)
		passengers[index].hide()

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
