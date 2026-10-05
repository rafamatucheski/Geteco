extends SceneTree
## Production scene, isolated save; baseline and final use identical cameras/time.
var world
var folder := "res://evidence/classic-meet/baseline"
var failures: Array[String] = []
var validate := false
var motion := false
const CENTER := Vector3(420,0,124)

func _initialize() -> void: run.call_deferred()

func run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): folder=arg.trim_prefix("--out=")
	validate="--validate" in OS.get_cmdline_user_args()
	motion="--motion" in OS.get_cmdline_user_args()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	create_timer(240).timeout.connect(func(): quit(3))
	seed(420124)
	root.size=Vector2i(1280,720)
	world=load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	root.add_child(world)
	current_scene=world
	while world.session==null or not world.session.ready_for_play: await process_frame
	if not ClassDB.class_exists(&"CSharpScript") or world.dispatch.router._native_graph()==null:
		push_error("Classic meet validation requires the compiled C# runtime")
		quit(2)
		return
	if "--without-meet" in OS.get_cmdline_user_args():
		var site=world.find_child("TorqueClassicMeetSite",true,false)
		if site!=null: site.queue_free()
	world.player.teleport(Vector3(420,.1,120))
	world.player.controlled_automatically=true
	world.player.automatic_direction=Vector3.ZERO
	world.session.state.world_state.moon_day=1
	world.camera.heading=0
	world.camera.target_size=32
	world.camera.size=32
	world.camera.initialized=false
	world.session.weather.weather_timer=100000
	world.session.weather.weather_state=0
	await create_timer(12).timeout
	var settling:=Time.get_ticks_msec()
	while "--capture-only" not in OS.get_cmdline_user_args() and world.people.size()<world.production._population_cap() and Time.get_ticks_msec()-settling<45000:
		await create_timer(.5).timeout
	for phase in ["day","night"]:
		world.session.weather.time_of_day=.5 if phase=="day" else 21.0/24.0
		world.session.weather._update()
		await create_timer(6).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(folder.path_join(phase+".png"))
		if "--capture-only" not in OS.get_cmdline_user_args(): await measure(phase)
		if validate: await validate_phase(phase)
		if "--capture-only" in OS.get_cmdline_user_args():
			world.camera.heading=3.6
			await create_timer(2).timeout
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(folder.path_join(phase+"-front.png"))
			world.camera.heading=0
	if motion: await capture_motion()
	elif "--hero" in OS.get_cmdline_user_args(): await capture_hero()
	if "--light-diagnose" in OS.get_cmdline_user_args(): await diagnose_lights()
	if validate: await validate_lifecycle()
	print("CLASSIC_MEET_DONE failures=",failures)
	quit(0 if failures.is_empty() else 1)

func measure(phase: String) -> void:
	var samples: Array[float]=[]
	var cpu: Array[float]=[]
	var physics: Array[float]=[]
	var begin:=Time.get_ticks_usec()
	var last:=begin
	while Time.get_ticks_usec()-begin<30000000:
		await process_frame
		var now:=Time.get_ticks_usec()
		samples.append(float(now-last)/1000.0)
		last=now
		cpu.append(Performance.get_monitor(Performance.TIME_PROCESS)*1000.0)
		physics.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000.0)
	var sorted:=samples.duplicate()
	sorted.sort()
	var report: Dictionary={"phase":phase,"seconds":float(last-begin)/1000000.0,"frames":samples.size(),"fps":samples.size()*1000000.0/(last-begin),"p50_ms":sorted[int(sorted.size()*.5)],"p95_ms":sorted[int(sorted.size()*.95)],"p99_ms":sorted[int(sorted.size()*.99)],"max_ms":sorted.back(),"over33":samples.filter(func(v):return v>33.3).size(),"over66":samples.filter(func(v):return v>66.7).size(),"renderer":RenderingServer.get_current_rendering_method(),"gpu":RenderingServer.get_video_adapter_name(),"engine":Engine.get_version_info().string,"resolution":str(root.size),"vsync":DisplayServer.window_get_vsync_mode(),"max_fps":Engine.max_fps,"people":world.people.size(),"vehicles":world.production.vehicles.size(),"camera":str(world.camera.global_transform),"player":str(world.player.global_position),"router_native":world.dispatch.router.get("_native")!=null,"samples_ms":samples,"cpu_ms":cpu,"physics_ms":physics}
	FileAccess.open(folder.path_join(phase+"-frames.json"),FileAccess.WRITE).store_string(JSON.stringify(report))
	for key in ["samples_ms","cpu_ms","physics_ms"]: report.erase(key)
	print("CLASSIC_MEET_REPORT ",JSON.stringify(report))

func capture_hero() -> void:
	world.camera.set_preview_view(false)
	world.camera.heading=3.6
	await create_timer(2).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(folder.path_join("night-front.png"))

