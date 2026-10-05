extends Node3D
const TRANSIT_WORK := preload("res://runtime/StallWorkTrace.gd")
## Four conserved services and sixteen people; no ambient spawn/despawn replacement.
const ROUTES := preload("res://runtime/terminal/TerminalRoutes.gd")
const COACH := preload("res://runtime/terminal/TerminalCoach.gd")
const GATE := preload("res://runtime/terminal/TerminalGate.gd")
const ACTOR := preload("res://scripts/Actor.gd")
const PASSENGER_MODEL := preload("res://assets/CivilianModel.gd")
var controller
var fleet: Array = []
var gates: Array = []
var apron_owner: Node3D
var road: Curve3D
var _road_prepared := false
var _passenger_meshes_prepared := false
var _road_signature: Array = []
var running := false
var resident := false
var _clock := 0.0
var guard_model: Node3D
var guard_authorizing := false

func configure(value) -> void:
	controller = value
	process_mode = Node.PROCESS_MODE_PAUSABLE

func _ready() -> void:
	name = "TerminalOperations"

## Resolve only the real route required near this saved exterior position.
## The startup caller still holds the curtain and ready_for_play is false.
## No coach, passenger, collision or simulation timer is prepared here.
func prepare_startup_route() -> void:
	if controller.state.region_id != "harbor" or not controller.state.place_id.is_empty(): return
	if controller.world.player.global_position.distance_to(ROUTES.point(0,0)) >= 100: return
	if not controller.urban_transit.instances.has("harbor_coach_terminal"): return
	prepare_road()

## Only immutable meshes are prepared; admission remains atomic in build().
## The time budget is soft: one identity is indivisible and may cross it.
func prepare_startup_passenger_meshes(budget_usec: int = 4000) -> void:
	if _passenger_meshes_prepared or controller.session.ready_for_play: return
	if controller.state.region_id != "harbor" or not controller.state.place_id.is_empty(): return
	if controller.world.player.global_position.distance_to(ROUTES.point(0,0)) >= 100: return
	if not controller.urban_transit.instances.has("harbor_coach_terminal"): return
	var slice_start := Time.get_ticks_usec()
	var slice_probe := TRANSIT_WORK.begin()
	var slice_active := 0
	var active_usec := 0
	var yielded := 0
	for identity in range(80,96):
		var identity_start := Time.get_ticks_usec()
		var identity_probe := TRANSIT_WORK.begin()
		PASSENGER_MODEL.prewarm_actor_identity(identity)
		var cost := Time.get_ticks_usec()-identity_start
		slice_active += cost
		active_usec += cost
		if identity_probe != 0: TRANSIT_WORK.finish("terminal.passenger.mesh_prewarm",identity_probe,{"identity":identity,"startup":not controller.session.ready_for_play})
		if Time.get_ticks_usec()-slice_start >= maxi(1,budget_usec):
			if slice_probe != 0: TRANSIT_WORK.finish("terminal.passenger.mesh_prewarm_slice",slice_probe,{"active_usec":slice_active,"last_identity":identity,"yielding":true,"budget_usec":budget_usec})
			yielded += 1
			await get_tree().process_frame
			slice_start = Time.get_ticks_usec()
			slice_probe = TRANSIT_WORK.begin()
			slice_active = 0
	if slice_probe != 0: TRANSIT_WORK.finish("terminal.passenger.mesh_prewarm_slice",slice_probe,{"active_usec":slice_active,"last_identity":95,"yielding":false,"budget_usec":budget_usec,"total_active_usec":active_usec,"yielded_frames":yielded})
	_passenger_meshes_prepared = true

func prepare_road() -> void:
	var graph: RefCounted = controller.traffic_routes
	# Same graph invalidation contract as DispatchRoadRouter._native_graph().
	var signature: Array = [graph.get_instance_id(),graph.vertices.size(),graph.edges.size()]
	if not graph.vertices.is_empty(): signature.append_array([graph.vertices[0],graph.vertices[-1]])
	if _road_prepared and _road_signature == signature: return
	var route_began := TRANSIT_WORK.begin()
	road = ROUTES.street(graph)
	_road_prepared = true
	_road_signature = signature
	if route_began != 0: TRANSIT_WORK.finish("terminal.route.prepare",route_began,{"valid":road!=null,"startup":not controller.session.ready_for_play})

