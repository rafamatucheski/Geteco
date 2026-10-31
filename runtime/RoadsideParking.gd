extends Node
## Atividade esparsa na beira da rua: seis carros físicos, quatro pedestres e uma manobra.
## As decisões rodam a 1.5 Hz; corpos Vehicle estacionados usam o caminho de repouso existente.
const LAYOUT := preload("res://world/roadside_parking/RoadsideParkingLayout.gd")
const ACTOR := preload("res://scripts/Actor.gd")
const MANEUVER := preload("res://gameplay/roadside_parking/ParkingManeuver.gd")
const FLEET := preload("res://runtime/FleetCatalog.gd")
const MAX_CARS := 6
const MAX_PEOPLE := 4
const ACTIVE_RADIUS := 112.0
const RETIRE_RADIUS := 135.0
const CITY_MODELS := ["metro_hatch", "union_sedan", "sedan_classic", "station_wagon", "ranch_pickup", "ranch_single", "atlas_crew_pickup", "sertao_trail_pickup", "lumber_pickup_4x4", "besouro_1300", "mare_microvan", "toco_minitruck"]
const MOUNTAIN_MODELS := ["arctic_jeep", "desert_jeep_4x4", "summit_suv", "winter_suv_heavy"]
const SPECIAL_MODELS := ["muscle_classic", "sport_coupe", "aurora_executive"]
var world: Node3D
var controller: Node
var records: Array[Dictionary] = []
var known_regions: Dictionary = {}
var clock := 0.0
var seconds := 0.0
var random := RandomNumberGenerator.new()
var maneuver: RefCounted
var maneuver_record: Dictionary = {}
var enabled := true
var events: Array[Dictionary] = []
var _spawn_shapes: Dictionary = {}
var last_spawn_failure: Dictionary = {}

func configure(owner_world: Node3D, owner_controller: Node) -> void:
	world = owner_world
	controller = owner_controller
	name = "RoadsideParking"
	random.randomize()
	if "--benchmark" in OS.get_cmdline_user_args(): random.seed = 61006
	enabled = not "--no-roadside-parking" in OS.get_cmdline_user_args()
	set_physics_process(enabled)

static func profile(seed_value: int, mountain: bool) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var occupied := rng.randf() < .66
	var special := not mountain and rng.randf() < .075
	var pool: Array = MOUNTAIN_MODELS if mountain else (SPECIAL_MODELS if special else CITY_MODELS)
	return {"occupied":occupied, "model":pool[rng.randi_range(0, pool.size()-1)], "special":special,
		"occupants":2 if rng.randf() < .28 else 1, "returns":rng.randf() < .67, "reverse":rng.randf() < .45}

static func eligible_traffic(car: Variant) -> bool:
	if not is_instance_valid(car) or not car is CharacterBody3D or car.is_queued_for_deletion(): return false
	if not car.get_meta("ambient_traffic", false) or not car.traffic or car.controlled or car.health <= 0: return false
	if car.archetype not in CITY_MODELS + MOUNTAIN_MODELS + SPECIAL_MODELS: return false
	for key in ["roadside_parking", "gang_hostile", "race_owned", "garage_reward", "residence_vehicle", "mission_vehicle", "port_work_vehicle"]:
		if car.get_meta(key, false): return false
	if str(car.get_meta("traffic_yield_state", "")) != "" or car.has_meta("crash_stun"): return false
	return car._held_junction == null and car._clearing_junctions.is_empty()

const _SYS_SPAN := preload("res://runtime/StallWorkTrace.gd")
## Span do sistema inteiro (22/10): quadros de 30–60 ms com o tempo em _process sem nenhum span.
func _physics_process(delta: float) -> void:
	var span := _SYS_SPAN.begin()
	_physics_process_traced(delta)
	_SYS_SPAN.finish_slow("sys.roadside_parking.physics", span, 3000)

