extends Node3D
## Logical service continues outside streaming; physical vehicles exist only nearby.
## This owner alone snapshots/retires the fleet, crew, vaults and cash receipts.
const SCHEDULE := preload("res://gameplay/armored/ArmoredSchedule.gd")
const TRUCK := preload("res://gameplay/armored/ArmoredTruck.gd")
const GUARD := preload("res://gameplay/armored/ArmoredGuard.gd")
const DRIVER := preload("res://gameplay/armored/ArmoredTrafficDriver.gd")
const APRON := preload("res://gameplay/armored/ArmoredBankApron.gd")
const PLACES := preload("res://world/places/PlaceCatalog.gd")
const CONNECTION := preload("res://world/regions/WorldConnection3D.gd")
const FORMATION := [24.0, 12.0, 36.0, 0.0]
const JUNCTIONS := preload("res://gameplay/traffic_junctions/TrafficJunctions.gd")
const ADMISSION_DISTANCE := 125.0
const RETIRE_DISTANCE := 185.0
var session
var data: Dictionary = {}
var security_level := 0
var profile: Dictionary = {}
var fleet: Array[CharacterBody3D] = []
var drivers: Array = []
var guards: Array = []
var routes: Dictionary = {}
var banks: Dictionary = {}
var minigame: CanvasLayer
var pending_truck := -1
var clock := 0.0
var escape_seconds := 0.0
var road: Curve3D
var last_event := ""
var _reported_point := Vector3.ZERO
var _route_retry := 0.0
var _admission_retry := 0.0
var _private_graph: RefCounted
var admission_status := "idle"
var admission_probe: Dictionary = {}
var _guard_phases: Array[String] = []

func configure(value) -> void:
	session = value
	name = "ArmoredTransport"
	var raw: Variant = session.state.world_state.get(SCHEDULE.KEY,{})
	var saved: Dictionary = raw if raw is Dictionary else {}
	last_event = str(saved.get("last_event", ""))
	security_level = clampi(int(saved.get("security_level",0)),0,6)
	data = SCHEDULE.restore(saved.get("event",{}))
	APRON.migrate_loading(data)
	if not data.is_empty():
		profile = SCHEDULE.security(int(data.security_level))
		_reported_point = _point(data.get("reported_point",[0,0,0]))
	for id in SCHEDULE.BANKS: banks[id] = PLACES.get_definition(id)

func _ready() -> void:
	minigame = preload("res://ui/ContainerLockpick.gd").new()
	add_child(minigame)
	minigame.resolved.connect(_resolve_lock)
	session.world.gameplay.weapon_fired.connect(_gunfire)
	session.world.gameplay.explosion_occurred.connect(_explosion)
	session.world.gameplay.player_died.connect(_failed)
	session.world.gameplay.player_arrested.connect(_failed)
	# Vehicles need their next floor admitted before their own physics callback.
	process_physics_priority = -10

func crew_operational() -> bool:
	return session.ready_for_play and not data.is_empty() and data.phase != "finished" and session.world.gameplay.health > 0 and not session.is_transition_blocked()

func available() -> bool:
	return crew_operational() and session.state.place_id.is_empty() and not session.modal and not session.world.player.input_locked and not session.world.driving.occupied

func _process(delta: float) -> void:
	if not session.ready_for_play: return
	if pending_truck >= 0 and not _lock_reachable(pending_truck): minigame.finish("cancelled")
	clock += delta
	if clock < .25: return
	var step := clock
	clock = 0.0
	if not session.state.campaign.snapshot().completed.has("cobra_finale"): return
	if session.is_transition_blocked(): return
	if data.is_empty() or data.phase == "finished":
		var event := SCHEDULE.departure(session.weather.moon_day(),session.weather.time_of_day)
		if event.is_empty() or event.id == last_event: return
		data = SCHEDULE.initial(event,security_level)
		profile = SCHEDULE.security(security_level)
		road = null
		last_event = event.id
		_persist()
	if road == null:
		_route_retry -= step
		if _route_retry > 0: return
		_route_retry = 5.0
		if not _prepare_route(): return
	for car in fleet:
		if not is_instance_valid(car) or car.is_queued_for_deletion():
			# A region jump can evict the owner region; recover the last safe snapshot.
			_release()
			return
	if not fleet.is_empty() and _out_of_sight(RETIRE_DISTANCE):
		_persist()
		_release()
	if fleet.is_empty():
		_admission_retry = maxf(0.0,_admission_retry-step)
		if _near_service():
			if _admission_retry <= 0:
				_admission_retry = 2.0
				_admit()
		else: _advance_virtual(step)
	data.elapsed += step
	if data.hostile:
		_tick_alarm(step)
		_update_crew()
		_tick_escape(step)
		if data.elapsed > 600.0 and data.pending == 0 and _out_of_sight(RETIRE_DISTANCE): _finish()
	elif not fleet.is_empty():
		_update_crew()
		_tick_service()
	_persist()

