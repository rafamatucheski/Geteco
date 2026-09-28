extends SceneTree
var world
var failures: Array[String] = []
var checks := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok: failures.append(text); print("FAIL ",text)
func run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	seed(28092026)
	for action in InputMap.get_actions(): InputMap.action_erase_events(action)
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true); root.add_child(world); current_scene = world
	if world.get_script()==null:
		check(false,"Main script compiled"); finish(); return
	for i in 2400:
		await process_frame
		if world.session != null and world.session.ready_for_play: break
	var session = world.session
	var transport = session.passenger_transport
	var taxis = transport.taxis
	world.player.controlled_automatically = true; world.player.automatic_direction = Vector3.ZERO
	world.player.teleport(Vector3(148,.16,71))
	world.production.region.set_focus(world.player.position)
	for i in 360: await physics_frame
	check(taxis.rank.cars.size()==4,"four taxis at the rank")
	check(taxis.rank.drivers.size()==4,"four physical drivers")
	if taxis.rank.cars.size()!=4: finish(); return
	var car = taxis.rank.cars[0]
	var driver = taxis.rank.drivers[0]
	var registrations := {}
	for candidate in taxis.rank.cars.values():
		var art = candidate.visual.get_node("TaxiLivery")
		registrations[art.plates[0].text] = true
		check(art.available and art.sign_material.emission_energy_multiplier > 0,"available roof sign illuminated")
		check(candidate.paint_color.is_equal_approx(Color("ffc526")),"taxi yellow paint")
		check(world.production.vehicle_position_clear(candidate,candidate.position,candidate.rotation.y),"parked taxi has physical clearance")
	check(registrations.size()==4,"distinct registrations")
	# The four drivers stand outside solids and remain independently damageable.
	for resident in taxis.rank.drivers.values():
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = resident.get_child(0).shape
		query.transform.origin = resident.position+Vector3.UP*.86
		query.collision_mask = 7; query.exclude = [resident.get_rid()]
		check(world.get_world_3d().direct_space_state.intersect_shape(query,1).is_empty(),"driver has independent free standing space")
	world.player.teleport(car.driver_door_anchor(1))
	for i in 5: await physics_frame
	check(taxis.offer(car),"rank taxi can be hailed")
	check(session.modal,"hail opens actual menu")
	check(taxis.valid_offer(),"offer remains valid while parked")
	session.close_menu()
	check(taxis.offered==null and not car.traffic,"closing restores parked state")
	check(taxis.offer(car),"reopen after cancellation")
	taxis.request(Vector3(100000,0,100000),"Inacessível")
	check(not transport.riding,"unreachable destination does not board")
	session.close_menu()
	taxis.offer(car)
	var start: Vector3 = car.position
	taxis.request(transport._stop_point(0),"Terminal Sul")
	print("REQUEST riding=",transport.riding," car=",transport.car," modal=",session.modal)
	check(transport.riding,"selected destination boards the actual taxi")
	if transport.riding:
		check(transport.car==car,"ride reuses rank vehicle")
		check(not world.player.visible and world.player.collision_layer==0,"passenger body safely stowed")
		check(not car.visual.get_node("TaxiLivery").available,"occupied sign off")
		check(not car.is_in_group("drivable"),"occupied taxi cannot be stolen midride")
		for i in 1000:
			await physics_frame
			if i%300==0: print("RIDE ",car.position," speed=",car.speed," blocked=",car.blocked," blocker=",car.blocker," junction=",car.junction_wait," traffic=",car.traffic," route=",car.route_distance)
			if car.position.distance_to(start)>15 or not transport.riding: break
		print("TRAVEL ",car.position," distance ",car.position.distance_to(start))
		check(car.position.distance_to(start)>15,"taxi physically drives out of bay and along street")
		transport.request_exit()
		for i in 600:
			await physics_frame
			if not transport.riding: break
		check(not transport.riding,"requested safe disembark completes")
		check(world.player.visible and world.player.collision_layer==2,"passenger visibility and collision restored")
		check(car.is_in_group("drivable"),"finished ride remains usable")
		check(not is_instance_valid(driver),"rank driver boarded")
	else: session.close_menu()
	if not transport.riding:
		# A real destination on the same street exercises automatic arrival.
		world.player.teleport(car.driver_door_anchor(1))
		for i in 4: await physics_frame
		var offered: bool = taxis.offer(car)
		print("REBOOK offer=",offered," eligible=",transport._eligible()," stars=",world.gameplay.stars," distance=",world.player.position.distance_to(car.position)," available=",taxis.available(car))
		var goal: Vector3 = car.position-car.global_basis.z*17
		taxis.request(goal,"Rodoviária")
		print("REBOOK riding=",transport.riding," modal=",session.modal," goal=",goal," notice=",session.notice.text)
		check(transport.riding,"completed cab accepts another ride")
		for i in 2400:
			await physics_frame
			if not transport.riding: break
		check(not transport.riding and car.position.distance_to(goal)<4,"automatic arrival at selected destination")
		check(world.player.visible and world.player.collision_layer==2,"automatic arrival restores actor")
		if session.modal: session.close_menu()
	var stolen = taxis.rank.cars.get(2)
	if is_instance_valid(stolen):
		world.player.teleport(stolen.driver_door_anchor(1))
		for i in 10: await physics_frame
		check(world.driving.interact(),"F opens taxi menu")
		check(session.modal and not world.driving.occupied,"F offers ride or theft before entry")
		taxis.steal()
		for i in 240:
			await physics_frame
			if world.driving.occupied and not world.driving.is_body_transition_active(): break
		check(world.driving.occupied and world.driving.car==stolen,"steal grants driving control")
		check(stolen.get_meta("taxi_stolen",false) and not taxis.available(stolen),"stolen taxi no longer offers fares")
		check(not stolen.visual.get_node("TaxiLivery").available,"stolen roof sign off")
		check(taxis.rank.drivers[2].frightened,"owner reacts to theft")
		check(world.gameplay.crime_points>0,"taxi theft registers crime")
		var saved: Dictionary = preload("res://runtime/FleetState.gd").capture(stolen,"harbor")
		check(preload("res://runtime/FleetState.gd").validate(saved),"stolen taxi valid for normal fleet persistence")
		check(saved.vehicle_id==stolen.vehicle_id and saved.paint==stolen.paint_color.to_html(true),"save retains taxi identity and paint")
	# Leaving the area unloads rank NPCs and decoration, preserving the stolen car.
	world.player.teleport(Vector3(400,.1,25))
	taxis.rank._unload()
	await process_frame
	check(taxis.rank.cars.is_empty() and taxis.rank.drivers.is_empty(),"rank unloads its own cars and drivers")
	check(is_instance_valid(stolen) and not stolen.is_queued_for_deletion(),"rank unload preserves player vehicle")
	finish()

func finish() -> void:
	print("TAXI_SERVICE ",checks," checks failures=",failures)
	world.free(); quit(0 if failures.is_empty() else 1)
