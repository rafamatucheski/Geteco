extends SceneTree
## Real drivers and collisions in Main, isolated low demand. Render for visual evidence.
const VEHICLE = preload("res://scripts/Vehicle.gd")
const DATA = preload("res://world/editing/WorldEditData.gd")
var world
var folder := ""
var results := []
var failures := 0
func _initialize(): run.call_deferred()

func extend_road(graph, at: int, first: int, id: String) -> Array[int]:
	var path: Array[int]=[at,first]
	var length: float=graph.vertices[at].distance_to(graph.vertices[first])
	while length<27.0:
		var next: int=-1
		for edge in graph.edges[path[-1]]:
			if edge.id==id and edge.to not in path: next=edge.to;break
		if next<0: break
		length+=graph.vertices[path[-1]].distance_to(graph.vertices[next])
		path.append(next)
	return path

func blockers_at(point: Vector3,yaw: float,id: String) -> Array:
	var vehicle=VEHICLE.new()
	vehicle.archetype=id
	vehicle.position=point
	vehicle.rotation.y=yaw
	world.add_child(vehicle)
	vehicle.set_physics_process(false)
	var query=PhysicsShapeQueryParameters3D.new()
	query.shape=vehicle.shape.shape
	query.transform=vehicle.global_transform*vehicle.shape.transform
	query.collision_mask=7
	query.exclude=[vehicle.get_rid()]
	var found=[]
	for hit in world.get_world_3d().direct_space_state.intersect_shape(query,20): found.append(str(hit.collider.get_path()))
	vehicle.free()
	return found