func capture_motion() -> void:
	await capture_hero()
	var stamps: Array[Dictionary]=[]
	var begin:=Time.get_ticks_usec()
	var frame:=0
	while Time.get_ticks_usec()-begin<30000000:
		await RenderingServer.frame_post_draw
		var elapsed:=float(Time.get_ticks_usec()-begin)/1000000.0
		# Static camera, then rotation and a short physical walk along the clear aisle.
		world.camera.heading=PI+(sin((elapsed-8)*.32)*.6 if elapsed>8 else 0.0)
		world.player.automatic_direction=Vector3(0,0,1) if elapsed>=18 and elapsed<20 else (Vector3(0,0,-1) if elapsed>=22 and elapsed<24 else Vector3.ZERO)
		root.get_texture().get_image().save_jpg(folder.path_join("motion-%05d.jpg"%frame),.78)
		var probes: Array=[]
		for point in [Vector3(417,.055,121.4),Vector3(425,.055,125),Vector3(411,.055,125),Vector3(425,.055,112.5)]:
			var pixel: Vector2=world.camera.unproject_position(point)
			probes.append([pixel.x,pixel.y])
		stamps.append({"frame":frame,"drawn_frame":Engine.get_frames_drawn(),"us":Time.get_ticks_usec()-begin,"floor_probes":probes,"sun_energy":world.production.sun.light_energy,"sun_color":str(world.production.sun.light_color),"sun_transform":str(world.production.sun.global_transform),"ambient":world.production.environment.environment.ambient_light_energy})
		frame+=1
	world.player.automatic_direction=Vector3.ZERO
	FileAccess.open(folder.path_join("motion-frames.json"),FileAccess.WRITE).store_string(JSON.stringify(stamps))

func check(ok: bool, label: String) -> void:
	print(("PASS " if ok else "FAIL ")+label)
	if not ok: failures.append(label)

func validate_phase(phase: String) -> void:
	var meet=world.session.urban_operations.classic_meet
	check(is_instance_valid(meet) and meet.active,"Meet is integrated and nearby")
	if not is_instance_valid(meet): return
	if phase=="day":
		check(meet.mode=="day" and meet.cars.size()==2 and meet.guests.size()==2,"Day has two ordinary parked cars and two shoppers")
		if meet.guests.size()==2:
			var first: Vector3=meet.guests[0].global_position
			await create_timer(2).timeout
			check(first.distance_to(meet.guests[0].global_position)>.5,"Daytime shopper actually walks")
	else:
		check(meet.mode=="meet" and meet.cars.size()==6 and meet.guests.size()==6,"Night has six exhibition cars and six people")
		var models: Dictionary = {}
		for car in meet.cars: models[car.model_id]=true
		check(models.size()==6,"Exhibition has six distinct car silhouettes")
		check(meet.cars.filter(func(c):return c.hood_open).size()==3,"Three open hoods")
		check(meet.cars.filter(func(c):return c.neon.a>0).size()==2,"Two neon cars")
		for guest in meet.guests:
			var shape:=PhysicsShapeQueryParameters3D.new()
			var capsule:=CapsuleShape3D.new()
			capsule.radius=.29
			capsule.height=1.65
			shape.shape=capsule
			shape.transform.origin=guest.global_position+Vector3.UP*.86
			shape.collision_mask=1
			check(world.get_world_3d().direct_space_state.intersect_shape(shape,1).is_empty(),"Guest is clear of real-world solids: "+guest.name)
			check(absf(guest.global_position.y)<.15,"Guest stands on ground: "+guest.name)

