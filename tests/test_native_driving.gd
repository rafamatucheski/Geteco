extends SceneTree
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	root.add_child(world)
	# A direção começa depois da admissão, nunca contra o carro temporário do início.
	var startup_deadline := Time.get_ticks_msec() + 90000
	while Time.get_ticks_msec() < startup_deadline:
		await physics_frame
		if admitted(world): break
	if not admitted(world):
		print("DRIVE_ADMISSION ",JSON.stringify(admission_state(world)))
		push_error("Native world did not finish loading before driving validation")
		world.free()
		await process_frame
		quit(1)
		return
	var car: CharacterBody3D = world.driving.car
	var route: Curve3D = world.production.traffic_routes.route_near(car.position)
	var distance := route.get_closest_offset(car.position)
	var point := route.sample_baked(distance,true)
	var direction := route.sample_baked(distance+1,true)-point
	print("DRIVE_DIAGNOSTIC before=",car.position," point=",point," shape=",car.shape.shape.size," center=",car.shape.position)
	car.place(point+Vector3.UP*.12,atan2(-direction.x,-direction.z))
	print("DRIVE_DIAGNOSTIC placed=",car.position," valid=",world.production.vehicle_position_clear(car,car.position,car.rotation.y))
	for i in 3: await physics_frame
	print("DRIVE_DIAGNOSTIC after=",car.position," floor=",car.is_on_floor())
	var entered := false
	for side in [-1,1]:
		var approach := car.to_global(Vector3(side*(car.half_width+.65),.04,.15))
		print("DRIVE_DIAGNOSTIC door=",approach," clear=",world.session.position_clear(approach))
		world.player.teleport(approach)
		await physics_frame
		if world.driving.interact(): entered=true; break
	print("NATIVE_DRIVING_ENTRY ","PASS" if entered else "FAIL")
	if not entered: print("DRIVE_ADMISSION ",JSON.stringify(admission_state(world)))
	world.free()
	await process_frame
	quit(0 if entered else 1)

func admitted(world: Node) -> bool:
	# restore_location publica uma prontidão transitória antes de _place_at_request
	# e do assentamento final. Embarque só pertence ao Main após a cortina sair.
	return world.session != null and world.production != null and world.session.ready_for_play and world.production.ready_for_play and not world.player.input_locked and world.get_node_or_null("LoadingCurtain") == null and root.get_node_or_null("LoadingCurtain") == null

func admission_state(world: Node) -> Dictionary:
	var session = world.get("session")
	var production = world.get("production")
	var player = world.get("player")
	var driving = world.get("driving")
	var candidate: CharacterBody3D = driving.car if driving != null else null
	return {
		"session_ready":session != null and session.ready_for_play,
		"production_ready":production != null and production.ready_for_play,
		"startup_settled":production != null and production.startup_streaming_settled,
		"player_locked":player != null and player.input_locked,
		"curtain_world":world.get_node_or_null("LoadingCurtain") != null,
		"curtain_root":root.get_node_or_null("LoadingCurtain") != null,
		"driving_blocked":session != null and session.blocks_driving_change(),
		"dialogue_open":session != null and session.dialogue_open,
		"modal":session != null and session.modal,
		"rescue_pending":session != null and session.rescue_pending,
		"player_health":world.gameplay.health if world.get("gameplay") != null else -1,
		"car_awaiting_ground":is_instance_valid(candidate) and candidate.has_meta("awaiting_ground"),
		"car_speed":candidate.speed if is_instance_valid(candidate) else 0,
		"car_physics":is_instance_valid(candidate) and candidate.is_physics_processing(),
		"body_transition":driving != null and driving.is_body_transition_active(),
		"paused":paused
	}
