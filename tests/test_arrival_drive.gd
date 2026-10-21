extends SceneTree
var world
var failures: Array[String] = []
func diagnostic_value(value: Variant) -> Variant:
	if value is Callable:
		var callback: Callable = value
		var owner: Object = callback.get_object()
		return {"method":str(callback.get_method()),"owner":str(owner.get_path()) if is_instance_valid(owner) and owner is Node else str(owner)}
	if value is Object:
		if not is_instance_valid(value): return "freed_object"
		var script: Script = value.get_script()
		return {"class":value.get_class(),"id":value.get_instance_id(),"script":script.resource_path if script != null else "","path":str(value.get_path()) if value is Node else ""}
	if value is Array and value.size()>12: return {"size":value.size(),"first":value.slice(0,12)}
	return value

func body_identity(node: Node) -> Dictionary:
	var properties := {}
	for property in node.get_property_list(): properties[str(property.name)] = true
	var values := {}
	for key in ["vehicle_id","archetype","health","max_health","controlled","external_input","input_locked","engine_disabled","speed","velocity","horizontal_velocity","throttle_input","steer_input","brake_input","traffic","blocked","blocked_time","stall_time","stuck_time","junction_wait","junction_gap","bypass_side","bypass_retry","backoff_time","unjam_time","_exit_wait","route_distance","controller","driver","pilot","owner"]:
		if properties.has(key): values[key] = diagnostic_value(node.get(key))
	var metadata := {}
	for key in node.get_meta_list(): metadata[str(key)] = diagnostic_value(node.get_meta(key))
	var script: Script = node.get_script()
	var children: Array[Dictionary] = []
	for child in node.get_children():
		var child_properties := {}
		for property in child.get_property_list(): child_properties[str(property.name)] = true
		if not child_properties.has("car") and not child_properties.has("vehicle") and not child_properties.has("driver"): continue
		var child_script: Script = child.get_script()
		var info := {"path":str(child.get_path()),"script":child_script.resource_path if child_script != null else "","physics":child.is_physics_processing()}
		for key in ["car","vehicle","driver","pilot","role","mode","hostile","stolen","deployed","route","destination"]:
			if child_properties.has(key): info[key] = diagnostic_value(child.get(key))
		children.append(info)
	return {"instance":node.get_instance_id(),"class":node.get_class(),"script":script.resource_path if script != null else "","groups":node.get_groups(),"properties":values,"meta":metadata,"controllers":children}

func junction_evidence(junction: Dictionary, car) -> Dictionary:
	var registry := preload("res://gameplay/traffic_junctions/TrafficJunctions.gd")
	var key: Vector3i = junction.key
	var center: Vector3 = registry.junctions.get(key,Vector3(key.x*.5,0,key.z*.5))
	var heading: Vector3 = junction.get("heading",Vector3.ZERO)
	var occupants: Array[Dictionary] = []
	var now := Time.get_ticks_msec()
	var leases: Dictionary = registry.owners.get(key,{})
	for id in leases:
		var body: Node3D = instance_from_id(id) as Node3D if is_instance_id_valid(id) else null
		var info := {"id":id,"axis_a":bool(leases[id][0]),"age_seconds":float(now-int(leases[id][1]))/1000.0,"occupies":registry.occupies(key,id),"exists":body!=null}
		if body != null:
			info.path = str(body.get_path())
			info.position = body.global_position
			info.yaw = body.global_rotation.y
			info.physics = body.is_physics_processing()
			for property in body.get_property_list():
				var name := str(property.name)
				if name in ["vehicle_id","archetype","health","controlled","external_input","traffic","speed","velocity","junction_wait","junction_gap","_held_junction","_clearing_junctions","blocked","blocker","route_distance"]:
					info[name] = diagnostic_value(body.get(name))
		occupants.append(info)
	var lenses: Array[Dictionary] = []
	for lens in registry._lenses:
		var lens_center: Vector3 = lens.center
		if lens_center.distance_to(center)>5: continue
		var mesh: MultiMesh = lens.mesh.get_ref()
		if mesh == null or int(lens.index)>=mesh.instance_count: continue
		lenses.append({"center":lens_center,"heading":lens.heading,"cached_state":lens.get("state",""),"live_state":registry.signal_state(key,lens.heading),"color":mesh.get_instance_color(int(lens.index))})
	return {"key":key,"center":center,"axis":registry.axes.get(key),"route_heading":heading,"ahead":float(junction.offset)-car.route_distance,"stop_ahead":float(junction.get("stop_offset",junction.offset))-car.route_distance,"signal":registry.signal_state(key,heading),"signal_source":registry._signal_near(center),"held":car._held_junction==key,"requester_occupies":registry.occupies(key,car.get_instance_id()),"occupants":occupants,"lenses":lenses}