func _prepare_route() -> bool:
	var route_key: String = data.origin+str(data.get("service_layout",0))
	if routes.has(route_key):
		road = routes[route_key]
		return true
	var snapshot: Dictionary = session.controller._route_cache.get("harbor,desert",{})
	if snapshot.is_empty():
		admission_status = "route_cache_missing"
		return false
	if _private_graph == null:
		_private_graph = preload("res://gameplay/NativeTrafficRoutes.gd").new()
		var roads: Array = []
		# The north bridge is authored player access, deliberately absent from
		# ordinary traffic. Add it only to this scheduled service's private graph.
		var bridge := preload("res://world/north_gateway/NorthGatewayLayout.gd").centerline()
		var projection := Vector3.INF
		var projection_gap := 4.0
		for segment in snapshot.traffic[0]:
			roads.append({"id":segment.id,"width":segment.width,"lanes_per_direction":segment.get("lanes",1),"points":PackedVector3Array([segment.a,segment.b])})
			if segment.id != "map2_highway_inbound": continue
			var point := Geometry3D.get_closest_point_to_segment(bridge[0],segment.a,segment.b)
			if point.distance_to(bridge[0]) < projection_gap:
				projection = point
				projection_gap = point.distance_to(bridge[0])
		if not projection.is_finite():
			_private_graph = null
			return false
		bridge.insert(0,projection)
		roads.append({"id":"armored_private_north_bridge","width":6.4,"points":bridge})
		_private_graph.configure(roads)
	var graph: RefCounted = _private_graph
	var router := preload("res://gameplay/dispatch/DispatchRoadRouter.gd").new()
	router.configure(graph)
	var origin: Vector3 = banks[data.origin].entry_position
	var destination: Vector3 = banks[data.destination].entry_position
	if data.destination == "desert_bank":
		var closest_gap := INF
		for from in graph.edges:
			for candidate in graph.edges[from]:
				if candidate.id != "desert_main_street": continue
				var direction: Vector3 = (graph.vertices[candidate.to]-graph.vertices[candidate.from]).normalized()
				if direction.dot(Vector3.LEFT) < .9: continue
				var shift: Vector3 = graph._lane_offset(direction,candidate)
				var point := Geometry3D.get_closest_point_to_segment(banks[data.destination].entry_position,graph.vertices[candidate.from]+shift,graph.vertices[candidate.to]+shift)
				var gap := point.distance_squared_to(banks[data.destination].entry_position)
				if gap < closest_gap:
					closest_gap = gap
					destination = point
	# Starting on the nearest lane can point away from the destination and
	# make Dijkstra insert a 180-degree return immediately across a frontage.
	# Cobre departs eastbound; the new North Pier bays join southbound Westgate.
	var edge: Dictionary = router.nearest_edge(origin,false,Vector3.RIGHT)
	if data.origin == "harbor_bank" and int(data.get("service_layout",0)) == 1:
		edge = router.nearest_edge(APRON.MERGE,false,Vector3.BACK)
	if data.origin == "desert_bank":
		# Cobre has a 27 m dead-end spur: a 36 m four-car convoy cannot turn
		# around there. Stage eastbound on its existing main-street frontage.
		edge = {}
		for candidate in router.spawn_candidates(origin,20.0,65.0,4.0):
			if candidate.edge.id != "desert_main_street": continue
			var direction: Vector3 = (graph.vertices[candidate.edge.to]-graph.vertices[candidate.edge.from]).normalized()
			if direction.dot(Vector3.RIGHT) < .9: continue
			edge = {"edge":candidate.edge,"closest":candidate.point}
			break
	if edge.is_empty():
		admission_status = "origin_lane_missing"
		return false
	var heading: Vector3 = (graph.vertices[edge.edge.to]-graph.vertices[edge.edge.from]).normalized()
	# Start the formation upstream of the bank, on the actual directed lane.
	var desired_start: Vector3 = edge.closest-heading*30.0
	# The upstream point may belong to a preceding segment of the SAME street
	# (Cobre's long main road), but never project onto a perpendicular street.
	var staging_edge: Dictionary = edge.edge
	var staging_gap := INF
	for from in graph.edges:
		for candidate in graph.edges[from]:
			if candidate.id != edge.edge.id: continue
			var direction: Vector3 = (graph.vertices[candidate.to]-graph.vertices[candidate.from]).normalized()
			if direction.dot(heading) < .98: continue
			var shift: Vector3 = graph._lane_offset(direction,candidate)
			var projected := Geometry3D.get_closest_point_to_segment(desired_start,graph.vertices[candidate.from]+shift,graph.vertices[candidate.to]+shift)
			if projected.distance_squared_to(desired_start) < staging_gap:
				staging_gap = projected.distance_squared_to(desired_start)
				staging_edge = candidate
	var lane: Vector3 = graph._lane_offset(heading,staging_edge)
	var lane_start: Vector3 = graph.vertices[staging_edge.from]+lane
	var lane_end: Vector3 = graph.vertices[staging_edge.to]+lane
	var start := Geometry3D.get_closest_point_to_segment(desired_start,lane_start,lane_end)
	var corner_margin := minf(float(staging_edge.width)*.5+3.0,lane_start.distance_to(lane_end)*.25)
	if start.distance_to(lane_start) < corner_margin: start = lane_start+heading*corner_margin
	var plan: Dictionary = router.plan(start,destination,heading)
	admission_probe = {"origin":origin,"start":start,"heading":heading,"start_edge":staging_edge.id,"route_reason":plan.get("reason",""),"end_gap":plan.get("end_gap",INF),"length":plan.get("length",0.0)}
	if not plan.get("ok",false) or plan.end_gap > 35 or plan.length < 80:
		admission_status = "route_rejected"
		return false
	admission_status = "route_ready"
	road = plan.curve
	var lane_sections: Array = []
	for index in range(plan.nodes.size()-1):
		var segment: Dictionary = graph._edge(plan.nodes[index],plan.nodes[index+1])
		lane_sections.append({"a":graph.vertices[segment.from],"b":graph.vertices[segment.to],"lanes":segment.get("lanes",1),"width":segment.width})
	road.set_meta("lane_sections",lane_sections)
	road.set_meta("lane_index",0)
	routes[route_key] = road
	return true