func _physics_process_traced(delta: float) -> void:
	if not enabled or not is_instance_valid(world) or controller.session == null: return
	var session = controller.session
	if not session.ready_for_play or session.has_position_transition() or not controller.state.place_id.is_empty(): return
	seconds += delta
	if maneuver != null:
		var result: int = maneuver.step(delta)
		if result != 0: _finish_maneuver(result > 0)
	clock += delta
	if clock < .65: return
	clock = 0
	_discover_regions()
	var admitted := false
	for record in records:
		var car = record.get("car")
		var nearby: bool = world.player.global_position.distance_to(record.slot.position) < ACTIVE_RADIUS
		if is_instance_valid(car) and not car.is_queued_for_deletion():
			if car == world.driving.car and world.driving.occupied:
				claim_vehicle(car)
				continue
			if car.health <= 0 or car.global_position.distance_to(record.slot.position) > 22 and record.phase != "departing":
				_release(record, false)
				continue
			if world.player.global_position.distance_to(car.global_position) > RETIRE_RADIUS and not controller._on_screen(car.global_position, 4):
				_release(record, true)
				continue
			_tick_visit(record)
		elif nearby and not admitted and seconds >= float(record.next_visit):
			if not record.initialized:
				if record.profile.occupied and controller._on_screen(record.slot.position, 4): continue
				if record.profile.occupied:
					admitted = _spawn_parked(record)
				else:
					record.initialized = true
					record.next_visit = seconds + random.randf_range(9, 18)
			elif maneuver == null and _car_count() < MAX_CARS:
				admitted = _try_arrival(record)
				record.next_visit = seconds + random.randf_range(4, 9)
		elif not nearby and record.initialized and not is_instance_valid(car) and world.player.global_position.distance_to(record.slot.position) > RETIRE_RADIUS:
			record.initialized = false
			record.profile = profile(random.randi(), record.site.region == "mountain")

func _discover_regions() -> void:
	for id in controller.regions:
		var region: Node = controller.regions[id]
		if not is_instance_valid(region) or known_regions.get(id) == region.get_instance_id(): continue
		known_regions[id] = region.get_instance_id()
		for site in LAYOUT.sites(region):
			for slot in site.slots:
				var found := false
				for previous in records:
					if previous.slot.id == slot.id: found = true; break
				if found: continue
				records.append({"site":site,"slot":slot,"profile":profile(random.randi(), id == "mountain"),
					"car":null,"actors":[],"phase":"empty","initialized":false,"next_visit":0.0,"due":0.0,"exit_count":0})

func _car_count() -> int:
	var count := 0
	for record in records:
		if is_instance_valid(record.get("car")) and not record.car.is_queued_for_deletion(): count += 1
	return count

func _people_count() -> int:
	var count := 0
	for record in records:
		for actor in record.actors:
			if is_instance_valid(actor) and not actor.is_queued_for_deletion(): count += 1
	return count

func _own(record: Dictionary, car: CharacterBody3D) -> void:
	record.car = car
	car.set_meta("roadside_parking", true)
	car.set_meta("parking_theft_handler", Callable(self, "claim_vehicle"))
	car.set_meta("region_id", record.site.region)
	car.set_meta("parking_slot_id", record.slot.id)
	car.remove_meta("ambient_traffic")
	car.player_damage_attribution = false

func _spawn_parked(record: Dictionary) -> bool:
	last_spawn_failure = {}
	if is_instance_valid(record.get("car")):
		last_spawn_failure = {"reason":"existing_record_car","car":str(record.car.name),"queued":record.car.is_queued_for_deletion()}
		return false
	if seconds < float(record.next_visit):
		last_spawn_failure = {"reason":"backoff","seconds":seconds,"next_visit":record.next_visit}
		return false
	var point: Vector3 = record.slot.position + Vector3.UP * .10
	if record.site.region == "mountain" and point.z < (-1350.0-4960.0)/16.0 and str(record.slot.id).ends_with("_0"):
		record.profile.model = "bike_snow"
	if _car_count() >= MAX_CARS:
		last_spawn_failure = {"reason":"population_cap","cars":_car_count()}
		_defer_spawn(record)
		return false
	if not _spawn_space_clear(record.profile.model, point, float(record.slot.yaw)):
		_defer_spawn(record)
		return false
	var car: CharacterBody3D = controller.spawn_vehicle(record.profile.model, point, float(record.slot.yaw))
	if car == null:
		# A checagem real do Vehicle continua oficial se streaming/física mudarem
		# depois da pré-checagem. Nunca monta um modelo repetidamente contra um espaço bloqueado.
		last_spawn_failure = {"reason":"controller_rejected","point":str(point),"model":record.profile.model}
		_defer_spawn(record)
		return false
	_own(record, car)
	record.initialized = true
	car.vehicle_id = "roadside_" + str(Time.get_ticks_usec())
	_event("spawn", record)
	_parked(record, random.randf() < .45)
	return true