func validate_lifecycle() -> void:
	var meet=world.session.urban_operations.classic_meet
	var ids: Array=meet.guests.map(func(g):return g.get_instance_id())
	world.player.teleport(Vector3(320,.1,149))
	await create_timer(1).timeout
	check(not meet.active and meet.guests.all(func(g):return not g.is_visible_in_tree() and g.process_mode==Node.PROCESS_MODE_DISABLED),"Leaving suspends guests, models and lights")
	# Reenter directly in a parked-car footprint: activation must wait safely.
	world.player.teleport(Vector3(413,.1,114.5))
	await create_timer(1).timeout
	check(not meet.active,"Reentry cannot reactivate a car on top of the player")
	world.player.teleport(Vector3(420,.1,120))
	await create_timer(1).timeout
	check(meet.active and ids==meet.guests.map(func(g):return g.get_instance_id()),"Return reuses the same six people without duplication")
	world.session.state.world_state.moon_day=2
	world.session.weather.time_of_day=.5/24.0
	await create_timer(.6).timeout
	check(meet.event_active and ids==meet.guests.map(func(g):return g.get_instance_id()),"Midnight keeps Tuesday's encounter alive")
	# Real save-store roundtrip uses an isolated output file.
	world.session.state.world_state.time=world.session.weather.time_of_day
	var store=preload("res://runtime/SaveStore.gd").new()
	store.path=folder.path_join("isolated-progress.json")
	check(store.save(world.session.state)==OK,"Meet calendar can be saved to isolated storage")
	var restored=preload("res://runtime/GameState.gd").new()
	check(store.load_into(restored).get("ok",false) and int(restored.world_state.get("moon_day",-1))==2,"Persisted day/time restore across midnight")
	world.session.weather.time_of_day=1.0/24.0
	await create_timer(1.2).timeout
	check(not meet.event_active and meet.mode=="quiet" and meet.guests.is_empty(),"At 01:00 meeting ends and crowd clears")
	world.session.weather.time_of_day=21.0/24.0
	await create_timer(.6).timeout
	check(not meet.event_active and meet.mode=="quiet","Wednesday evening has no meet")
	world.session.state.world_state.moon_day=3
	var crowd_deadline:=Time.get_ticks_msec()+6000
	while meet.guests.size()<6 and Time.get_ticks_msec()<crowd_deadline: await create_timer(.1).timeout
	check(meet.event_active and meet.guests.size()==6,"Thursday starts the next six-person meeting")
	world.player.teleport(Vector3(420,.1,106))
	world.player.speed=3.5
	world.player.automatic_direction=Vector3(0,0,1)
	await create_timer(4).timeout
	world.player.automatic_direction=Vector3.ZERO
	check(world.player.global_position.z>118 and absf(world.player.global_position.y)<.2,"Player walks from existing street through the driveway")
	# Swept movement, separately from the depth-render test.
	for body in [world.player,meet.guests[1]]:
		check(body.test_move(Transform3D(Basis.IDENTITY,Vector3(413.6,.08,120)),Vector3(0,0,-5)),"Full actor capsule cannot sweep through parked car")
		check(body.test_move(Transform3D(Basis.IDENTITY,Vector3(420,.08,129)),Vector3(0,0,3)),"Full actor capsule cannot sweep through auto-parts store")
	if meet.guests.size()>0:
		world.gameplay.weapon_fired.emit("pistol",Vector3(420,1,120))
		await create_timer(.6).timeout
		check(meet.guests.any(func(g):return g.get_meta("workplace_threatened",false)),"Conversation reacts to nearby gunfire signal")
		await create_timer(9).timeout
		check(meet.guests.all(func(g):return not g.get_meta("workplace_threatened",false)),"Guests recover after the threat ceases")
		var casualty=meet.guests[0]
		var missing_index:=int(casualty.get_meta("classic_meet_guest"))
		casualty.receive_damage(200,null)
		check(casualty.dead and missing_index in world.session.state.world_state.get("classic_meet_absences",{}).get("guests",[]),"Death is recorded immediately for this encounter")
		check(store.save(world.session.state)==OK,"Encounter absence persists in isolated save")
		var after_death=preload("res://runtime/GameState.gd").new()
		var death_loaded: bool=store.load_into(after_death).get("ok",false)
		var saved_indices: Array=after_death.world_state.get("classic_meet_absences",{}).get("guests",[])
		check(death_loaded and saved_indices.any(func(v):return int(v)==missing_index),"Isolated load preserves the missing participant")
		world.session.state.world_state.classic_meet_absences=after_death.world_state.get("classic_meet_absences",{}).duplicate(true)
		var site: Node3D=meet.site
		meet.queue_free()
		await process_frame
		meet=preload("res://gameplay/classic_meet/ClassicMeetController.gd").new()
		meet.configure(world.session,site)
		site.add_child(meet)
		world.session.urban_operations.classic_meet=meet
		crowd_deadline=Time.get_ticks_msec()+6000
		while meet.guests.size()<5 and Time.get_ticks_msec()<crowd_deadline: await create_timer(.1).timeout
		check(meet.guests.size()==5 and meet.guests.all(func(g):return int(g.get_meta("classic_meet_guest"))!=missing_index),"Rebuilding this encounter does not resurrect the participant")
	FileAccess.open(folder.path_join("validation.json"),FileAccess.WRITE).store_string(JSON.stringify({"failures":failures,"native_router":world.dispatch.router._native!=null,"meet_cars":meet.cars.size(),"meet_guests":meet.guests.size()}))

func diagnose_lights() -> void:
	var site=world.session.urban_operations.classic_meet.site
	var sources=site._lamps+site._event_lamps
	for light in sources:
		print("MEET_LIGHT ",light.global_position," energy=",light.light_energy," visible=",light.is_visible_in_tree()," direction=",-light.global_basis.z)
		light.light_energy*=4
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(folder.path_join("diagnostic-energy-x4.png"))
	for light in sources: light.light_energy/=4