func _virtual_offset(index: int) -> float:
	return clampf(float(data.route_offset)+FORMATION[index],0.0,road.get_baked_length()-(36.0-FORMATION[index]))

func _virtual_point(index: int) -> Vector3:
	if _loading_apron(): return APRON.SLOTS[index]
	if _unloading_apron(): return APRON.arrival_slot(index)
	return road.sample_baked(_virtual_offset(index),true)+Vector3.UP*.08

func _loading_apron() -> bool:
	return data.get("origin","") == "harbor_bank" and data.get("phase","") in ["loading","boarding"]

func _unloading_apron() -> bool:
	return data.get("destination","") == "harbor_bank" and data.get("phase","") == "unloading"

func _route_heading(offset: float) -> Vector3:
	return road.sample_baked(minf(offset+1.0,road.get_baked_length()),true)-road.sample_baked(maxf(0.0,offset-1.0),true)

func _near_service() -> bool:
	if not session.state.place_id.is_empty(): return false
	for index in 4:
		var point := _point(data.vehicles[index].point) if data.vehicles.size() == 4 else _virtual_point(index)
		if session.world.player.global_position.distance_to(point) <= ADMISSION_DISTANCE: return true
	return false

func _advance_virtual(step: float) -> void:
	if data.hostile: return
	# Retirement preserves casualties too: a wreck or missing carrier cannot be
	# replaced with a healthy crew simply because the player left the area.
	for vehicle_record in data.vehicles:
		if float(vehicle_record.health) <= 0.0:
			data.phase = "finished"
			return
	if data.phase in ["loading","unloading"]:
		for index in mini(2,data.guards.size()):
			if float(data.guards[index].health) <= 0.0 and int(data.cargo_cycles[index]) < 2:
				data.phase = "finished"
				return
	if data.phase == "departing":
		data.phase = "finished"
		return
	if data.phase in ["loading","unloading"] and data.elapsed >= 65.0:
		data.cargo_cycles = [2,2]
		if data.phase == "unloading": data.delivered = [true,true]
		data.phase = "boarding" if data.phase == "loading" else "finished"
		data.elapsed = 0.0
	elif data.phase == "boarding" and data.elapsed >= 8.0:
		data.phase = "driving"
		data.elapsed = 0.0
		for guard_record in data.guards: guard_record.phase = "board"
	elif data.phase == "driving":
		data.virtual_poses = true
		data.route_offset = minf(road.get_baked_length()-36.0,float(data.route_offset)+step*float(profile.cruise_speed))
		# Advance only the off-screen poses, retaining each vehicle's actual damage.
		for index in data.vehicles.size():
			var offset := _virtual_offset(index)
			var point := _virtual_point(index)
			var tangent := _route_heading(offset)
			data.vehicles[index].point = [point.x,point.y,point.z]
			data.vehicles[index].yaw = atan2(-tangent.x,-tangent.z)
		for guard_record in data.guards: guard_record.phase = "board"
		if data.route_offset >= road.get_baked_length()-36.0:
			data.phase = "unloading"
			data.cargo_cycles = [0,0]
			data.elapsed = 0.0
			APRON.migrate_loading(data)

func _ground_at(point: Vector3) -> bool:
	var region: Node3D = session.controller.regions.get(CONNECTION.logical_region(point))
	return is_instance_valid(region) and region.has_method("prepare_collision_at") and region.prepare_collision_at(point)