func _defer_spawn(record: Dictionary) -> void:
	record.initialized = false
	record.next_visit = seconds + random.randf_range(5, 10)

func _spawn_space_clear(model: String, point: Vector3, yaw: float) -> bool:
	if not _spawn_shapes.has(model):
		var specification := FLEET.spec(model)
		if specification.is_empty():
			last_spawn_failure = {"reason":"unknown_model","model":model}
			return false
		var bounds: Array = specification.bounds_size
		var hull := BoxShape3D.new()
		# O envelope conservador inclui as variantes de Fleet suportadas (até 10%
		# mais largas/longas, 15% mais altas). Nenhum visual, pintura, porta ou Vehicle é alocado.
		hull.size = Vector3(maxf(.65,float(bounds[0])*1.10),clampf(float(bounds[1])*1.15,1.1,3.6),float(bounds[2])*1.10)
		_spawn_shapes[model] = hull
	var shape: BoxShape3D = _spawn_shapes[model]
	var basis := Basis(Vector3.UP, yaw)
	var space := world.get_world_3d().direct_space_state
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(basis,point+Vector3.UP*shape.size.y*.5)
	query.collision_mask = 7
	var overlap := space.intersect_shape(query,1)
	if not overlap.is_empty():
		var collider: Object = overlap[0].collider
		last_spawn_failure = {"reason":"overlap","point":str(point),"size":str(shape.size),"yaw":yaw,
			"collider":str(collider.get_path()) if collider is Node and collider.is_inside_tree() else str(collider),
			"class":collider.get_class(),"queued":collider.is_queued_for_deletion() if collider is Node else false}
		return false
	for x in [-shape.size.x*.4,shape.size.x*.4]:
		for z in [-shape.size.z*.4,shape.size.z*.4]:
			var support: Vector3 = point+basis*Vector3(x,0,z)
			var ray := PhysicsRayQueryParameters3D.create(support+Vector3.UP*.6,support-Vector3.UP*.5,1)
			if space.intersect_ray(ray).is_empty():
				last_spawn_failure = {"reason":"missing_support","point":str(point),"corner":str(support),"size":str(shape.size)}
				return false
	return true

func _try_arrival(record: Dictionary) -> bool:
	var forward: Vector3 = record.site.forward
	var target: Vector3 = record.slot.position
	for car in controller.vehicles:
		if not eligible_traffic(car): continue
		if record.site.region == "mountain" and car.archetype not in MOUNTAIN_MODELS: continue
		var difference: Vector3 = car.global_position - target
		var along := difference.dot(forward)
		if along < -14 or along > -7 or absf(difference.y) > 1.2: continue
		var side := difference - forward * along
		if side.length() > 7.5 or (-car.global_basis.z).dot(forward) < .94 or car.speed > 11: continue
		if not controller.vehicle_position_clear(car, target + Vector3.UP * .1, record.slot.yaw): continue
		_own(record, car)
		_event("arrival", record)
		record.original_route = car.route
		# A baliza de ré primeiro avança na mesma faixa e depois entra de ré na vaga.
		record.phase = "passing" if record.profile.reverse else "arriving"
		var destination := target + Vector3.UP * .10
		if record.profile.reverse: destination = car.global_position + forward * (8.0 - along)
		_start_maneuver(record, destination, false)
		return true
	return false