func build() -> void:
	var stall_began := TRANSIT_WORK.begin()
	_stall_build()
	if stall_began != 0: TRANSIT_WORK.finish("terminal.build", stall_began, {"fleet":fleet.size(),"gates":gates.size(),"resident":resident})

func _stall_build() -> void:
	var route_began := TRANSIT_WORK.begin()
	prepare_road()
	if route_began != 0: TRANSIT_WORK.finish("terminal.route",route_began,{"valid":road!=null})
	for i in 2:
		var gate_began := TRANSIT_WORK.begin()
		var gate := GATE.new()
		gate.entering = i==0
		gate.position = ROUTES.point(360 if i==0 else 250,125)
		gate.position.y = 0
		add_child(gate)
		gates.append(gate)
		if gate_began != 0: TRANSIT_WORK.finish("terminal.gate.create_ready",gate_began,{"index":i})
	for i in 4:
		var coach_began := TRANSIT_WORK.begin()
		var coach := COACH.new()
		coach.platform = i
		coach.position = ROUTES.point(-141+100*i,-88)
		coach.timer = 1+i*11
		var ready_began := TRANSIT_WORK.begin()
		add_child(coach)
		if ready_began != 0: TRANSIT_WORK.finish("terminal.coach.add_child_ready",ready_began,{"platform":i})
		fleet.append(coach)
		if coach_began != 0: TRANSIT_WORK.finish("terminal.coach.create_ready",coach_began,{"platform":i})
		for seat in 4:
			var person_began := TRANSIT_WORK.begin()
			var person := ACTOR.new()
			person.identity = 80+i*4+seat
			person.controlled_automatically = true
			person.speed = 1.4
			person.position = wait_point(i,seat)
			person.set_meta("persistent_id","terminal_%d_%d" % [i,seat])
			add_child(person)
			var passenger := {"actor":person,"inside":seat<2,"phase":"waiting","seat":seat}
			coach.passengers.append(passenger)
			set_inside(passenger,seat<2)
			if person_began != 0: TRANSIT_WORK.finish("terminal.passenger.create_ready",person_began,{"platform":i,"seat":seat,"identity":person.identity,"inside":seat<2})
	resident = true

static func wait_point(bay: int, seat: int) -> Vector3:
	return ROUTES.point(-141+100*bay+66,[-142,-112,-72,-40][seat])

func set_inside(passenger: Dictionary, value: bool) -> void:
	passenger.inside = value
	var actor = passenger.actor
	actor.visible = not value
	actor.set_physics_process(not value)
	actor.process_mode = Node.PROCESS_MODE_DISABLED if value else Node.PROCESS_MODE_INHERIT
	actor.collision_layer = 0 if value else 2
	actor.collision_mask = 0 if value else 7
	actor.automatic_direction = Vector3.ZERO

func _physics_process(delta: float) -> void:
	var stall_began := TRANSIT_WORK.begin()
	_stall_physics_process(delta)
	TRANSIT_WORK.finish_slow("terminal.physics", stall_began, 1000, self)

func _stall_physics_process(delta: float) -> void:
	if controller == null or controller.session == null or not controller.session.ready_for_play: return
	_clock += delta
	if _clock >= .5:
		_clock = 0
		var focus: Vector3 = controller.world.player.global_position
		var enabled: bool = controller.state.region_id=="harbor" and controller.state.place_id.is_empty() and focus.distance_to(ROUTES.point(0,0)) < 100 and controller.urban_transit.instances.has("harbor_coach_terminal")
		if enabled and not is_instance_valid(guard_model):
			guard_model = controller.urban_transit.instances.harbor_coach_terminal.find_child("CoachTerminalModel",true,false)
		if enabled and not resident: build()
		if running != enabled:
			running = enabled
			visible = running
			if not running and is_instance_valid(guard_model):
				guard_authorizing = false
				guard_model.set_guard_authorization(false)
			for gate in gates: gate.body.collision_layer = 1 if running else 0
			for coach in fleet:
				coach.collision_layer = 4 if running else 0
				for p in coach.passengers:
					if running:
						set_inside(p,p.inside)
					else:
						suspend(p)
	if not running or not resident: return
	# Arrival's route-city coach remains independent. No terminal manoeuvre starts
	# during the scripted M00 disembark, so both flows cannot claim its crossing.
	if controller.session.arrival.active and controller.session.arrival.phase=="disembark": return
	for gate in gates: gate.tick(delta)
	var authorizing: bool = gates.any(func(gate): return gate.state in ["checking","opening","passing"])
	if authorizing != guard_authorizing and is_instance_valid(guard_model):
		guard_authorizing = authorizing
		guard_model.set_guard_authorization(authorizing)
	for coach in fleet: tick_coach(coach,delta)