func _admit() -> void:
	# A persistent or player car may occupy the bank lane. Before creating any
	# bodies, try a short downstream staging shift on the SAME authored route.
	# Saved physical fleets retain their poses; nothing already visible is moved.
	var initial_offset := float(data.route_offset)
	if data.vehicles.is_empty() and initial_offset < 25.0 and not _loading_apron():
		var found := false
		for shift in [0.0,6.0,12.0,18.0,24.0]:
			data.route_offset = initial_offset+shift
			if float(data.route_offset) > 24.0: break
			var clear := true
			for index in 4:
				var offset := _virtual_offset(index)
				var tangent := _route_heading(offset)
				if not _spawn_space_clear(_virtual_point(index),atan2(-tangent.x,-tangent.z),index < 2):
					clear = false
					break
			if clear:
				found = true
				break
		if not found:
			data.route_offset = initial_offset
			return
	var poses: Array[Dictionary] = []
	for index in 4:
		var point := _virtual_point(index)
		var tangent := _route_heading(_virtual_offset(index))
		var yaw := atan2(-tangent.x,-tangent.z)
		if _loading_apron(): yaw = PI
		if _unloading_apron(): yaw = 0.0
		if data.vehicles.size() == 4:
			point = _point(data.vehicles[index].point)
			yaw = float(data.vehicles[index].yaw)
		if bool(data.get("virtual_poses",data.vehicles.is_empty())):
			point = _supported_virtual_point(point,yaw,index < 2)
			if not point.is_finite():
				admission_probe["slot"] = index
				return
		if not _spawn_space_clear(point,yaw,index < 2):
			admission_probe["slot"] = index
			return
		poses.append({"point":point,"yaw":yaw})
	# Stage all four with physics disabled. A failed admission publishes none.
	var staged: Array[CharacterBody3D] = []
	for index in 4:
		var point: Vector3 = poses[index].point
		var yaw: float = poses[index].yaw
		var car: CharacterBody3D = TRUCK.new() if index < 2 else preload("res://gameplay/dispatch/DispatchVehicle.gd").new()
		if index >= 2:
			car.archetype = "winter_suv_heavy"
			car.paint_color = Color("293b35")
		car.vehicle_id = "armored_%s_%d" % [data.id,index]
		car.position = point
		car.rotation.y = yaw
		car.set_meta("armored_transport",true)
		car.set_meta("local_security",true)
		car.set_meta("region_id",CONNECTION.logical_region(point))
		car.set_meta("gang_damage_handler",Callable(self,"provoke"))
		car.hide()
		session.world.add_child(car)
		car.set_physics_process(false)
		car.remove_from_group("drivable")
		staged.append(car)
		if not session.controller.vehicle_position_clear(car,point,yaw):
			admission_status = "actual_hull_blocked"
			admission_probe = {"point":point,"yaw":yaw,"slot":index}
			for discard in staged: discard.queue_free()
			return
		if index < 2: car.max_health = float(profile.armor_health)
		car.health = float(data.vehicles[index].health) if data.vehicles.size() == 4 else car.max_health
	admission_status = "admitted"
	fleet.assign(staged)
	for index in fleet.size():
		var car = fleet[index]
		session.controller.vehicles.append(car)
		var driver := DRIVER.new()
		driver.setup(car,float(profile.cruise_speed),4.0)
		driver.disable_overtaking()
		driver.set_route(_individual_route(index))
		drivers.append(driver)
		car.set_physics_process(true)
		car.show()
		car.restore_health(car.health)
		if data.vehicles.size()==4: car.restore_body_dents(data.vehicles[index].get("body_dents",[]),data.vehicles[index].get("breakaway_parts",{}))
		if data.vehicles.size()==4: car.restore_blood_stains(int(data.vehicles[index].get("blood_stains",0)))
		if index < 2: car.set_vault(_vault_accessible(index),data.taken[index] or data.delivered[index])
	_update_crew()

func _supported_virtual_point(point: Vector3,yaw: float,armored: bool) -> Vector3:
	# Logical route heights interpolate authored vertices; the rendered desert
	# descent has its own smooth support profile. Resolve the upright footprint
	# before publishing new bodies, never relocate a visible or saved physical car.
	if not point.is_finite() or not _ground_at(point):
		admission_status = "virtual_ground_not_ready"
		return Vector3.INF
	var specification: Dictionary = preload("res://runtime/FleetCatalog.gd").spec("armored_truck" if armored else "winter_suv_heavy")
	var dimensions: Array = specification.bounds_size
	var scale_factor := 1.0 if armored else 1.08
	var width := float(dimensions[0])*scale_factor*.5
	var length := float(dimensions[2])*scale_factor*.5
	var footprint_basis := Basis(Vector3.UP,yaw)
	var space := get_world_3d().direct_space_state
	var highest := -INF
	var lowest := INF
	var authored_floor := true
	for across in [-1.0,0.0,1.0]:
		for along in [-1.0,-.5,0.0,.5,1.0]:
			var sample: Vector3 = point+footprint_basis*Vector3(across*width,0,along*length)
			var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(sample+Vector3.UP*.8,sample-Vector3.UP*.8,1))
			if hit.is_empty() or hit.normal.y < .7:
				admission_status = "virtual_footprint_without_floor"
				return Vector3.INF
			var body: Node = hit.collider
			authored_floor = authored_floor and (body.has_meta("vehicle_surface") or body.has_meta("vehicle_ramp_structure"))
			highest = maxf(highest,hit.position.y)
			lowest = minf(lowest,hit.position.y)
	# Unknown props cannot be promoted to a road merely by casting onto their top.
	# Preserve existing admission on untagged city/bridge surfaces instead.
	if not authored_floor: return point
	var corrected := Vector3(point.x,highest+.04,point.z)
	if absf(corrected.y-point.y) > .6 or highest-lowest > .5:
		admission_status = "virtual_support_out_of_range"
		return Vector3.INF
	return corrected

func _spawn_space_clear(point: Vector3, yaw: float, armored: bool) -> bool:
	admission_probe = {"point":point,"yaw":yaw}
	if not point.is_finite() or not _ground_at(point):
		admission_status = "region_ground_not_ready"
		return false
	var staging_basis := Basis(Vector3.UP,yaw)
	var width := 1.25 if armored else 1.15
	var length := 3.0 if armored else 2.8
	var space := get_world_3d().direct_space_state
	for x in [-width*.8,width*.8]:
		for z in [-length*.8,length*.8]:
			var corner: Vector3 = point+staging_basis*Vector3(x,0,z)
			if space.intersect_ray(PhysicsRayQueryParameters3D.create(corner+Vector3.UP*.6,corner-Vector3.UP*.5,1)).is_empty():
				admission_status = "corner_without_floor"
				admission_probe["corner"] = corner
				return false
	var shape := BoxShape3D.new()
	shape.size = Vector3(width*2,1.8,length*2)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(staging_basis,point+Vector3.UP*1.1)
	query.collision_mask = 7
	var hits := space.intersect_shape(query,4)
	if not hits.is_empty():
		admission_status = "staging_obstructed"
		var obstacles: Array = []
		for hit in hits:
			var body = hit.collider
			var record := {"path":str(body.get_path()),"class":body.get_class(),"point":body.global_position,"script":body.get_script().resource_path if body.get_script() != null else "","player":body == session.world.player}
			if "vehicle_id" in body: record["vehicle_id"] = body.vehicle_id
			obstacles.append(record)
		admission_probe["colliders"] = obstacles
	return hits.is_empty()