func _start_maneuver(record: Dictionary, destination: Vector3, reverse: bool) -> void:
	maneuver = MANEUVER.new()
	maneuver_record = record
	maneuver.begin(record.car, destination, record.site.forward, reverse, record.phase == "departing")

func _finish_maneuver(success: bool) -> void:
	var record := maneuver_record
	var diagnostic: Dictionary = maneuver.diagnostic() if not success else {}
	var previous_start: Vector3 = maneuver.start
	var previous_reverse: bool = maneuver.reverse
	maneuver = null
	maneuver_record = {}
	if not is_instance_valid(record.get("car")) or record.car.is_queued_for_deletion(): return
	if not success:
		_event("maneuver_blocked", record)
		events[-1].diagnostic = diagnostic
		if record.car.health <= 0 or record.car.has_meta("crash_stun"):
			_release(record, false)
		elif record.phase == "recovering":
			# Uma pessoa/veículo pode bloquear os dois sentidos. Espera visivelmente com colisão;
			# isto não é uma vaga estacionada e não pode ganhar trava de roubo de estacionado.
			record.phase = "stalled"
			record.due = seconds + 6
			record.car.remove_meta("ambient_parked")
			record.car.remove_meta("vehicle_locked")
		else:
			# Varre de volta ao início físico, mantendo colisão e prioridade de faixa.
			record.recovery_phase = record.phase
			record.recovery_target = previous_start
			record.recovery_reverse = not previous_reverse
			record.phase = "recovering"
			_start_maneuver(record, previous_start, not previous_reverse)
		return
	if record.phase == "passing":
		record.phase = "arriving"
		_start_maneuver(record, record.slot.position + Vector3.UP * .10, true)
	elif record.phase == "recovering":
		if record.recovery_phase == "departing": _parked(record, false)
		else: _resume_traffic(record)
	elif record.phase == "departing": _resume_traffic(record)
	else: _parked(record, true)

func _parked(record: Dictionary, visit: bool) -> void:
	var car = record.car
	car.traffic = false
	car.set_meta("ambient_parked", true)
	car.set_meta("vehicle_locked", not visit)
	car.remove_meta("ambient_traffic")
	_event("parked", record)
	record.phase = "exiting" if visit else "parked"
	record.due = seconds + 1.0
	record.exit_count = 0

func _tick_visit(record: Dictionary) -> void:
	var car = record.car
	if record.phase in ["arriving", "passing", "departing", "recovering", "parked"]: return
	if seconds < float(record.due): return
	if record.phase == "stalled":
		if maneuver == null:
			record.phase = "recovering"
			_start_maneuver(record, record.recovery_target, record.recovery_reverse)
	elif record.phase == "exiting":
		if not car.warm_doors(1800): return
		if int(record.exit_count) >= int(record.profile.occupants) or _people_count() >= MAX_PEOPLE:
			car.animate_driver_door(_door_side(record), false)
			car.set_meta("vehicle_locked", true)
			record.phase = "exploring"
			record.due = seconds + random.randf_range(22, 48)
			return
		if _exit_occupant(record): record.exit_count += 1
		else: record.exit_count = record.profile.occupants
		record.due = seconds + 1.6
	elif record.phase == "exploring":
		if not record.profile.returns:
			record.phase = "parked"
			return
		record.phase = "returning"
		record.return_timeout = seconds + 25
	elif record.phase == "returning":
		var remaining := 0
		for actor in record.actors:
			if not is_instance_valid(actor) or actor.is_queued_for_deletion() or actor.dead: continue
			var direction: Vector3 = _exit_point(record) - actor.global_position
			direction.y = 0
			if direction.length() < .8:
				car.animate_driver_door(_door_side(record), true)
				world.people.erase(actor)
				actor.queue_free()
			else:
				actor.controlled_automatically = true
				actor.automatic_direction = direction.normalized()
				remaining += 1
		if remaining == 0:
			car.animate_driver_door(_door_side(record), false)
			car.set_meta("vehicle_locked", true)
			record.phase = "leaving"
			record.due = seconds + 1.0
		elif seconds > float(record.return_timeout):
			for actor in record.actors:
				if is_instance_valid(actor) and not actor.is_queued_for_deletion(): actor.controlled_automatically = false
			record.phase = "parked"
	elif record.phase == "leaving" and maneuver == null:
		_depart(record)