func suspend(passenger: Dictionary) -> void:
	passenger.actor.process_mode = Node.PROCESS_MODE_DISABLED
	passenger.actor.collision_layer = 0
	passenger.actor.collision_mask = 0

func take_apron(coach: Node3D) -> bool:
	if not is_instance_valid(apron_owner): apron_owner = coach
	return apron_owner == coach

func route(coach: Node3D, phase: String) -> void:
	coach.state = phase
	coach.set_path(road if phase=="road" else ROUTES.apron(phase,coach.platform),phase=="reversing")
	if phase in ["departing","arriving"]: coach.gate_stop = gates[0 if phase=="arriving" else 1].stop_distance(coach,coach.path)

func tick_coach(coach: Node3D, delta: float) -> void:
	if coach.health <= 0: return
	for passenger in coach.passengers:
		var actor = passenger.actor
		if not passenger.inside and passenger.phase in ["waiting","done"] and actor.is_on_floor() and not actor.dead:
			actor.set_physics_process(false)
	if coach.state in ["parked","exchange","closing","gear_change","return_wait"] and not coach.is_on_floor():
		coach.velocity = Vector3(0,-2,0)
		coach.move_and_slide()
	match coach.state:
		"parked":
			coach.timer -= delta
			if coach.timer <= 0:
				coach.state = "exchange"
				for p in coach.passengers: p.phase = "alight" if p.inside else "board"
		"exchange":
			coach.set_doors(move_toward(coach.doors,1,delta))
			if coach.doors >= .99 and exchange(coach): coach.state = "closing"; coach.timer = 1.2
		"closing":
			coach.timer -= delta
			if coach.timer <= 0:
				coach.set_doors(move_toward(coach.doors,0,delta))
				if coach.doors <= 0 and road != null and take_apron(coach): route(coach,"reversing")
		"gear_change":
			coach.timer -= delta
			if coach.timer <= 0: route(coach,"departing")
		"return_wait":
			if take_apron(coach): route(coach,"arriving")
		_:
			var clearance := INF
			if coach.state in ["arriving","departing"]: clearance = gates[0 if coach.state=="arriving" else 1].clearance(coach)
			coach.drive(delta,clearance)
			if coach.arrived():
				match coach.state:
					"reversing": coach.state = "gear_change"; coach.timer = 1.1
					"departing": apron_owner = null; route(coach,"road")
					"road": coach.state = "return_wait"
					"arriving": apron_owner = null; coach.state = "parked"; coach.timer = 10; coach.trips += 1

func clear_person(point: Vector3, actor: CharacterBody3D) -> bool:
	var query := PhysicsShapeQueryParameters3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = .31; shape.height = 1.7
	query.shape = shape
	query.transform.origin = point+Vector3.UP*.86
	query.collision_mask = 7
	query.exclude = [actor.get_rid()]
	return get_world_3d().direct_space_state.intersect_shape(query,1).is_empty()

func exchange(coach: Node3D) -> bool:
	# One person uses the door at a time; alighters walk away before boarding starts.
	for p in coach.passengers:
		var actor = p.actor
		if actor.dead: p.phase = "done"; continue
		var door: Vector3 = coach.global_position+Vector3(1.4,.12,-2.18)
		if p.phase=="alight":
			if not clear_person(door,actor): return false
			actor.teleport(door)
			set_inside(p,false)
			p.phase = "walk_away"
			coach.alighted += 1
		if p.phase=="walk_away":
			if walk(actor,wait_point(coach.platform,p.seat)): p.phase = "done"
			return false
	for p in coach.passengers:
		if p.phase != "board": continue
		var door: Vector3 = coach.global_position+Vector3(1.4,.12,-2.18)
		if walk(p.actor,door):
			set_inside(p,true); p.phase = "done"; coach.boarded += 1
		return false
	return true

func walk(actor: CharacterBody3D, target: Vector3) -> bool:
	var offset := target-actor.global_position
	offset.y = 0
	if offset.length() < .16:
		actor.automatic_direction = Vector3.ZERO
		actor.set_physics_process(false)
		return true
	actor.set_physics_process(true)
	actor.automatic_direction = offset.normalized()
	return false