func _individual_route(index: int) -> Curve3D:
	var result := Curve3D.new()
	result.bake_interval = .5
	var start := 0.0
	if data.origin == "harbor_bank" and APRON.contains(fleet[index].global_position):
		for point in APRON.departure(index): result.add_point(point)
		start = road.get_closest_offset(APRON.MERGE)+2.0
		result.set_meta("formation_origin",start-result.get_baked_length())
	var finish: float = road.get_baked_length()-(36.0-float(FORMATION[index]))
	if data.destination == "harbor_bank" and int(data.get("service_layout",0)) == 1: finish = road.get_baked_length()
	for offset in range(int(start),int(finish),2): result.add_point(road.sample_baked(float(offset),true))
	result.add_point(road.sample_baked(finish,true))
	if data.destination == "harbor_bank" and int(data.get("service_layout",0)) == 1:
		for point in APRON.arrival(index): result.add_point(point)
	result.set_meta("traffic_open",true)
	result.set_meta("traffic_endpoint",result.get_point_position(result.point_count-1))
	result.set_meta("lane_sections",road.get_meta("lane_sections",[]))
	result.set_meta("lane_index",road.get_meta("lane_index",0))
	return result

func _physics_process(delta: float) -> void:
	if session == null or data.is_empty(): return
	var operational := crew_operational()
	var leaving_apron: bool = data.origin == "harbor_bank" and fleet.any(func(car): return is_instance_valid(car) and car.global_position.x < 35.0 and car.global_position.z < 42.0)
	for index in drivers.size():
		var driver = drivers[index]
		var car: CharacterBody3D = driver.vehicle
		if not is_instance_valid(car): continue
		var ahead: Vector3 = car.global_position-car.global_basis.z*(car.half_length+3)
		var ground_ready := _ground_at(car.global_position) and _ground_at(ahead)
		car.set_meta("region_id",CONNECTION.logical_region(car.global_position))
		if is_instance_valid(car.damage_look):
			if ground_ready: car.damage_look.resume_from_dispatch()
			else: car.damage_look.suspend_for_dispatch()
		if car.health <= 0: continue
		car.set_physics_process(ground_ready)
		if not ground_ready: continue
		driver.holding = not operational or data.phase != "driving" or data.hostile
		if not driver.holding and data.origin == "harbor_bank" and APRON.contains(car.global_position):
			var order := APRON.DEPARTURE_ORDER.find(index)
			if order > 0:
				var preceding = fleet[APRON.DEPARTURE_ORDER[order-1]]
				driver.holding = preceding.global_position.z < 42.0
		var successor := _formation_follower(index)
		var waiting_for_crew := false
		var parking_arrival: bool = data.destination == "harbor_bank" and int(data.get("service_layout",0)) == 1 and driver.remaining < 100.0
		if not driver.holding and not leaving_apron and not parking_arrival and successor >= 0 and successor < drivers.size():
			var gap: float = _formation_progress(index)-_formation_progress(successor)
			waiting_for_crew = gap > 26.0 and not _occupies_crossing(car) and not driver.pending_recovery()
			if waiting_for_crew: driver.holding = true
		car.set_meta("armored_formation_wait",waiting_for_crew)
		# Vehicle's street controller owns signals, obstacles and steering. This
		# service only supplies the route and formation hold, never a body pose.
		driver.tick(delta)

func _formation_follower(index: int) -> int:
	# A lawful bypass can change the order. Keep the nearest real neighbour behind
	# together with the convoy, including an escort that has passed the lead car.
	var follower := -1
	var progress: float = _formation_progress(index)
	for candidate in drivers.size():
		if candidate == index: continue
		var at: float = _formation_progress(candidate)
		if at > progress or (is_equal_approx(at,progress) and candidate > index): continue
		if follower < 0 or at > _formation_progress(follower) or (is_equal_approx(at,_formation_progress(follower)) and candidate > follower):
			follower = candidate
	return follower

func _formation_progress(index: int) -> float:
	# Bay connectors have different lengths. Compare positions on the common
	# road, never unrelated offsets on four independent driveway curves.
	var route: Curve3D = drivers[index].route
	return float(drivers[index].offset)+(float(route.get_meta("formation_origin",0.0)) if route != null else 0.0)

func _occupies_crossing(car: CharacterBody3D) -> bool:
	if car._held_junction != null and JUNCTIONS.occupies(car._held_junction,car.get_instance_id()): return true
	for key in car._clearing_junctions:
		if JUNCTIONS.occupies(key,car.get_instance_id()): return true
	if car.route == null: return false
	var progress: float = car.route.get_closest_offset(car.global_position)
	for junction in car._junction_list:
		var beyond: float = progress-float(junction.offset)
		if beyond < 0.0: continue
		var center: Vector3 = JUNCTIONS.junctions.get(junction.key,Vector3.INF)
		if not center.is_finite() or absf(car.route.sample_baked(float(junction.offset),true).y-center.y) > .75: continue
		var radius: float = JUNCTIONS.EXIT
		for approach in JUNCTIONS._approaches.get(junction.key,[]): radius = maxf(radius,float(approach.width)*.5)
		if beyond > radius+car.half_length+24.0: continue
		# Leave enough exit space for a following vehicle to clear its own lease.
		# Stopping only our hull outside EXIT can trap that vehicle in the crossing,
		# which in turn prevents the rear escort from joining us on the other arm.
		var following_length := 6.0
		for id in JUNCTIONS.owners.get(junction.key,{}):
			var occupant = instance_from_id(int(id))
			if is_instance_valid(occupant) and occupant != car and "half_length" in occupant and absf(occupant.global_position.y-center.y) < JUNCTIONS.OCCUPANCY_HEIGHT:
				following_length = maxf(following_length,float(occupant.half_length)*2.0)
		var clear_exit: float = radius+car.half_length+following_length+2.2+.75
		if beyond < clear_exit: return true
	return false

