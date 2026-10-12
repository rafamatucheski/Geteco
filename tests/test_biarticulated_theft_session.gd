extends "res://tests/measure/measure.gd"
## Main + production interaction, temporary snapshot files only, finite rendered sample.
var checks := 0
var failures := 0
var folder := "res://evidence/biarticulated/theft-20261010"
func check(ok: bool, label: String) -> void:
	checks+=1
	if not ok: failures+=1; push_error(label)
func photo(label: String) -> void:
	if DisplayServer.get_name()=="headless": return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(folder+"/"+label+".png")
func wait_body() -> void:
	var deadline := Time.get_ticks_msec()+16000
	while world.driving.is_body_transition_active() and Time.get_ticks_msec()<deadline: await process_frame
	check(not world.driving.is_body_transition_active(),"Body transition completes within 16 seconds")
func probe_landing(bus) -> void:
	var space: PhysicsDirectSpaceState3D=world.get_world_3d().direct_space_state
	var capsule := CapsuleShape3D.new(); capsule.radius=.32; capsule.height=1.72
	for lateral in [.2,.5,.9,1.3]:
		for back in [1.25,1.8,2.4,-1.25,-1.8,-2.4]:
			var point: Vector3=bus.driver_door_anchor(1)+bus.global_basis.z*back+bus.global_basis.x*lateral
			var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(point+Vector3.UP*2,point-Vector3.UP*4,1,[bus.get_rid()]))
			if hit.is_empty(): print("LANDING_PROBE ",lateral," ",back," no floor"); continue
			point.y=hit.position.y+.04
			var query := PhysicsShapeQueryParameters3D.new(); query.shape=capsule
			query.transform=Transform3D(Basis.IDENTITY,point+Vector3.UP*.9); query.collision_mask=7; query.exclude=[bus.get_rid(),world.player.get_rid()]
			var hits := space.intersect_shape(query,3)
			var blockers := []
			for block in hits: blockers.append(str(block.collider.get_path()))
			print("LANDING_PROBE ",lateral," ",back," point=",point," floor=",hit.collider.get_path()," blockers=",blockers)
