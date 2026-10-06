extends "res://tests/test_mining_session.gd"
## Focused real-Main visual regression capture after cutting the persistent
## desert backdrop. Physics support and visible composition are recorded apart.
func _initialize() -> void:
	create_timer(180).timeout.connect(func(): push_error("MINING_REPAIR timeout"); finish(3))
	run.call_deferred()

func run() -> void:
	if DisplayServer.get_name()=="headless" or "--no-save" not in OS.get_cmdline_user_args(): finish(2); return
	seed(6102026)
	root.size=Vector2i(1280,720)
	output=FIXTURE.output_dir("mining-visual-repair")
	var start:=LAYOUT.SECRET_ENTRY+Vector3.UP*.08
	var snapshot:=FIXTURE.full_snapshot(start,true)
	snapshot.region_id="desert"
	snapshot.world.pedestrian={"region":"desert","position":[start.x,start.y,start.z]}
	var path:=FIXTURE.write_fixture(output,"checkpoint.json",snapshot)
	world=load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	world.set_meta("menu_save_path",path)
	root.add_child(world); current_scene=world
	for i in 4800:
		await physics_frame
		if world.session!=null and world.session.ready_for_play and world.production.startup_streaming_settled: break
	if not check(world.session!=null and world.session.ready_for_play and world.production.store.path==path,"Main ready with isolated fixture"): finish(1); return
	world.dispatch.router.nearest_edge(start)
	check(world.dispatch.router._native!=null,"compiled native routing")
	if world.session.modal: world.session.close_menu()
	world.player.controlled_automatically=true
	world.player.automatic_direction=Vector3.ZERO
	world.session.weather.weather_state=0
	world.session.weather.weather_timer=3600
	var setups: Array[Dictionary]=[
		{"id":"secret-entrance-day","point":start,"hour":.45},
		{"id":"pit-machines-day","point":LAYOUT.CENTER+Vector3(29,-27.92,-20),"hour":.45},
		{"id":"pit-machines-night","point":LAYOUT.CENTER+Vector3(7,-27.92,-22),"hour":.9},
	]
	if "--overview-only" in OS.get_cmdline_user_args(): setups=[]
	for setup in setups:
		world.production.region.set_focus(setup.point)
		world.production.region.prepare_collision_at(setup.point)
		world.player.teleport(setup.point)
		world.camera.initialized=false
		world.session.weather.time_of_day=setup.hour
		world.session.weather._update()
		await create_timer(4).timeout
		var at: Vector3=world.player.global_position
		var ray:=PhysicsRayQueryParameters3D.create(at+Vector3.UP*.2,at-Vector3.UP*.3,1)
		var hit: Dictionary=world.get_world_3d().direct_space_state.intersect_ray(ray)
		check(not hit.is_empty() and world.gameplay.health>0,"physical support below datum "+str(setup.id))
		print("MINING_VISUAL_PHYSICS ",JSON.stringify({"id":setup.id,"player":str(at),"camera":str(world.camera.global_position),"floor":str(hit.get("position",Vector3.INF))}))
		var dust: Dictionary=world.production.region.mining_dust.debug_snapshot()
		check(bool(dust.active) and int(dust.particle_capacity)==64 and dust.ground_y.x< -20,"light sand uses the excavated floor "+str(setup.id))
		print("MINING_VISUAL_DUST ",JSON.stringify({"id":setup.id,"snapshot":dust}))
		await photo(setup.id)
	world.session.weather.time_of_day=.45
	world.session.weather._update()
	# Full-site diagnostic framing exceeds normal gameplay streaming and the
	# 180 m gameplay far plane; admit that explicit composition before capture.
	world.production.region.set_retention_radius(2)
	for x in range(floori(LAYOUT.BOUNDS.position.x/96),ceili(LAYOUT.BOUNDS.end.x/96)):
		for z in range(floori(LAYOUT.BOUNDS.position.y/96),ceili(LAYOUT.BOUNDS.end.y/96)):
			world.production.region.prepare_collision_at(Vector3((float(x)+.5)*96,0,(float(z)+.5)*96))
	for i in 900:
		await physics_frame
		if world.production.region.is_streaming_idle(): break
	world.camera.set_process(false)
	world.camera.size=280
	world.camera.far=600
	world.camera.position=Vector3(-180,200,-1590)
	world.camera.look_at(Vector3(-180,-8,-1750))
	await photo("overview-diagnostic")
	finish(0 if failures.is_empty() else 1)