func _seat(index: int) -> int:
	return index if index < 2 else 2+(index%2)

func _crew_point(index: int) -> Vector3:
	var car = fleet[_seat(index)]
	if index < 2:
		if APRON.contains(car.global_position): return Vector3(32.25,car.global_position.y+.08,car.global_position.z-.5)
		return car.to_global(Vector3((-1 if index == 0 else 1)*(car.half_width+1.05),.08,.5))
	var local_rank := floori(float(index-2)/2.0)
	if APRON.contains(car.global_position):
		# The west side borders the neighbouring house. Keep every escort in
		# the open aisle instead of retrying an impossible spawn inside its wall.
		return Vector3(car.global_position.x+car.half_width+1.05,car.global_position.y+.08,car.global_position.z+[-.7,1.2,-2.2,2.7][local_rank])
	var side := -1.0 if local_rank%2 == 0 else 1.0
	var longitudinal := .7 if local_rank < 2 else -1.2
	return car.to_global(Vector3(side*(car.half_width+1.05),.08,longitudinal))

func _update_crew() -> void:
	if fleet.is_empty(): return
	for index in mini(2,fleet.size()):
		fleet[index].set_vault(_vault_accessible(index),data.taken[index] or data.delivered[index])
	if data.phase == "driving" and not data.hostile: return
	while guards.size() < int(profile.crew_count):
		guards.append(null)
		_guard_phases.append(("car" if data.phase == "unloading" else "bank") if guards.size() <= 2 else "post")
	for index in guards.size():
		var car = fleet[_seat(index)]
		if not is_instance_valid(car) or absf(car.speed) > .6: continue
		var guard = guards[index]
		if not is_instance_valid(guard):
			var saved: Dictionary = data.guards[index] if index < data.guards.size() else {}
			if float(saved.get("health",profile.guard_health)) <= 0: continue
			var point := _point(saved.point) if saved.has("point") and saved.get("phase","") != "board" else _crew_point(index)
			if not session.position_clear(point): continue
			guard = GUARD.new()
			guard.convoy = self
			guard.slot = index
			guard.tier = int(data.security_level)
			guard.position = point
			guard.configure_security(profile)
			guard.health = float(saved.get("health",profile.guard_health))
			guard.patrol_target = _crew_point(index)
			add_child(guard)
			_guard_phases[index] = str(saved.get("phase",_guard_phases[index]))
			if _guard_phases[index] == "board" and data.phase in ["loading","unloading"]:
				_guard_phases[index] = ("car" if data.phase == "unloading" else "bank") if index < 2 else "post"
			guards[index] = guard
		if guard.dead: continue
		if data.hostile:
			guard.cargo_carrying = false
			continue
		var bank_id: String = data.destination if data.phase == "unloading" else data.origin
		var bank: Vector3 = banks[bank_id].entry_position
		if data.phase == "boarding":
			_guard_phases[index] = "board"
			guard.cargo_carrying = false
			guard.patrol_target = _crew_point(index)
		elif index < 2 and int(data.cargo_cycles[index]) < 2:
			var to_bank: bool = _guard_phases[index] == "bank"
			guard.patrol_target = bank+Vector3(float(index)*1.0-.5,.08,1.0) if to_bank else fleet[index].door_point()
			guard.cargo_carrying = (not to_bank) if data.phase == "loading" else to_bank
			if guard.reached_target(.7):
				if (not to_bank and data.phase == "loading") or (to_bank and data.phase == "unloading"):
					data.cargo_cycles[index] += 1
					if data.phase == "unloading" and int(data.cargo_cycles[index]) >= 2 and not data.taken[index]: data.delivered[index] = true
				_guard_phases[index] = "car" if to_bank else "bank"
		else:
			guard.cargo_carrying = false
			guard.patrol_target = _crew_point(index)

func _tick_service() -> void:
	# Non-player destruction cannot make a delivery succeed off-screen.
	for car in fleet:
		if car.health <= 0:
			data.phase = "departing"
			if _out_of_sight(RETIRE_DISTANCE): _finish()
			return
	if data.phase in ["loading","unloading"]:
		for index in mini(2,guards.size()):
			if ((is_instance_valid(guards[index]) and guards[index].dead) or (index < data.guards.size() and float(data.guards[index].health) <= 0)) and int(data.cargo_cycles[index]) < 2:
				data.phase = "departing"
				return
		if int(data.cargo_cycles[0]) < 2 or int(data.cargo_cycles[1]) < 2: return
		if data.elapsed < 35.0: return
		if data.phase == "unloading":
			# Remain at the bank until the player leaves; no visible disappearing convoy.
			if _out_of_sight(95.0): _finish()
		else:
			data.phase = "boarding"
			data.elapsed = 0.0
	elif data.phase == "boarding":
		if guards.size() < int(profile.crew_count): return
		for index in guards.size():
			var guard = guards[index]
			if not is_instance_valid(guard):
				if index < data.guards.size() and float(data.guards[index].health) <= 0: continue
				return
			if not guard.dead and not guard.reached_target(.8): return
		_persist()
		_board()
		data.phase = "driving"
		data.elapsed = 0.0
	elif data.phase == "driving":
		var arrived := true
		var offset := INF
		for index in drivers.size():
			var driver = drivers[index]
			offset = minf(offset,road.get_closest_offset(driver.vehicle.global_position)-FORMATION[index])
			if not driver.at_route_end(): arrived = false
		data.route_offset = maxf(0.0,offset)
		if arrived:
			data.phase = "unloading"
			data.elapsed = 0.0
			data.cargo_cycles = [0,0]