func _door_side(record: Dictionary) -> int:
	return 1 if record.car.global_basis.x.dot(_outward(record)) > 0 else -1

func _outward(record: Dictionary) -> Vector3:
	return record.site.get("outward", record.site.forward.cross(Vector3.UP)).normalized()

func _exit_point(record: Dictionary) -> Vector3:
	return record.car.global_position + _outward(record) * (record.car.half_width + .75)

func _exit_occupant(record: Dictionary) -> bool:
	# Carros roubados soltam os donos na multidão comum. Esses atores continuam
	# andando visivelmente, mas ainda precisam consumir a cota de população compartilhada.
	if _people_count() >= MAX_PEOPLE or world.people.size() >= controller._population_cap() + MAX_PEOPLE: return false
	var point := _exit_point(record)
	var forward: Vector3 = record.site.forward
	if record.exit_count > 0: point -= forward * 1.4
	if not controller.session.position_clear(point + Vector3.UP * .08): return false
	var ray := PhysicsRayQueryParameters3D.create(point + Vector3.UP * .5, point - Vector3.UP * .65, 1)
	var ground: Dictionary = world.get_world_3d().direct_space_state.intersect_ray(ray)
	if ground.is_empty(): return false
	var actor := ACTOR.new()
	actor.identity = random.randi_range(0, 10000)
	actor.position = ground.position + Vector3.UP * .06
	actor.speed = random.randf_range(1.05, 1.5)
	actor.set_meta("region_id", record.site.region)
	actor.set_meta("roadside_visitor", true)
	# Anda pelo acostamento externo, não num laço de um metro ao lado da porta.
	# Vagas duplas mandam os visitantes para a outra ponta sem entrar numa vaga.
	var along: float = (record.slot.position - record.site.position).dot(forward)
	var walk_offset := -along if absf(along) > 1 else (2.0 if record.exit_count == 0 else -2.0)
	var explore: Vector3 = record.site.explore_position + forward * walk_offset
	actor.route = PackedVector3Array([point, explore])
	actor.waypoint = 1
	record.car.animate_driver_door(_door_side(record), true)
	record.car.set_meta("vehicle_locked", false)
	world.add_child(actor)
	world.people.append(actor)
	record.actors.append(actor)
	_event("occupant_exit", record)
	return true

func _departure_route(record: Dictionary) -> Curve3D:
	var route: Curve3D = record.get("original_route")
	if route == null:
		var lane_index := 0
		for road in controller.ambient_roads_cache:
			if str(road.id) == str(record.site.road_id):
				lane_index = maxi(0,int(road.get("lanes_per_direction",1))-1)
				break
		route = controller.ambient_traffic_routes.route_near(record.slot.lane_position,lane_index)
	if route == null:
		return null
	var destination: Vector3 = record.slot.lane_position + record.site.forward * 6.0
	var offset := route.get_closest_offset(destination)
	var at := route.sample_baked(offset, true)
	var ahead := route.sample_baked(minf(offset + 1, route.get_baked_length()), true) - at
	if ahead.normalized().dot(record.site.forward) < .85 or at.distance_to(destination) > 3:
		return null
	# A car waiting for a safe gap reuses its admitted route instead of rebuilding
	# a complete graph traversal every decision tick.
	record.original_route = route
	return route

static func blocks_departure(car: CharacterBody3D, other: CharacterBody3D, at: Vector3, direction: Vector3) -> bool:
	if other == car or not is_instance_valid(other) or other.is_queued_for_deletion(): return false
	var relative := other.global_position - at
	if absf(relative.y) > 2.0: return false
	var forward := direction.normalized()
	var lateral := absf(relative.dot(forward.cross(Vector3.UP)))
	# Um vizinho estacionado atrás da borda da calçada não é trânsito passando. Mantém
	# prioridade para qualquer corpo real ocupando o corredor de entrada, incluindo um
	# jogador/destroço parado; a manobra ainda varre todos os obstáculos físicos.
	if lateral > car.half_width + other.half_width + .45: return false
	var reach: float = maxf(17.0,absf(other.speed)*2.0) + other.half_length
	return absf(relative.dot(forward)) < reach

