extends SceneTree
var world
var failures := 0
var checks := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok: failures+=1; push_error(label)
func run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	var hash := preload("res://world/editing/WorldEditData.gd").disk_hash()
	seed(27092026)
	world=load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	root.add_child(world)
	for frame in 1800:
		await process_frame
		if world.session!=null and world.session.ready_for_play: break
	check(world.session!=null and world.session.ready_for_play,"Actual Main starts")
	if failures: world.free(); quit(1); return
	Engine.time_scale=3
	Engine.physics_ticks_per_second=180
	for spec in [["market_street","quay_boulevard"],["medical_garden_lane","warehouse_way"]]:
		var graph=world.production.traffic_routes
		var path: Array[int]=[]
		for at in graph.edges:
			var incoming := -1
			var outgoing := -1
			for edge in graph.edges[at]:
				if edge.id==spec[0] and graph.vertices[edge.to].x<graph.vertices[at].x: incoming=edge.to
				if edge.id==spec[1] and graph.vertices[edge.to].z>graph.vertices[at].z: outgoing=edge.to
			if incoming>=0 and outgoing>=0: path=[incoming,at,outgoing]; break
		check(path.size()==3,"Connected turn available: "+spec[0])
		if path.is_empty(): continue
		var center: Vector3=graph.vertices[path[1]]
		world.player.teleport(center+Vector3(-10,.1,-10))
		world.player.controlled_automatically=true
		world.player.automatic_direction=Vector3.ZERO
		world.production._update_physical_residency(world.player.position)
		for frame in 180: await physics_frame
		var route: Curve3D=graph._curve(path,false)
		route.set_meta("traffic_open",true)
		var crossing := route.get_closest_offset(center)
		var start := maxf(0,crossing-12)
		var point := route.sample_baked(start,true)
		var ahead := route.sample_baked(start+.5,true)-point
		var car=world.production.spawn_vehicle("union_sedan",point+Vector3.UP*.12,atan2(-ahead.x,-ahead.z))
		check(car!=null,"Car spawns on edited lane: "+spec[0])
		if car==null: continue
		car.route=route
		car.route_distance=start
		car.traffic=true
		var began := Time.get_ticks_msec()
		var target := minf(route.get_baked_length()-2,crossing+8)
		while Time.get_ticks_msec()-began<45000 and car.route_distance<target:
			await physics_frame
		var blocker := str(car.blocker.get_path()) if is_instance_valid(car.blocker) else ""
		print("EDITED_DRIVE ",spec," position=",car.position," progress=",car.route_distance," target=",target," blocker=",blocker)
		check(car.route_distance>=target,"Physical car passes repaired intersection: "+spec[0])
		car.free()
	check(preload("res://world/editing/WorldEditData.gd").disk_hash()==hash,"Saved map untouched")
	world.free()
	print("EDITED_DRIVE ",checks," checks ",failures," failures")
	quit(1 if failures else 0)