func run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	create_timer(300).timeout.connect(func(): push_error("BIARTICULATED_THEFT_SESSION timeout"); quit(2))
	for action in InputMap.get_actions(): InputMap.action_erase_events(action)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	root.size=Vector2i(1280,720)
	world=load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true); root.add_child(world); current_scene=world
	while world.session==null or not world.session.ready_for_play: await process_frame
	check(world.production.no_save,"User saves are isolated")
	var ops=world.production.urban_transit.urban_service
	while not ops.prepared: await physics_frame
	var bus=ops.fleet[0]
	ops.set_physics_process(false)
	for other in ops.fleet: other.set_active(false)
	bus.service_stop=1; bus.route_distance=ops.stops[1].offset
	bus._apply_poses(ops.path_poses.at(bus.route_distance),false)
	bus.service_state="exchange"; bus.dwell=1000; bus.speed=0; bus.set_doors(1)
	world.player.controlled_automatically=true; world.player.automatic_direction=Vector3.ZERO
	world.player.teleport(bus.driver_door_anchor(1)+Vector3.UP*.45)
	world.production._update_physical_residency(world.player.position)
	world.camera.target=bus; world.camera.target_size=30; world.camera.initialized=false
	world.camera.set_process_unhandled_input(false)
	world.session.weather.time_of_day=.35; world.session.weather.weather_state=0
	world.session.weather._update(); world.session.weather.set_process(false)
	ops.refresh_presence(); bus.set_active(true)
	ops.gate(bus.service_stop,true)
	for frame in 120: await physics_frame
	var person: Dictionary=ops.people[0]
	person.bus=bus; person.phase="aboard"; ops.hide_person(person)
	if not bus.passengers.has(person): bus.passengers.append(person)
	ops.set_physics_process(true)
	await photo("before")
	if "--landing-probe" in OS.get_cmdline_user_args(): probe_landing(bus); quit(); return
	print("BUS_THEFT_ENTRY point=",world.player.global_position," door=",bus.driver_door_anchor(1)," option=",world.driving._entry_option()," landing=",preload("res://gameplay/VehicleCarjacking.gd").landing_point(world,bus,1)," active=",bus.active," aboard=",bus.player_aboard)
	check(world.driving.interact(),"F interaction steals the real scheduled bus")
	if not world.driving.occupied: quit(1); return
	check(bus.stolen and world.driving.car==bus,"Driving and service agree on the new owner")
	var body=world.driving.transition
	check(is_instance_valid(body) and body.carjacking!=null,"The shared driver extraction runs before control")
	var victim=body.carjacking.victim if is_instance_valid(body) and body.carjacking!=null else null
	await wait_body()
	check(bus.controlled and not bus.traffic and world.player.seated,"Dante becomes the seated driver")
	check(is_instance_valid(victim) and victim.visible and victim.collision_layer==2,"The expelled driver remains a physical pedestrian")
	check(person.bus==null and bus.passengers.is_empty(),"Passengers leave the stolen service vehicle")
	check(ops.boardable_bus()!=bus,"The bus no longer sells passenger boarding")
	await photo("seated")
	var began := Time.get_ticks_usec()
	var quick := "--quick" in OS.get_cmdline_user_args()
	var last := began
	var frames: Array[float]=[]
	var start: Vector3=bus.global_position
	Input.action_press("accelerate")
	while Time.get_ticks_usec()-began<(12000000 if quick else 38000000):
		await process_frame
		var now := Time.get_ticks_usec()
		var seconds := (now-began)/1000000.0
		if seconds>2 and seconds<3: Input.action_press("move_right",.35)
		else: Input.action_release("move_right")
		if seconds>=8: frames.append((now-last)/1000.0)
		last=now
	Input.action_release("accelerate"); Input.action_release("move_right")
	Input.action_press("handbrake")
	for frame in 180: await physics_frame
	Input.action_release("handbrake")
	check(bus.global_position.distance_to(start)>2,"Real driving input moves the articulated bus")
	check(bus.distance_travelled>2,"Driven distance is accounted for")
	if DisplayServer.get_name()!="headless" and not quick:
		var report := {"summary":stats(frames),"frames_ms":frames,"gpu":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),"resolution":str(root.size),"vsync":DisplayServer.window_get_vsync_mode(),"max_fps":Engine.max_fps,"distance_m":bus.distance_travelled,"scenario":"38 seconds of player input, including 8-second warmup; collisions remain active"}
		FileAccess.open(folder+"/performance.json",FileAccess.WRITE).store_string(JSON.stringify(report))
		print("BUS_THEFT_PERF ",report.summary)
	await photo("driven")
	var record: Dictionary=preload("res://runtime/FleetState.gd").capture(bus,"harbor")
	check(preload("res://runtime/FleetState.gd").validate(record),"The real stolen bus produces a valid fleet save")
	var parked: Transform3D=bus.global_transform
	check(world.driving.leave(),"Dante can exit the stolen bus")
	await wait_body()
	check(not world.driving.occupied and world.player.visible and world.player.collision_layer==2,"Exit restores pedestrian control and collision")
	await photo("exited")
	world.production.state.place_id="test_interior"; ops.refresh_presence()
	check(not bus.active and bus.sections.all(func(section): return section.collision_layer==0),"Suspension removes all three collision bodies")
	world.production.state.place_id=""; ops.refresh_presence()
	if not bus.active:
		print("BUS_RESTORE_BLOCKED ",bus.blocked_by," player=",world.player.global_position," bus=",bus.global_position," awaiting=",bus.has_meta("awaiting_ground")," region=",bus.get_meta("region_id",""))
		var deadline := Time.get_ticks_msec()+12000
		while not bus.active and Time.get_ticks_msec()<deadline: await physics_frame; ops.refresh_presence()
	check(bus.active and bus.stolen and bus.global_transform==parked,"Return keeps the stolen pose instead of snapping to the route")
	world.player.teleport(bus.driver_door_anchor(1)+Vector3.UP*.04)
	await physics_frame
	check(world.driving.interact(),"The parked stolen bus remains available for re-entry")
	await wait_body()
	check(bus.controlled and world.driving.car==bus,"Re-entry restores the same articulated identity")
	print("BIARTICULATED_THEFT_SESSION ",checks," checks ",failures," failures")
	world.driving.cancel_transition("test_cleanup")
	world.queue_free(); await process_frame
	quit(1 if failures else 0)