func _depart(record: Dictionary) -> void:
	var route := _departure_route(record)
	if route == null:
		record.phase = "parked"
		return
	var destination: Vector3 = record.slot.lane_position + record.site.forward * 6.0
	var offset := route.get_closest_offset(destination)
	var at := route.sample_baked(offset,true)
	var ahead := route.sample_baked(minf(offset+1,route.get_baked_length()),true)-at
	# A full lane gap gives through traffic priority before pulling out.
	for other in controller.vehicles:
		if is_instance_valid(other) and blocks_departure(record.car,other,at,ahead): return
	record.phase = "departing"
	_event("departure", record)
	record.car.set_meta("vehicle_locked", false)
	_start_maneuver(record, at + Vector3.UP * .08, false)

func _resume_traffic(record: Dictionary) -> void:
	var car = record.car
	car.route = record.get("original_route")
	if car.route == null:
		_parked(record, false)
		return
	car.route_distance = car.route.get_closest_offset(car.global_position)
	car.set_meta("ambient_traffic", true)
	car.traffic = true
	car.remove_meta("ambient_parked")
	car.remove_meta("vehicle_locked")
	_release(record, false)

func claim_vehicle(car: CharacterBody3D) -> void:
	for record in records:
		if record.get("car") == car:
			_event("claimed", record)
			_release(record, false)
			car.player_damage_attribution = true
			return

func _release(record: Dictionary, remove_car: bool) -> void:
	if maneuver_record == record and maneuver != null:
		maneuver.stop()
		maneuver = null
		maneuver_record = {}
	var car = record.get("car")
	if is_instance_valid(car):
		car.remove_meta("roadside_parking")
		car.remove_meta("parking_theft_handler")
		car.remove_meta("parking_slot_id")
		if remove_car and car != world.driving.car:
			controller.vehicles.erase(car)
			car.queue_free()
	for actor in record.actors:
		if not is_instance_valid(actor) or actor.is_queued_for_deletion(): continue
		actor.controlled_automatically = false
		if remove_car:
			world.people.erase(actor)
			actor.queue_free()
	record.actors = []
	record.car = null
	record.phase = "empty"
	record.next_visit = seconds + random.randf_range(35, 70)

func reset() -> void:
	for record in records: _release(record, true)
	records.clear()
	known_regions.clear()

func snapshot() -> Dictionary:
	var phases := {}
	for record in records:
		phases[record.phase] = int(phases.get(record.phase, 0)) + 1
	return {"sites":records.size(),"cars":_car_count(),"people":_people_count(),"maneuvers":1 if maneuver != null else 0,"phases":phases}

func debug_snapshot() -> Dictionary:
	var result := snapshot()
	result.last_spawn_failure = last_spawn_failure.duplicate()
	result.events = events.duplicate(true)
	result.slots = []
	for record in records:
		result.slots.append({"id":record.slot.id,"region":record.site.region,"phase":record.phase,"position":str(record.slot.position),
			"model":record.car.archetype if is_instance_valid(record.get("car")) else "","occupied":is_instance_valid(record.get("car"))})
	return result

func _event(kind: String, record: Dictionary) -> void:
	events.append({"event":kind,"slot":record.slot.id,"time":snappedf(seconds,.01)})
	if events.size() > 48: events.pop_front()

## Chamado enquanto a cortina de carregamento ainda está presente; nunca surge no jogo vivo.
func initialize_nearby() -> void:
	if not enabled: return
	_discover_regions()
	for record in records:
		if _car_count() >= MAX_CARS: break
		if record.initialized or world.player.global_position.distance_to(record.slot.position) > ACTIVE_RADIUS: continue
		if record.profile.occupied:
			if not _spawn_parked(record): continue
		record.initialized = true