func _board() -> void:
	for guard in guards:
		if is_instance_valid(guard): guard.queue_free()
	guards.clear()
	_guard_phases.clear()

func _player_source(source: Node) -> bool:
	return is_instance_valid(source) and (source == session.world.player or (source.has_method("is_player_damage_source") and source.is_player_damage_source()))

func provoke(source: Node) -> void:
	if data.is_empty() or data.hostile or not crew_operational(): return
	if not _player_source(source): return
	data.hostile = true
	data.elapsed = 0.0
	_reported_point = session.world.gameplay.pursuit_target().global_position
	data.reported_point = [_reported_point.x,_reported_point.y,_reported_point.z]
	var urban := _reported_point.distance_to(banks.harbor_bank.entry_position) < 320.0 or _reported_point.distance_to(banks.desert_bank.entry_position) < 120.0
	data.report_remaining = float(profile.city_report_delay if urban else profile.road_report_delay)
	if not data.escalated:
		data.escalated = true
		security_level = mini(6,security_level+1)
	session.show_message("Escolta em alerta! Reforços a caminho.")
	_update_crew()
	_tick_alarm(0.0)
	_persist()

func _tick_alarm(step: float) -> void:
	if data.reported or data.report_remaining < 0: return
	data.report_remaining = maxf(0.0,float(data.report_remaining)-step)
	if data.report_remaining <= 0:
		data.reported = true
		session.world.gameplay.register_crime(90+int(data.security_level)*8,_reported_point,"alarm",{"exterior":_reported_point})

func _gunfire(_weapon: String, origin: Vector3) -> void:
	if not session.state.place_id.is_empty() or not session.state.weapons_allowed() or _weapon in ["fists","knife","axe","bat"]: return
	for car in fleet:
		if is_instance_valid(car) and car.global_position.distance_to(origin) < 35:
			var ray := PhysicsRayQueryParameters3D.create(origin+Vector3.UP,car.global_position+Vector3.UP,1)
			if not get_world_3d().direct_space_state.intersect_ray(ray).is_empty(): continue
			provoke(session.world.player)
			return

func _explosion(origin: Vector3, radius: float, source: Node) -> void:
	if data.is_empty() or not session.state.place_id.is_empty(): return
	if not _player_source(source): return
	for index in mini(2,fleet.size()):
		var car = fleet[index]
		if not is_instance_valid(car) or origin.distance_to(car.door_point()) > minf(radius,4.5): continue
		var ray := PhysicsRayQueryParameters3D.create(origin,car.door_point(),1)
		if not get_world_3d().direct_space_state.intersect_ray(ray).is_empty(): continue
		data.door_damage[index] += 1
		data.opened[index] = data.opened[index] or int(data.door_damage[index]) >= int(profile.blast_hits)
		car.set_vault(_vault_accessible(index),data.taken[index] or data.delivered[index])
		provoke(source)
	_persist()

func _vault_accessible(index: int) -> bool:
	return bool(data.opened[index]) or data.phase in ["loading","unloading"]

func nearest_action() -> Dictionary:
	if not available(): return {}
	for index in mini(2,fleet.size()):
		if data.taken[index] or data.delivered[index] or not _lock_reachable(index): continue
		return {"id":"armored_transport","target":index,"label":"Recolher R$ 40.000" if _vault_accessible(index) else "Arrombar porta · Lockpick"}
	return {}

func _lock_reachable(index: int) -> bool:
	if not crew_operational() or not session.state.place_id.is_empty() or index < 0 or index >= fleet.size(): return false
	var car = fleet[index]
	if not is_instance_valid(car) or absf(car.speed) > .5: return false
	var player: Node3D = session.world.player
	if player.global_position.distance_to(car.door_point()) > 1.8: return false
	var ray := PhysicsRayQueryParameters3D.create(player.global_position+Vector3.UP*.7,car.door_point(),1)
	return get_world_3d().direct_space_state.intersect_ray(ray).is_empty()

func perform(index: int) -> bool:
	if nearest_action().get("target",-1) != index: return false
	if _vault_accessible(index):
		data.opened[index] = true
		data.taken[index] = true
		data.pending += SCHEDULE.CASH_PER_TRUCK
		fleet[index].set_vault(true,true)
		provoke(session.world.player)
		session.show_message(String(TranslationServer.translate("R$ %d na bolsa. Despiste a polícia e escape da escolta.")) % data.pending)
		_persist()
		return true
	var picks := int(session.state.economy.inventory.get("lockpick",0))
	if picks <= 0:
		session.show_message("Precisa de lockpick.")
		return false
	pending_truck = index
	provoke(session.world.player)
	session.modal = true
	session.world.player.input_locked = true
	minigame.begin(picks,randf_range(-75,75))
	return true

