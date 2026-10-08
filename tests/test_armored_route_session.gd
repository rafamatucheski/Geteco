extends SceneTree
## Complete service over production roads. The observer follows on foot only to
## retain streaming; the four convoy bodies are never moved or accelerated here.
const FIXTURE := preload("res://tests/fixtures/NorthGatewayFixtures.gd")
const PLACES := preload("res://world/places/PlaceCatalog.gd")
const SCHEDULE := preload("res://gameplay/armored/ArmoredSchedule.gd")
const DISPATCH_RULES := preload("res://gameplay/dispatch/DispatchRules.gd")
var world
var failures: Array[String] = []
var checks := 0
var folder := ""
var origin := "harbor_bank"
var _last_trace := 0
var _last_follow := 0
var _started := 0
var _floor_failures := 0
var _retired := false
var _observed: Dictionary = {}
var _minimum_health := 1.0
var _last_positions: Array = []
var _travelled := [0.0,0.0,0.0,0.0]
var _lead_anchor := Vector3.INF
var _lead_progress_at := 0
var _service_wait_until := 0
var _service_deadlines: Dictionary = {}
var _checkpoint_driving := false
var _maximum_security := false
var _maximum_crew_verified := false
var _minimum_travel := 1000.0
var _unloading_only := false
func _initialize() -> void:
	create_timer(1260).timeout.connect(func(): check(false,"bounded full route timeout"); finish(3))
	run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	print("ARMORED_ROUTE_SESSION ","PASS " if ok else "FAIL ",label)
	if not ok: failures.append(label)