func car_diagnostic(car, curve: Curve3D, label: String) -> void:
	var ahead: Vector3 = curve.sample_baked(minf(car.route_distance+3.0,curve.get_baked_length()))
	var hit_paths: Array[String] = []
	for index in car.get_slide_collision_count():
		var hit = car.get_slide_collision(index).get_collider()
		hit_paths.append(str(hit.get_path()) if is_instance_valid(hit) and hit is Node else str(hit))
	var obstacle := ""
	if is_instance_valid(car.blocker) and car.blocker is Node:
		obstacle = str(car.blocker.get_path())
		if car.blocker is Node3D: obstacle += " at "+str(car.blocker.global_position)
	print("ARRIVAL_CAR_DIAGNOSTIC ",label," position=",car.global_position," speed=",car.speed," route_distance=",car.route_distance,"/",curve.get_baked_length()," next_point=",ahead," yaw=",car.rotation.y," physics=",car.is_physics_processing()," floor=",car.is_on_floor()," blocked=",car.blocked," blocker=",obstacle," junction_wait=",car.junction_wait," collisions=",hit_paths)
	print("ARRIVAL_DRIVER_IDENTITY ",label," ",body_identity(car))
	var near_junctions: Array[Dictionary] = []
	for junction in car._junction_list:
		var ahead_distance: float = float(junction.offset)-car.route_distance
		if ahead_distance>-6.0 and ahead_distance<20.0:
			near_junctions.append({"key":junction.key,"ahead":ahead_distance,"held":car._held_junction==junction.key})
			print("ARRIVAL_JUNCTION_EVIDENCE ",label," ",junction_evidence(junction,car))
	print("ARRIVAL_BYPASS_DIAGNOSTIC ",label," nearby_junctions=",near_junctions," left_corridor_clear=",car._lane_clear(-3.4,car.BYPASS_PROBES)," right_corridor_clear=",car._lane_clear(2.6,car.BYPASS_PROBES)," junction_owners=",preload("res://gameplay/traffic_junctions/TrafficJunctions.gd").owners)
	var arrival = world.session.arrival
	var passenger: Vector3 = arrival._exit_point(1)
	var driver: Vector3 = arrival._exit_point(-1,passenger)
	print("ARRIVAL_EXIT_DIAGNOSTIC ",label," passenger=",passenger," driver=",driver," narration=",arrival.narration_hold_info())
	if not passenger.is_finite(): print("ARRIVAL_PASSENGER_REJECTS ",arrival.exit_candidate_diagnostics(1))
	if not driver.is_finite(): print("ARRIVAL_DRIVER_REJECTS ",arrival.exit_candidate_diagnostics(-1,passenger))
	var cursor: Object = car.blocker
	var seen: Array[int] = []
	for depth in 6:
		if not is_instance_valid(cursor): break
		if cursor.get_instance_id() in seen:
			print("ARRIVAL_BLOCKER_CYCLE ",seen)
			break
		seen.append(cursor.get_instance_id())
		if not cursor is Node: break
		var node := cursor as Node
		print("ARRIVAL_BLOCKER_IDENTITY ",label," ",body_identity(node))
		var details := {"depth":depth,"path":str(node.get_path()),"physics":node.is_physics_processing(),"traffic":node.get("traffic"),"blocked":node.get("blocked"),"speed":node.get("speed"),"junction_wait":node.get("junction_wait"),"stall_time":node.get("stall_time"),"yield":node.get_meta("traffic_yield_state",""),"bypass_side":node.get("bypass_side"),"bypass_retry":node.get("bypass_retry")}
		if node is Node3D: details.position = node.global_position
		print("ARRIVAL_BLOCKER_CHAIN ",details)
		cursor = node.get("blocker")
func _initialize() -> void:
	# Este teste confere a abertura: o runner a pula por padrão (Arrival.skip_opening).
	OS.set_environment("GETECO_SKIP_OPENING", "0")
	run.call_deferred()
func check(value: bool, label: String) -> void:
	if not value: failures.append(label); push_error(label)