func _resolve_lock(result: String) -> void:
	var index := pending_truck
	var reachable := _lock_reachable(index)
	pending_truck = -1
	session.modal = false
	if not session.is_transition_blocked() and session.world.gameplay.health > 0: session.world.player.input_locked = false
	if index < 0 or index >= fleet.size() or not is_instance_valid(fleet[index]): return
	if result == "opened" and reachable:
		data.lock_progress[index] += 1
		data.opened[index] = data.opened[index] or int(data.lock_progress[index]) >= int(profile.lock_stages)
		fleet[index].set_vault(_vault_accessible(index),data.taken[index] or data.delivered[index])
		if not data.opened[index]: session.show_message(String(TranslationServer.translate("Trava reforçada: %d/%d.")) % [data.lock_progress[index],profile.lock_stages])
	elif result == "broken":
		session.state.economy.consume_item("lockpick")
		session.show_message("Lockpick quebrou.")
	_persist()

func _tick_escape(step: float) -> void:
	if data.pending <= 0: return
	var clear: bool = session.world.gameplay.stars == 0 and session.world.gameplay.health > 0 and session.state.place_id.is_empty()
	for index in 4:
		var point := fleet[index].global_position if index < fleet.size() else (_point(data.vehicles[index].point) if data.vehicles.size() == 4 else _virtual_point(index))
		if point.distance_to(session.world.player.global_position) < 85: clear = false
	for guard in guards:
		if is_instance_valid(guard) and not guard.dead and guard.global_position.distance_to(session.world.player.global_position) <= 35.0: clear = false
	escape_seconds = escape_seconds+step if clear else 0.0
	if escape_seconds >= 8.0: _secure_cash()

func _secure_cash() -> void:
	var awarded := 0
	for index in 2:
		if not data.taken[index] or data.secured[index]: continue
		var receipt := "armored:%s:truck:%d" % [data.id,index]
		if session.state.economy.grant_reward(receipt,SCHEDULE.CASH_PER_TRUCK):
			awarded += SCHEDULE.CASH_PER_TRUCK
			data.secured[index] = true
		elif session.state.economy.has_reward_receipt(receipt): data.secured[index] = true
	data.pending = 0
	for index in 2:
		if data.taken[index] and not data.secured[index]: data.pending += SCHEDULE.CASH_PER_TRUCK
	escape_seconds = 0.0
	if awarded > 0: session.show_message(String(TranslationServer.translate("Saque garantido: R$ %d")) % awarded)
	_persist()

func _failed() -> void:
	if is_instance_valid(minigame) and minigame.active: minigame.finish("cancelled")
	if data.is_empty(): return
	data.pending = 0
	_finish()

func _finish() -> void:
	data.phase = "finished"
	_persist()
	_release()

func save_block_reason() -> String:
	if not data.is_empty() and (data.pending > 0 or pending_truck >= 0): return "Escape do assalto ao carro-forte para salvar."
	_persist()
	return ""

func suspend_for_travel() -> void:
	if pending_truck >= 0: minigame.finish("cancelled")
	_persist()
	_release()

func _out_of_sight(distance: float = RETIRE_DISTANCE) -> bool:
	for car in fleet:
		if not is_instance_valid(car): continue
		if car.global_position.distance_to(session.world.player.global_position) < distance or session.controller._on_screen(car.global_position,3.0): return false
	return true

static func _point(value: Array) -> Vector3:
	return Vector3(float(value[0]),float(value[1]),float(value[2]))

func _persist() -> void:
	if data.is_empty(): return
	if not fleet.is_empty():
		var records: Array = []
		for car in fleet:
			if not is_instance_valid(car) or car.is_queued_for_deletion(): return
			var point: Vector3 = car.global_position
			records.append({"point":[point.x,point.y,point.z],"yaw":car.rotation.y,"health":car.health})
			records[-1]["body_dents"]=car.body_dents.snapshot() if is_instance_valid(car.body_dents) else []
			records[-1]["breakaway_parts"]=car.breakaway_parts.snapshot() if is_instance_valid(car.breakaway_parts) else {}
			records[-1]["blood_stains"]=int(car.get_meta("blood_stains",0))
		data.vehicles = records
		data.virtual_poses = false
	if not guards.is_empty():
		var records: Array = []
		for index in guards.size():
			var guard = guards[index]
			if is_instance_valid(guard):
				var point: Vector3 = guard.global_position
				records.append({"health":guard.health,"point":[point.x,point.y,point.z],"seat":_seat(index),"phase":_guard_phases[index]})
			elif index < data.guards.size(): records.append(data.guards[index])
			else: records.append({"health":profile.guard_health,"point":_crew_record_point(index),"seat":_seat(index),"phase":_guard_phases[index]})
		data.guards = records
	session.state.world_state[SCHEDULE.KEY] = {"version":1,"last_event":last_event,"security_level":security_level,"event":data.duplicate(true)}

func _crew_record_point(index: int) -> Array:
	var point := _crew_point(index)
	return [point.x,point.y,point.z]

func _release() -> void:
	_board()
	for child in get_children():
		if child.has_meta("armored_dropped_case"): child.queue_free()
	for car in fleet:
		if is_instance_valid(car):
			session.controller.vehicles.erase(car)
			car.queue_free()
	fleet.clear()
	drivers.clear()

func _exit_tree() -> void:
	_release()
