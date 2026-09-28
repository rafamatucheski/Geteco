extends SceneTree
var failures := 0
var checks := 0
var world
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks+=1
	if not ok: failures+=1; push_error(label)
func run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	seed(28092026)
	world=load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	root.add_child(world)
	for frame in 1800:
		await process_frame
		if world.session!=null and world.session.ready_for_play: break
	var ops=world.production.urban_transit.urban_service
	for frame in 180:
		await physics_frame
		if ops.prepared: break
	check(ops.stops.size()==6 and ops.fleet.size()==2,"Service built")
	if failures: quit(1); return
	var bus=ops.fleet[0]
	world.player.teleport(ops.stops[bus.service_stop].inside+Vector3.UP*.05)
	world.player.controlled_automatically=true; world.player.automatic_direction=Vector3.ZERO
	world.session.weather.time_of_day=.35; world.session.weather.set_process(false)
	for frame in 120: await physics_frame
	var ride=world.session.passenger_transport
	if "--diagnostic" in OS.get_cmdline_user_args():
		for p in ops.people:
			if p.stop!=bus.service_stop or not is_instance_valid(p.actor): continue
			var actor=p.actor
			print("DIAG_PERSON ",actor.global_position," direction=",actor.automatic_direction," physics=",actor.is_physics_processing()," floor=",actor.is_on_floor()," velocity=",actor.velocity," target=",ops.stops[p.stop].inside)
			for i in actor.get_slide_collision_count():
				var hit=actor.get_slide_collision(i)
				print("CONTACT ",hit.get_collider().get_path()," normal=",hit.get_normal()," at=",hit.get_position())
			var ray=PhysicsRayQueryParameters3D.create(actor.global_position+Vector3.UP*3,actor.global_position-Vector3.UP,1)
			print("FLOOR ",world.get_world_3d().direct_space_state.intersect_ray(ray))
		var model=world.production.urban_transit.instances[ops.stops[bus.service_stop].definition.id].find_child("StationTerminalModel",true,false)
		print("MODEL ",model.global_transform)
		for child in model.collision_body.get_children():
			if str(child.name).contains("Platform"): print("PLATFORM ",child.global_transform," face=",child.shape.get_faces()[0]," world=",child.global_transform*child.shape.get_faces()[0])
		quit(); return
	print("BOARD_ELIGIBLE ",ride._eligible()," action=",ride.nearest_action()," bus=",bus.active," state=",bus.service_state)
	check(ride.perform("urban_board"),"Player boards the scheduled bus at the platform")
	if failures: quit(1); return
	var westgate_only := "--westgate-only" in OS.get_cmdline_user_args()
	if westgate_only:
		bus.set_active(false)
		bus.service_stop=4; bus.route_distance=ops.stops[4].offset; bus.stop_offset=bus.route_distance
		bus._apply_poses(ops.path_poses.at(bus.route_distance),false)
		world.player.teleport(ops.stops[4].inside)
		world.production._update_physical_residency(world.player.position)
		ops.refresh_presence()
	if DisplayServer.get_name()!="headless":
		world.camera.target_size=38
		for frame in 60: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://evidence/biarticulated/boarding.png")
	var visited := {}
	Engine.time_scale=4; Engine.physics_ticks_per_second=240
	var start:=Time.get_ticks_msec()
	var simulated:=0.0
	var log_at:=0.0
	var obstructed:=0.0
	while simulated<360 and Time.get_ticks_msec()-start<150000:
		await physics_frame
		simulated+=1.0/60.0
		obstructed=obstructed+1.0/60.0 if not bus.blocked_by.is_empty() else 0.0
		if obstructed>15:
			print("BLOCKED_ABORT ",bus.blocked_by)
			var blocker=world.get_node_or_null(bus.blocked_by.split(" @ ")[0])
			if blocker!=null:
				for key in ["archetype","traffic","speed","blocked","blocker","bypass_side","bypass_blend","route_distance","junction_wait"]: print("BLOCKER_DETAIL ",key,"=",blocker.get(key))
				print("BLOCKER_HEADING ",blocker.global_basis," route=",blocker.route.get_meta("traffic_source_ids",[]) if blocker.get("route")!=null else [])
			print("BUS_JUNCTIONS ",bus._junctions," tokens=",bus.junction_tokens)
			for vehicle in world.production.vehicles:
				if not is_instance_valid(vehicle) or vehicle.global_position.distance_to(bus.global_position)>30: continue
				print("NEAR_VEHICLE ",vehicle.get_path()," ",vehicle.archetype," at=",vehicle.global_position," heading=",-vehicle.global_basis.z," traffic=",vehicle.traffic," speed=",vehicle.speed," blocked=",vehicle.blocked," blocker=",vehicle.blocker," bypass=",vehicle.bypass_side,"/",vehicle.bypass_blend," junction=",vehicle.junction_wait," route=",vehicle.route.get_meta("traffic_source_ids",[]) if vehicle.route!=null else [])
			break
		if bus.service_state=="exchange": visited[bus.service_stop]=true
		if simulated>=log_at:
			log_at+=15
			print("BUS_STEP ",snappedf(simulated,.1)," ",bus.service_state," stop=",bus.service_stop," distance=",snappedf(bus.total_travelled,.1)," blocked=",bus.blocked_by," people=",ops.boarded,"/",ops.alighted)
			for p in ops.people:
				if p.stop==bus.service_stop and p.bus==null and is_instance_valid(p.actor): print("PERSON ",p.id," ",p.phase," ",p.actor.global_position," target=",ops.waiting_point(p))
		# Exit at the sixth distinct platform; the separate hull audit covers the
		# closed circuit. Signal phases intentionally remain in real wall time.
		if visited.size()==(2 if westgate_only else 6): ride.request_exit()
		if not ride.riding: break
	check(visited.size()==(2 if westgate_only else 6),"Westgate junction passes with normal traffic" if westgate_only else "All six stops physically served")
	if not westgate_only: check(ops.boarded>0 and ops.alighted>0,"Visible passengers physically board and alight")
	check(not ride.riding and world.player.visible and world.player.collision_layer==2,"Requested exit restores player controls and collision")
	if DisplayServer.get_name()!="headless":
		world.camera.target_size=42
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://evidence/biarticulated/service.png")
	print("BIARTICULATED_SERVICE ",checks," checks ",failures," failures visited=",visited)
	quit(1 if failures else 0)