func run() -> void:
	world = load("res://Main.tscn").instantiate()
	root.add_child(world)
	for i in 240:
		await physics_frame
		if world.session != null and world.session.ready_for_play: break
	var session = world.session
	print("ARRIVAL_FIXTURE_STATE selected_path=",root.get_node("V2Launch").selected_path," region=",session.state.region_id," place=",session.state.place_id," active_campaign=",session.state.campaign.active_id," campaign_step=",session.state.campaign.step," wanted=",world.gameplay.stars," player_vehicle=",world.driving.car.vehicle_id if is_instance_valid(world.driving.car) else "")
	for i in 240:
		await physics_frame
		if session.arrival.phase == "complete": break
	check(session.arrival.phase == "complete", "skipped opening finishes before tour fixture")
	var arrival = session.arrival
	arrival.active = true
	arrival.opening_completed = true
	arrival.flags = {"harbor_arrival_seen":true, "harbor_arrival_contact_met":true}
	world.player.teleport(arrival.PARK + Vector3(4, .1, 0))
	session.controller.region.set_focus(arrival.PARK)
	for i in 600:
		await physics_frame
		if session.controller.region.is_streaming_idle(): break
	check(session.controller.region.is_streaming_idle(), "terminal street collision streamed before boarding")
	arrival._spawn_encounter()
	var car: CharacterBody3D = arrival.car
	world.player.teleport(car.door_point(1))
	for i in 4: await physics_frame
	arrival._set_phase("tour_board", "", car.door_point(1))
	check(arrival.perform("arrival_board"), "real passenger boarding available")
	for i in 600:
		await physics_frame
		if arrival.riding or arrival.phase == "tour_board": break
	check(arrival.riding, "physical approach reaches both doors and seats")
	if arrival.riding:
		var stalled := 0
		var reported_stall := false
		var reported_narration := false
		# Avança o mundo junto do passeio para o trânsito que compartilha a via
		# dirigir e liberar a faixa; passos manuais congelavam os outros carros.
		# O teto inclui circulação e filas reais sem permitir
		# que uma parada contínua acima de 30 s passe despercebida.
		for step in 9000:
			var before: Vector3 = car.global_position
			await physics_frame
			if not is_instance_valid(car): break
			var narration: Dictionary = arrival.narration_hold_info()
			if before.distance_to(car.global_position) < .001 and narration.holding:
				# Only the demonstrated, finite audio/caption hold at the endpoint
				# is intentional. Physical driving stalls retain the same deadline.
				stalled = 0
				if not reported_narration:
					print("ARRIVAL_PLANNED_NARRATION_HOLD ",narration)
					reported_narration = true
			else:
				stalled = stalled+1 if before.distance_to(car.global_position)<.001 else 0
			if stalled >= 300 and not reported_stall:
				car_diagnostic(car,arrival.route,"stalled_5_seconds")
				reported_stall = true
			if stalled == 0: reported_stall = false
			# Uma fila de cruzamento pode conter mais de um carro; cada reserva
			# expira após 8 s quando o dono fica preso.
			if arrival.flags.get("harbor_city_tour_complete", false) or stalled > 1800: break
		if not is_instance_valid(car):
			check(false,"tour was interrupted by vehicle recovery: "+arrival.recovery_reason)
			world.free()
			await process_frame
			print("ARRIVAL_DRIVE failures=",failures)
			quit(1)
			return
		car_diagnostic(car,arrival.route,"final")
		print("TOUR position=", car.global_position, " distance=", car.route_distance, "/", arrival.route.get_baked_length(), " blocked=", car.blocked, " blocker=", car.blocker.get_path() if is_instance_valid(car.blocker) and car.blocker is Node else str(car.blocker), " riding=", arrival.riding)
		if is_instance_valid(car.blocker) and car.blocker is Node3D:
			print("TOUR blocker_position=", car.blocker.global_position, " ambient=", car.blocker.get_meta("ambient_traffic", false), " traffic=", car.blocker.get("traffic"), " controlled=", car.blocker.get("controlled"), " player_car=", car.blocker == world.driving.car)
		print("TOUR endpoint=", arrival.route.get_point_position(arrival.route.point_count - 1), " yaw=", car.rotation.y, " speed=", car.speed, " junction_wait=", car.junction_wait, " health=", car.health)
		if car.junction_wait: print("TOUR junction owners=", preload("res://gameplay/traffic_junctions/TrafficJunctions.gd").owners, " held=", car._held_junction)
		for index in car.get_slide_collision_count(): print("TOUR collision=", car.get_slide_collision(index).get_collider().get_path())
		if not arrival.flags.get("harbor_city_tour_complete", false):
			print("ARRIVAL_DRIVE_FAIL position=", car.global_position, " distance=", car.route_distance, "/", arrival.route.get_baked_length(), " stalled_frames=", stalled, " blocked=", car.blocked, " junction_wait=", car.junction_wait, " blocker=", car.blocker.get_path() if is_instance_valid(car.blocker) and car.blocker is Node else str(car.blocker))
		check(arrival.flags.get("harbor_city_tour_complete", false), "Harbor street trip reaches the relocated industrial workshop physically")
		check(world.player.visible and world.player.collision_layer == 2, "passenger restored with collision")
		check(not arrival.maciota.has_method("receive_damage"), "Maciota remains immortal during journey")
		if arrival.flags.get("harbor_city_tour_complete", false):
			for i in 600:
				await physics_frame
				if not arrival.maciota.visible: break
			check(not arrival.maciota.visible, "Maciota physically walks to garage doorway")
			check(arrival.maciota.collision_layer == 0, "hidden encounter actor cannot block the workshop approach")
			check(not car.is_physics_processing(), "parked cinematic car does not fall when surrounding floor unloads")
	world.free()
	await process_frame
	print("ARRIVAL_DRIVE failures=", failures)
	quit(0 if failures.is_empty() else 1)