func photo(label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(folder.path_join(label+".png"))
func run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	if "--desert" in OS.get_cmdline_user_args(): origin = "desert_bank"
	_maximum_security = "--maximum-security" in OS.get_cmdline_user_args()
	folder = FIXTURE.output_dir("armored-route-"+origin)
	var bank: Vector3 = PLACES.get_definition(origin).entry_position
	var point := bank+Vector3(0,.12,2)
	var corner_diagnostic := "--diagnostic-corner" in OS.get_cmdline_user_args()
	var gateway_diagnostic := "--diagnostic-gateway" in OS.get_cmdline_user_args()
	var city_return_diagnostic := "--diagnostic-city-return" in OS.get_cmdline_user_args()
	var junction_exit_diagnostic := "--diagnostic-junction-exit" in OS.get_cmdline_user_args()
	var post_gateway_diagnostic := "--diagnostic-post-gateway" in OS.get_cmdline_user_args()
	var cobre_arrival_diagnostic := "--diagnostic-cobre-arrival" in OS.get_cmdline_user_args()
	_unloading_only = "--diagnostic-cobre-unloading" in OS.get_cmdline_user_args()
	_checkpoint_driving = corner_diagnostic or gateway_diagnostic or city_return_diagnostic or junction_exit_diagnostic or post_gateway_diagnostic or cobre_arrival_diagnostic or _unloading_only or "--diagnostic-driving" in OS.get_cmdline_user_args()
	if corner_diagnostic: point = Vector3(286,.12,-45)
	if gateway_diagnostic: point = Vector3(372,.12,-240)
	if city_return_diagnostic: point = Vector3(372,.12,-240)
	if city_return_diagnostic: _minimum_travel = 350.0
	if junction_exit_diagnostic: point = Vector3(372,.12,-160)
	if post_gateway_diagnostic: point = Vector3(335,2.52,-285)
	if cobre_arrival_diagnostic:
		point = Vector3(338,.12,-894)
		_minimum_travel = 450.0
	# The saved personal coupe parks eight metres north of this observer; keep
	# that legal parked car beyond the convoy's bank-side unloading formation.
	if _unloading_only: point = Vector3(-230,.12,-890.25)
	var snapshot := FIXTURE.full_snapshot(point,true)
	snapshot.campaign.aftermath = {"call_complete":true}
	var region := "desert" if origin == "desert_bank" or cobre_arrival_diagnostic or _unloading_only else "harbor"
	snapshot.region_id = region
	snapshot.world.pedestrian = {"region":region,"position":[point.x,point.y,point.z]}
	snapshot.world.moon_day = 3 if origin == "desert_bank" else 1
	snapshot.world.time = (14.0 if origin == "desert_bank" else 9.0)/24.0
	if _maximum_security:
		snapshot.world[SCHEDULE.KEY] = {"version":1,"last_event":"","security_level":6,"event":{}}
	if _checkpoint_driving:
		var departure := SCHEDULE.departure(int(snapshot.world.moon_day),float(snapshot.world.time))
		var event := SCHEDULE.initial(departure,6 if _maximum_security else 0)
		event.phase = "driving"
		event.cargo_cycles = [2,2]
		if corner_diagnostic: event.route_offset = 260.0
		if gateway_diagnostic: event.route_offset = 560.0
		if city_return_diagnostic: event.route_offset = 1280.0
		if junction_exit_diagnostic: event.route_offset = 400.0
		# Coverage starts beyond the independently recorded ambient reservation
		# deadlock; this checkpoint does NOT approve passage through that return.
		if post_gateway_diagnostic: event.route_offset = 690.0
		if cobre_arrival_diagnostic:
			event.route_offset = 1300.0
			print("ARMORED_COVERAGE approach/unloading at Cobre only; north return NOT covered; offset1300; each body must drive >450m")
		if _unloading_only:
			event.route_offset = 1807.0
			event.phase = "unloading"
			event.cargo_cycles = [0,0]
			print("ARMORED_COVERAGE Cobre unloading and physical return to posts only; driving/north return NOT covered")
		snapshot.world[SCHEDULE.KEY] = {"version":1,"last_event":event.id,"security_level":6 if _maximum_security else 0,"event":event}
	var path := FIXTURE.write_fixture(folder,"checkpoint.json",snapshot)
	check(not path.is_empty(),"isolated post-finale scheduled checkpoint accepted")
	if path.is_empty(): finish(1); return
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	world.set_meta("menu_save_path",path)
	root.add_child(world)
	current_scene = world
	for frame in 7000:
		await physics_frame
		if world.session != null and world.session.ready_for_play: break
	check(world.session != null and world.session.ready_for_play and not world.production.save_invalid,"production Main ready")
	if not failures.is_empty(): finish(1); return
	var session = world.session
	if session.modal: session.close_menu()
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	world.production.region.set_focus(point)
	await physics_frame
	await physics_frame
	var placed := false
	for offset in [Vector3.ZERO,Vector3(3,0,0),Vector3(-3,0,0),Vector3(0,0,2),Vector3(0,0,4)]:
		if session.position_clear(point+offset):
			world.player.teleport(point+offset)
			placed = true
			break
	check(placed,"observer begins outside the existing bank on supported clear ground")
	if not placed: finish(1); return
	world.dispatch.router.nearest_edge(world.player.global_position)
	check(world.dispatch.router._native != null,"compiled native router active")
	var convoy = session.armored_transport
	_started = Time.get_ticks_msec()
	var admitted := false
	var delivered := false
	while Time.get_ticks_msec()-_started < (240000 if _unloading_only else 1200000):
		await physics_frame
		if convoy.data.is_empty(): continue
		if convoy.fleet.size() == 4:
			admitted = true
			if _maximum_security and not _maximum_crew_verified and convoy.data.phase == "boarding":
				_maximum_crew_verified = true
				check(convoy.guards.size() == 10 and convoy.guards.all(func(guard): return is_instance_valid(guard) and not guard.dead and guard.health >= 180),"maximum security physically loaded with ten living guards at 180 HP")
			if not _observed.has(convoy.data.phase):
				_observed[convoy.data.phase] = true
				await photo(convoy.data.phase)
			if convoy.data.phase == "driving":
				var lead_point: Vector3 = convoy.fleet[2].global_position
				if not _lead_anchor.is_finite() or lead_point.distance_to(_lead_anchor) > 2.0:
					_lead_anchor = lead_point
					_lead_progress_at = Time.get_ticks_msec()
					_service_wait_until = 0
				_extend_service_wait(convoy)
				if Time.get_ticks_msec() > maxi(_lead_progress_at+70000,_service_wait_until):
					check(false,"leader made no progress beyond traffic cycles and any real emergency service deadline")
					_trace(convoy)
					break
			if Time.get_ticks_msec()-_last_follow >= 500:
				_last_follow = Time.get_ticks_msec()
				_follow(convoy)
				_observe_physics(convoy)
			if convoy.data.phase == "unloading" and convoy.data.delivered == [true,true] and _crew_back_at_posts(convoy):
				delivered = true
				break
		elif admitted:
			_retired = true
			break
		if Time.get_ticks_msec()-_last_trace >= 15000:
			_last_trace = Time.get_ticks_msec()
			_trace(convoy)
		if not admitted and Time.get_ticks_msec()-_started > 30000:
			check(false,"scheduled service could not admit its four bodies in 30 seconds")
			_trace(convoy)
			break
		if convoy.data.hostile or world.gameplay.health <= 0: break
		if convoy.data.phase in ["departing","finished"] and not delivered:
			check(false,"lawful service aborted before both consignments were delivered")
			_trace(convoy)
			break
	check(admitted,"two armored trucks and two escorts physically admitted")
	if _maximum_security and not _checkpoint_driving: check(_maximum_crew_verified,"maximum-security crew reached real boarding")
	check(not _retired,"observer retained physical fleet across regional streaming")
	if _unloading_only:
		check(_observed.has("unloading"),"saved unloading checkpoint admitted physical destination service (driving not covered)")
	elif _checkpoint_driving:
		check(_observed.has("driving") and _observed.has("unloading"),"saved driving checkpoint reached physical arrival (origin loading not covered)")
	else:
		check(_observed.has("loading") and _observed.has("boarding") and _observed.has("driving") and _observed.has("unloading"),"both bank operations connected by physical departure and arrival")
	check(delivered,"both R$40000 consignments unloaded by physical crew at destination")
	check(_crew_back_at_posts(convoy),"all surviving crew returned physically to their exterior posts")
	check(_floor_failures == 0,"fleet retained actual road support across route and north bridge")
	if not _unloading_only: check(_travelled.all(func(distance): return distance > _minimum_travel),"all four bodies physically drove over %d metres after the declared checkpoint" % int(_minimum_travel))
	check(_minimum_health > .65,"physical route caused no severe fleet collision damage")
	check(not convoy.data.hostile and world.gameplay.stars == 0,"legal service did not incriminate observer")
	check(convoy.data.taken == [false,false] and convoy.data.pending == 0,"bank delivery did not grant stolen cash")
	check(SCHEDULE.valid_saved(session.state.world_state.get(SCHEDULE.KEY,{})),"complete live service snapshot remains valid")
	_trace(convoy)
	await photo("final")
	finish(0 if failures.is_empty() else 1)
func _crew_back_at_posts(convoy) -> bool:
	if convoy.guards.size() != int(convoy.profile.crew_count): return false
	for index in convoy.guards.size():
		var guard = convoy.guards[index]
		if not is_instance_valid(guard) or guard.dead or guard.patrol_target.distance_to(convoy._crew_point(index)) > .2 or not guard.reached_target(.8): return false
	return true
func _follow(convoy) -> void:
	var lead = convoy.fleet[2]
	world.camera.target = lead
	if world.player.global_position.distance_to(lead.global_position) < 28 and _observer_clear(world.player.global_position,convoy): return
	# Find a supported observer foothold; moving this fixture never drives,
	# unblocks, repairs, hides or teleports service vehicles or ambient traffic.
	for lateral in [8.0,-8.0,11.0,-11.0,15.0,-15.0,20.0,-20.0,26.0,-26.0]:
		for along in [0.0,5.0,-5.0,10.0,-10.0]:
			var point: Vector3 = lead.global_position+lead.global_basis.x*lateral+lead.global_basis.z*along
			if _observer_clear(point,convoy):
				world.player.teleport(point)
				return
func _observer_clear(point: Vector3,convoy) -> bool:
	# Standing on clear ground now is insufficient: remain outside the whole future
	# route corridor, including the native driver's maximum lateral bypass envelope.
	if not world.session.position_clear(point): return false
	var nearest: Vector3 = convoy.road.get_closest_point(point)
	if Vector2(point.x,point.z).distance_to(Vector2(nearest.x,nearest.z)) < 6.0: return false
	for car in convoy.fleet:
		if point.distance_to(car.global_position) < 8.0: return false
	return true
func _observe_physics(convoy) -> void:
	for index in 4:
		var car = convoy.fleet[index]
		_minimum_health = minf(_minimum_health,car.health/car.max_health)
		if _last_positions.size() == 4: _travelled[index] += car.global_position.distance_to(_last_positions[index])
		var query := PhysicsRayQueryParameters3D.create(car.global_position+Vector3.UP,car.global_position-Vector3.UP*1.2,1)
		if world.get_world_3d().direct_space_state.intersect_ray(query).is_empty(): _floor_failures += 1
	_last_positions.clear()
	for car in convoy.fleet: _last_positions.append(car.global_position)
func _trace(convoy) -> void:
	var cars: Array = []
	for index in convoy.fleet.size():
		var car = convoy.fleet[index]
		var driver = convoy.drivers[index]
		cars.append({"point":str(car.global_position),"yaw":car.rotation.y,"lane_error":driver.route.get_closest_point(car.global_position).distance_to(car.global_position),"bypass_side":car.bypass_side,"bypass_blend":car.bypass_blend,"merging_back":car._merging_back,"speed":car.speed,"health":car.health,"remaining":driver.remaining,"blocked":driver.blocked_ahead,"signal":car.junction_wait,"formation_wait":car.get_meta("armored_formation_wait",false),"stalled":driver.stalled,"target":str(driver.route.sample_baked(minf(driver.offset+4.0,driver.route.get_baked_length()),true)),"hull":_hull_trace(car,driver) if absf(car.speed) < .2 else {},"sensor":_sensor_hits(car,driver) if driver.blocked_ahead else []})
	var crew: Array = []
	for guard in convoy.guards:
		if is_instance_valid(guard): crew.append({"point":str(guard.global_position),"target":str(guard.patrol_target),"health":guard.health,"dead":guard.dead})
	for lead in convoy.fleet:
		if not lead.junction_wait: continue
		var signals = preload("res://gameplay/traffic_junctions/TrafficJunctions.gd")
		var approaches: Array = []
		for junction in lead._junction_list:
			if absf(float(junction.offset)-float(lead.route_distance)) > 35.0: continue
			var owners: Dictionary = signals.owners.get(junction.key,{})
			var occupants: Array = []
			for id in owners:
				var body = instance_from_id(int(id))
				if is_instance_valid(body): occupants.append({"id":id,"point":body.global_position,"vehicle_id":body.get("vehicle_id") if "vehicle_id" in body else "","speed":body.get("speed") if "speed" in body else 0})
			approaches.append({"row":junction,"state":signals.signal_state(junction.key,junction.get("heading",Vector3.ZERO)),"owners":owners,"occupants":occupants,"axis":signals.axes.get(junction.key,Vector2.ZERO)})
		print("ARMORED_JUNCTION_TRACE ",JSON.stringify({"lead":lead.get_instance_id(),"point":lead.global_position,"gap":lead.junction_gap,"held":lead._held_junction,"clearing":lead._clearing_junctions,"exit_blocked":lead._exit_blocked,"exit_wait":lead._exit_wait,"approaches":approaches}))
	print("ARMORED_ROUTE_TRACE ",JSON.stringify({"admission":convoy.admission_status,"admission_probe":convoy.admission_probe,"road":convoy.road != null,"seconds":(Time.get_ticks_msec()-_started)/1000.0,"observer":world.player.global_position,"region":world.session.state.region_id,"phase":convoy.data.get("phase",""),"cycles":convoy.data.get("cargo_cycles",[]),"cars":cars,"crew":crew,"travelled":_travelled,"dispatch":_dispatch_trace()}))
func _sensor_hits(car, driver) -> Array:
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = car.sensor_shape if car.traffic else driver._sensor
	query.transform = Transform3D(car.global_basis,car.global_position-car.global_basis.z*(car.half_length+query.shape.size.z*.5)+Vector3.UP*.8)
	query.collision_mask = 7
	query.exclude = [car.get_rid()]
	var result: Array = []
	for hit in world.get_world_3d().direct_space_state.intersect_shape(query,8):
		var body = hit.collider
		result.append({"path":str(body.get_path()),"class":body.get_class(),"point":str(body.global_position),"vehicle_id":body.get("vehicle_id") if body is CharacterBody3D else "","yaw":body.rotation.y,"speed":body.get("speed") if "speed" in body else 0,"traffic":body.get("traffic") if "traffic" in body else false,"signal":body.get("junction_wait") if "junction_wait" in body else false})
	return result

func _hull_trace(car, driver) -> Dictionary:
	var contacts: Array = []
	for index in car.get_slide_collision_count():
		var contact = car.get_slide_collision(index)
		var body = contact.get_collider()
		contacts.append({"body":str(body.get_path()),"normal":contact.get_normal(),"point":contact.get_position(),"vehicle_id":body.get("vehicle_id") if "vehicle_id" in body else "","script":body.get_script().resource_path if body.get_script() != null else "","player":body == world.player})
	var goal: Vector3 = driver.route.sample_baked(minf(driver.offset+3.0,driver.route.get_baked_length()),true)
	var direction: Vector3 = goal-car.global_position
	var yaw := rotate_toward(float(car.rotation.y),atan2(-direction.x,-direction.z),1.7/60.0)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = car.rotation_shape
	query.collision_mask = 7
	query.exclude = [car.get_rid()]
	query.transform = Transform3D(Basis(Vector3.UP,yaw),car.global_position+Vector3.UP*car.shape.position.y)
	var hits: Array = []
	for hit in world.get_world_3d().direct_space_state.intersect_shape(query,8): hits.append({"body":str(hit.collider.get_path()),"point":hit.collider.global_position,"shape":hit.shape})
	return {"contacts":contacts,"rotation_hits":hits,"attempted_yaw":yaw,"goal":goal,"shape_size":car.rotation_shape.size}

func _extend_service_wait(convoy) -> void:
	# Follow the actual blocker anywhere in the formation. One fixed deadline per
	# body includes the remaining lawful service and its existing departure policy;
	# state changes never renew it. Departure still needs visibility/distance checks
	# in DispatchUnit: the harness does not remove a car when this allowance expires.
	for car in convoy.fleet:
		if not car.blocked or not is_instance_valid(car.blocker): continue
		var body = car.blocker
		var key: int = body.get_instance_id()
		if not _service_deadlines.has(key):
			var allowance := 0.0
			if "health" in body and body.health <= 0.0: allowance = 12.0+70.0
			for unit in world.dispatch.units:
				if unit.vehicle != body or unit.service == "police": continue
				match unit.state:
					"enroute": allowance = maxf(0.0,DISPATCH_RULES.UNANSWERED_SECONDS-float(unit.age))+8.6+DISPATCH_RULES.MAX_INCIDENT_SECONDS+180.0+70.0
					"parked": allowance = maxf(0.0,8.6-float(unit.state_age))+DISPATCH_RULES.MAX_INCIDENT_SECONDS+180.0+70.0
					"working": allowance = maxf(0.0,DISPATCH_RULES.MAX_INCIDENT_SECONDS-float(unit.state_age))+180.0+70.0
					"departing": allowance = maxf(0.0,180.0-float(unit._departure_clock))+70.0
				break
			if allowance > 0.0:
				_service_deadlines[key] = Time.get_ticks_msec()+int(allowance*1000.0)
				print("ARMORED_SERVICE_WAIT ",JSON.stringify({"blocking_body":str(body.get_path()),"vehicle":body.get("vehicle_id"),"allowance_seconds":allowance,"deadline_msec":_service_deadlines[key]}))
		if _service_deadlines.has(key): _service_wait_until = maxi(_service_wait_until,int(_service_deadlines[key]))

func _dispatch_trace() -> Array:
	var result: Array = []
	if not is_instance_valid(world) or world.dispatch == null: return result
	for unit in world.dispatch.units:
		if not is_instance_valid(unit.vehicle): continue
		if unit.vehicle.global_position.distance_to(world.player.global_position) > 150.0: continue
		result.append({"id":unit.vehicle.vehicle_id,"state":unit.state,"age":unit.age,"state_age":unit.state_age,"departure_age":unit._departure_clock,"unseen":world.dispatch.is_unseen(unit.vehicle.global_position),"player_distance":world.dispatch.distance_to_player(unit.vehicle.global_position),"point":unit.vehicle.global_position,"siren":unit.vehicle.equipment.siren_on if is_instance_valid(unit.vehicle.equipment) else false,"driver":unit.driver.stop_status() if unit.driver != null else "","crew_mode":unit.crew.mode if is_instance_valid(unit.crew) else "","crew_point":unit.crew.global_position if is_instance_valid(unit.crew) else Vector3.INF,"patient_point":unit.actor.global_position if is_instance_valid(unit.actor) else Vector3.INF,"return_door":unit.vehicle.to_global(Vector3(unit.vehicle.half_width+.8,0,0))})
	return result

func finish(code: int) -> void:
	print("ARMORED_ROUTE_RESULT ",JSON.stringify({"checks":checks,"failures":failures,"origin":origin,"maximum_security":_maximum_security,"checkpoint_driving":_checkpoint_driving,"unloading_only":_unloading_only,"evidence":folder,"floor_failures":_floor_failures,"minimum_health":_minimum_health,"travelled":_travelled,"dispatch":_dispatch_trace()}))
	if is_instance_valid(world): world.queue_free()
	quit(code)

