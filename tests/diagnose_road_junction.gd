extends SceneTree
var world
var rows=[]
func _initialize():run.call_deferred()
func run():
	if "--no-save" not in OS.get_cmdline_user_args():quit(2);return
	var folder=""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out-dir="):folder=arg.trim_prefix("--out-dir=")
	if folder.is_empty():quit(2);return
	DirAccess.make_dir_recursive_absolute(folder)
	seed(29092026)
	world=load("res://Main.tscn").instantiate();world.set_meta("skip_arrival",true)
	root.add_child(world);current_scene=world
	var start=Time.get_ticks_msec()
	while Time.get_ticks_msec()-start<60000:
		await process_frame
		if world.session!=null and world.session.ready_for_play:break
	if world.session==null or not world.session.ready_for_play:quit(3);return
	world.player.controlled_automatically=true;world.player.automatic_direction=Vector3.ZERO
	world.player.collision_layer=0;world.session.cold.set_process(false)
	var focus=Vector3(182,.15,83)
	world.player.teleport(focus+Vector3(-12,0,-12));world.production._update_physical_residency(focus)
	world.session.weather.time_of_day=.35;world.session.weather.weather_state=0
	world.session.weather._update();world.session.weather.set_process(false)
	world.camera.set_process_unhandled_input(false);world.camera.heading=0;world.camera.target_size=72;world.camera.initialized=false
	if "--probe-bays" in OS.get_cmdline_user_args():
		for i in 180:await physics_frame
		var rank=world.session.passenger_transport.taxis.rank
		print("BAY_CARS ",rank.cars.keys()," DRIVERS ",rank.drivers.keys())
		var shape=BoxShape3D.new();shape.size=Vector3(2.1,1.7,4.78)
		var query=PhysicsShapeQueryParameters3D.new();query.shape=shape;query.collision_mask=1
		for x in range(145,178):
			for z in [73.0]:
				query.transform=Transform3D(Basis(Vector3.UP,PI/2),Vector3(x,.16+.85,z))
				var hits=[]
				for hit in world.get_world_3d().direct_space_state.intersect_shape(query,20):hits.append({"node":str(hit.collider.get_path()),"position":str(hit.collider.global_position)})
				print("BAY_PROBE ",Vector3(x,.16,z)," ",hits)
		world.queue_free();await process_frame;quit();return
	start=Time.get_ticks_msec()
	var next=0
	var last_shot=0
	while Time.get_ticks_msec()-start<95000:
		await physics_frame
		var elapsed=Time.get_ticks_msec()-start
		if elapsed<next:continue
		next=elapsed+1000
		if DisplayServer.get_name()!="headless" and elapsed-last_shot>=5000:
			last_shot=elapsed
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(folder+"/traffic_%03d.png"%int(elapsed/1000))
		for car in world.production.vehicles:
			if not is_instance_valid(car) or not car.traffic or car.global_position.distance_to(focus)>40:continue
			var row={"ms":elapsed,"id":car.get_instance_id(),"position":str(car.global_position),"yaw":car.rotation.y,"speed":car.speed,"physics":car.is_physics_processing(),"awaiting":car.has_meta("awaiting_ground"),"wait":car.junction_wait,"blocked":car.blocked,"stall":car.stall_time,"stuck":car.stuck_time,"controlled":car.controlled,"external":car.external_input,"health":car.health,"progress":car.route_distance,"blocker":str(car.blocker.get_path()) if is_instance_valid(car.blocker) else ""}
			if car.route!=null:
				row.length=car.route.get_baked_length();row.open=car.route.get_meta("traffic_open",false)
				row.exit_wait=car._exit_wait;row.exit_blocked=car._exit_blocked;row.held=str(car._held_junction);row.gap=car.junction_gap
				row.junctions=[]
				for junction in car._junction_list:
					var ahead=car._route_ahead(junction.offset,row.length,row.open)
					if ahead < -7 or ahead > 35:continue
					var before=car.route.sample_baked(junction.offset-6 if row.open else fposmod(junction.offset-6,row.length),true)
					var at=car.route.sample_baked(junction.offset-1 if row.open else fposmod(junction.offset-1,row.length),true)
					var heading:Vector3=junction.get("heading",at-before)
					var detail={"key":str(junction.key),"ahead":ahead,"offset":junction.offset,"state":car.JUNCTIONS.signal_state(junction.key,heading),"owners":str(car.JUNCTIONS.owners.get(junction.key,{})),"heading":str(heading),"old_tangent":str(at-before)}
					var exit_at=junction.offset+7+car.half_length+1
					var right=car._route_right(exit_at,row.length,row.open)
					var query=PhysicsShapeQueryParameters3D.new();query.shape=car.rotation_shape;query.collision_mask=4;query.exclude=[car.get_rid()]
					query.transform=Transform3D(Basis(Vector3.UP,atan2(-right.z,right.x)),car._route_point(exit_at,row.length,row.open)+Vector3.UP*car.shape.position.y)
					detail.exit_hits=[]
					for hit in world.get_world_3d().direct_space_state.intersect_shape(query,4):detail.exit_hits.append({"node":str(hit.collider.get_path()),"vehicle_id":hit.collider.get("vehicle_id"),"position":str(hit.collider.global_position),"speed":car._body_speed(hit.collider)})
					row.junctions.append(detail)
				if car._exit_blocked:
					row.nearby=[]
					for other in get_nodes_in_group("drivable"):
						if other is Node3D and other.global_position.distance_to(car.global_position)<35:row.nearby.append({"node":str(other.get_path()),"position":str(other.global_position),"speed":other.get("speed")})
				row.roads=car.route.get_meta("traffic_source_ids",[])
				row.next=str(car.route.sample_baked(car.route_distance+3,true))
			if is_instance_valid(car.blocker) and car.blocker is Node3D:row.blocker_position=str(car.blocker.global_position)
			if is_instance_valid(car.blocker) and car._is_vehicle(car.blocker):row.blocker_vehicle_id=car.blocker.get("vehicle_id")
			row.contacts=[]
			for i in car.get_slide_collision_count():
				var hit=car.get_slide_collision(i)
				row.contacts.append({"node":str(hit.get_collider().get_path()),"normal":str(hit.get_normal())})
			rows.append(row)
			if elapsed>45000 and absf(car.speed)<.2:print("JUNCTION_STALLED ",row)
	FileAccess.open(folder+"/trace.json",FileAccess.WRITE).store_string(JSON.stringify(rows,"\t"))
	print("JUNCTION_DIAG_DONE samples=",rows.size())
	var rank=world.session.passenger_transport.taxis.rank
	print("TAXI_RANK_FINAL cars=",rank.cars.size()," drivers=",rank.drivers.size()," slots=",rank.SLOTS)
	world.queue_free();await process_frame;quit()
