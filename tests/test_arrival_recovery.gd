extends SceneTree
## A removed cinematic body must release Dante's actual capsule and camera.
var world
var failures: Array[String] = []

func _initialize() -> void: run.call_deferred()

func check(value: bool, message: String) -> void:
	if not value: failures.append(message); push_error(message)

func run() -> void:
	root.get_node("V2Launch").selected_path = "user://arrival-recovery-isolated.json"
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	root.add_child(world)
	var deadline := Time.get_ticks_msec()+80000
	while Time.get_ticks_msec()<deadline:
		await physics_frame
		if world.session != null and world.session.ready_for_play: break
	if world.session == null or not world.session.ready_for_play:
		push_error("Arrival recovery startup unavailable"); world.free(); quit(1); return
	var session = world.session
	var arrival = session.arrival
	check(world.production.no_save,"recovery fixture cannot write a user journey")
	arrival.active = false
	world.player.teleport(arrival.PARK+Vector3(0,.08,5))
	world.production.region.set_focus(world.player.global_position)
	for i in 600:
		await physics_frame
		if world.production.region.is_streaming_idle(): break
	arrival._spawn_encounter()
	# The real driver stops one metre short of an open route. Verify both exits
	# beside Jessica's full physical Jetta hull, rather than assuming an empty bay.
	var parking: Vector3 = world.maciota_place.tour_parking
	world.player.teleport(parking+Vector3(-1.1,.08,3.0))
	world.production.region.set_focus(world.player.global_position)
	for i in 600:
		await physics_frame
		if world.production.region.is_streaming_idle(): break
	var jetta := preload("res://scripts/Vehicle.gd").new()
	jetta.archetype = preload("res://gameplay/jessica/JessicaCarSpec.gd").ID
	jetta.position = Vector3(154.25,.01,105.1)
	world.add_child(jetta)
	jetta.set_physics_process(false)
	var curve: Curve3D = arrival._build_route()
	var stop := curve.sample_baked(curve.get_baked_length()-1.0,true)
	var direction := curve.sample_baked(curve.get_baked_length()-.95,true)-curve.sample_baked(curve.get_baked_length()-1.05,true)
	arrival.car.place(stop+Vector3.UP*.01,atan2(-direction.x,-direction.z))
	arrival.car.set_physics_process(false)
	await physics_frame
	var hull_query := PhysicsShapeQueryParameters3D.new()
	hull_query.shape = arrival.car.shape.shape
	hull_query.transform = arrival.car.shape.global_transform
	hull_query.collision_mask = 4
	hull_query.exclude = [arrival.car.get_rid()]
	check(world.get_world_3d().direct_space_state.intersect_shape(hull_query,1).is_empty(),"stopped M8 full hull stays outside the neighboring Jetta")
	arrival._player_layer = 2
	arrival._player_mask = 7
	arrival.riding = true
	arrival.controls_locked = true
	world.player.hide()
	world.player.collision_layer = 0
	world.player.collision_mask = 0
	world.player.set_physics_process(false)
	arrival.maciota.hide()
	arrival.maciota.collision_layer = 0
	arrival.maciota.collision_mask = 0
	check(arrival._leave_car(),"final M8 pose permits two safe exits beside the parked Jetta")
	if not arrival.last_exit_plan.is_empty():
		check(arrival.last_exit_plan.passenger.distance_to(arrival.last_exit_plan.driver)>=1.0,"final pose separates the two admitted actor capsules")
		check(session.position_clear(world.player.global_position),"final pose puts Dante on supported clear ground")
	# Run the actual collision handler on the controlled cinematic driver. The
	# street system owns damage/impulse/stun; Arrival must resume only afterward.
	world.player.teleport(arrival.PARK+Vector3(0,.08,5))
	world.production.region.set_focus(world.player.global_position)
	for i in 600:
		await physics_frame
		if world.production.region.is_streaming_idle(): break
	var balance: int = session.state.economy.balance
	var campaign: Dictionary = session.state.campaign.snapshot()
	arrival._player_layer = 2
	arrival._player_mask = 7
	arrival.flags = {"harbor_arrival_seen":true,"harbor_arrival_contact_met":true,"harbor_city_tour_started":true}
	arrival.phase = "city_tour"
	arrival.opening_completed = true
	arrival.riding = true
	arrival.controls_locked = true
	world.player.collision_layer = 0
	world.player.collision_mask = 0
	world.player.set_physics_process(false)
	world.player.hide()
	world.player.input_locked = true
	world.camera.target = arrival.car
	arrival.car.place(arrival.PARK+Vector3.UP*.01,0)
	jetta.place(arrival.PARK+Vector3(0,.01,-6),0)
	arrival.route = Curve3D.new()
	arrival.route.add_point(arrival.PARK)
	arrival.route.add_point(arrival.PARK+Vector3.FORWARD*10)
	arrival.route.set_meta("traffic_open",true)
	arrival.car.route = arrival.route
	arrival.car.traffic = true
	arrival.car.controlled = true
	arrival.car.brake_input = false
	arrival.car.set_physics_process(true)
	arrival.active = true
	var healthy_before: float = arrival.car.health
	var resumes_before: int = arrival.crash_resume_count
	var street = preload("res://gameplay/street_physics/StreetPhysics.gd").instance
	street._crash(arrival.car,jetta,Vector3.BACK,4.0,arrival.car.global_position+Vector3.FORWARD*arrival.car.half_length,Vector3.FORWARD*4.0)
	check(arrival.car.health<healthy_before and arrival.car.health>0,"real contact damage remains active for the cinematic M8")
	check(arrival.car.has_meta("crash_stun") and not arrival.car.traffic,"real street collision suspends the cinematic driver")
	await physics_frame
	check(not arrival.car.traffic and arrival.car.has_meta("crash_stun"),"driver stays suspended while the street impact settles")
	deadline = Time.get_ticks_msec()+5000
	while Time.get_ticks_msec()<deadline:
		await physics_frame
		if arrival.car.traffic and not arrival.car.has_meta("crash_stun"): break
	check(arrival.car.traffic and arrival.car.controlled and arrival.car.external_input and not arrival.car.brake_input,"healthy cinematic driver resumes its native route after impact stun")
	check(arrival.crash_resume_count==resumes_before+1,"impact resumes the cinematic driver exactly once")
	check(session.state.economy.balance==balance and session.state.campaign.snapshot()==campaign,"impact recovery grants no campaign progress or reward")
	street._crash(arrival.car,jetta,Vector3.BACK,4.0,arrival.car.global_position+Vector3.FORWARD*arrival.car.half_length,Vector3.FORWARD*4.0)
	check(arrival.cancel_ride(),"passenger can safely interrupt the ride during impact stun")
	deadline = Time.get_ticks_msec()+5000
	while Time.get_ticks_msec()<deadline:
		await physics_frame
		if not arrival.car.has_meta("crash_stun"): break
	check(not arrival.car.traffic and not arrival.riding and world.player.visible,"cancelled ride remains parked after the impact settles")
	check(arrival.crash_resume_count==resumes_before+1,"cancelled impact never resumes the cinematic driver")
	arrival.active = false
	arrival.car.traffic = false
	arrival.car.controlled = false
	arrival.car.stop_boarding_motion()
	jetta.free()
	# Then remove the car itself while the player is hidden in the same ride.
	arrival.phase = "city_tour"
	arrival.riding = true
	arrival.controls_locked = true
	world.player.collision_layer = 0
	world.player.collision_mask = 0
	world.player.set_physics_process(false)
	world.player.hide()
	world.player.input_locked = true
	world.camera.target = arrival.car
	arrival.car.free()
	arrival.active = true
	deadline = Time.get_ticks_msec()+5000
	while Time.get_ticks_msec()<deadline:
		await physics_frame
		if not arrival.riding and world.player.visible and not arrival.controls_locked: break
	check(not arrival.riding and not arrival.controls_locked,"removed body releases passenger ownership")
	check(world.player.visible and world.player.collision_layer==2 and world.player.collision_mask==7,"removed body restores visibility and the full player collision")
	check(not world.player.input_locked and world.camera.target == world.player,"removed body restores camera and player control")
	check(arrival.phase=="tour_board" and is_instance_valid(arrival.car),"recovery recreates the terminal encounter for another attempt")
	check(not arrival.flags.get("harbor_city_tour_complete",false) and not arrival.flags.get("harbor_city_tour_started",false),"recovery does not manufacture a completed journey")
	check(session.state.economy.balance==balance and session.state.campaign.snapshot()==campaign,"recovery grants no campaign progress or reward")
	check(preload("res://runtime/Arrival.gd").validate_snapshot(arrival.snapshot()),"recovered checkpoint remains saveable")
	world.free()
	await process_frame
	print("ARRIVAL_RECOVERY failures=",failures)
	quit(0 if failures.is_empty() else 1)