func run():
	var args=OS.get_cmdline_user_args()
	if "--no-save" not in args or "--no-traffic" not in args: quit(2);return
	var archetype="union_sedan"
	var only=""
	for arg in args:
		if arg.begins_with("--out-dir="): folder=arg.trim_prefix("--out-dir=")
		if arg.begins_with("--vehicle="): archetype=arg.trim_prefix("--vehicle=")
		if arg.begins_with("--only="): only=arg.trim_prefix("--only=")
	if folder.is_empty(): quit(2);return
	DirAccess.make_dir_recursive_absolute(folder)
	var hash_before=DATA.disk_hash()
	seed(29092026)
	root.size=Vector2i(1280,720)
	world=load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	root.add_child(world);current_scene=world
	var start=Time.get_ticks_msec()
	while Time.get_ticks_msec()-start<60000:
		await process_frame
		if world.session!=null and world.session.ready_for_play: break
	if world.session==null or not world.session.ready_for_play: quit(3);return
	world.player.controlled_automatically=true
	world.player.automatic_direction=Vector3.ZERO
	world.session.cold.set_process(false)
	world.camera.set_process_unhandled_input(false)
	world.camera.heading=0;world.camera.target_size=48
	world.session.weather.time_of_day=.35
	world.session.weather.weather_state=0
	world.session.weather._update();world.session.weather.set_process(false)
	for spec in [
		["mountain_pass","mountain_track_2",Vector3(703,0,-329)],
		["mountain_pass","mountain_track_4",Vector3(697,0,-466)],
		["mountain_pass","mountain_track_5",Vector3(687,0,-412)],
		["island_esplanade","northbank_gateway_avenue",Vector3(291,0,-121)],
		["warehouse_way","medical_garden_lane",Vector3(100,0,100)]
	]:
		if not only.is_empty() and not only.begins_with(spec[1]):continue
		world.player.teleport(spec[2]+Vector3(0,.15,10))
		world.production._update_physical_residency(spec[2])
		for i in 120: await physics_frame
		var graph=world.production.traffic_routes
		var junction=-1
		var incoming=-1
		var outgoing=-1
		for at in graph.edges:
			incoming=-1;outgoing=-1
			for edge in graph.edges[at]:
				if edge.id==spec[0]: incoming=edge.to
				if edge.id==spec[1]: outgoing=edge.to
			if incoming>=0 and outgoing>=0: junction=at;break
		if junction<0:
			failures+=1;results.append({"id":spec[1],"error":"No junction"});continue
		var center: Vector3=graph.vertices[junction]
		var path=extend_road(graph,junction,incoming,spec[0])
		path.reverse()
		var tail=extend_road(graph,junction,outgoing,spec[1]);tail.pop_front();path.append_array(tail)
		for reverse in [false,true]:
			var label=spec[1]+("_return" if reverse else "_enter")
			if not only.is_empty() and only!=spec[1] and only!=label:continue
			var nodes: Array[int]=path.duplicate()
			if reverse:nodes.reverse()
			var route: Curve3D=graph._curve(nodes,false)
			route.set_meta("traffic_open",true)
			# A driveway can finish at a pedestrian storefront. Test its vehicle
			# approach, keeping the starting body clear of that terminal doorway.
			var start_offset=8.0 if reverse else 1.0
			var point=route.sample_baked(start_offset,true)+Vector3.UP*.12
			var direction=route.sample_baked(start_offset+.5,true)-route.sample_baked(start_offset,true)
			var yaw=atan2(-direction.x,-direction.z)
			world.player.teleport(point+Vector3(0,0,12))
			world.production._update_physical_residency(point)
			# Admit each point in its owning region. Building a Harbor chunk at a
			# mountain coordinate makes its later eviction suspend the nearby car.
			for location in [point,center]:
				var region_id=preload("res://world/regions/WorldConnection3D.gd").logical_region(location)
				if world.production.regions.has(region_id):world.production.regions[region_id].prepare_collision_at(location)
			for i in 30: await physics_frame
			var car=world.production.spawn_vehicle(archetype,point,yaw)
			if car==null:
				failures+=1
				var row={"id":label,"error":"Spawn refused","position":str(point),"blockers":blockers_at(point,yaw,archetype)}
				results.append(row);print("ROAD_DRIVE ",row);continue
			car.vehicle_id="road_validation_"+label
			car.route=route;car.route_distance=start_offset;car.traffic=true
			var target=minf(route.get_baked_length()-2.5,route.get_closest_offset(center)+14.0)
			var trace=[]
			var last_sample=0
			var last_shot=0
			var shot=0
			var reached=false
			start=Time.get_ticks_msec()
			var timeout_ms=int(1000.0*(route.get_baked_length()/2.2+32.0))
			while Time.get_ticks_msec()-start<timeout_ms:
				await physics_frame
				if not is_instance_valid(car):break
				world.player.global_position=car.global_position+car.global_basis.x*14
				world.production._update_physical_residency(car.global_position)
				var elapsed=Time.get_ticks_msec()-start
				if elapsed-last_sample>=250:
					last_sample=elapsed
					var contacts=[]
					for ci in car.get_slide_collision_count():
						var contact=car.get_slide_collision(ci)
						contacts.append({"node":str(contact.get_collider().get_path()),"normal":str(contact.get_normal()),"depth":contact.get_depth()})
					var sample={"ms":elapsed,"position":str(car.global_position),"progress":car.route_distance,"speed":car.speed,"floor":car.is_on_floor(),"blocker":str(car.blocker.get_path()) if is_instance_valid(car.blocker) else "","health":car.health,"contacts":contacts,"velocity":str(car.velocity),"junction_wait":car.junction_wait,"junction_gap":car.junction_gap}
					sample.physics=car.is_physics_processing();sample.awaiting_ground=car.has_meta("awaiting_ground")
					trace.append(sample)
					if elapsed%2000<300: print("DRIVE_TRACE ",label," ",sample)
				if DisplayServer.get_name()!="headless" and elapsed-last_shot>=2000:
					last_shot=elapsed;shot+=1
					await RenderingServer.frame_post_draw
					root.get_texture().get_image().save_png(folder+"/"+label+"_%02d.png"%shot)
				if car.route_distance>=target: reached=true;break
			var row={"id":label,"vehicle":archetype,"reached":reached,"trace":trace,"length":route.get_baked_length(),"target":target,"elapsed_ms":Time.get_ticks_msec()-start,"position":str(car.global_position) if is_instance_valid(car) else "despawned"}
			results.append(row)
			FileAccess.open(folder+"/progress.json",FileAccess.WRITE).store_string(JSON.stringify(results,"\t"))
			print("ROAD_DRIVE ",label," reached=",reached," pos=",row.position," ms=",row.elapsed_ms)
			if not reached:failures+=1
			if is_instance_valid(car):world.production.vehicles.erase(car);car.queue_free()
			await physics_frame
	FileAccess.open(folder+"/results.json",FileAccess.WRITE).store_string(JSON.stringify({"map_hash":hash_before,"map_unchanged":hash_before==DATA.disk_hash(),"seed":29092026,"vehicle":archetype,"failures":failures,"results":results},"\t"))
	print("ROAD_DRIVE_DONE failures=",failures)
	world.queue_free();await process_frame
	quit(1 if failures else 0)
