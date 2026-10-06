extends SceneTree
## Real Main: walking, contextual discoveries, isolated disk save and cold reload.
const FIXTURE := preload("res://tests/fixtures/NorthGatewayFixtures.gd")
const SITES := preload("res://world/desert/expansion/DesertRelics.gd")
const LAND := preload("res://world/desert/expansion/DesertLandforms.gd")
const LIFE := preload("res://world/desert/expansion/DesertEcologyLife.gd")
const STATE := preload("res://runtime/desert/expansion/DesertDiscoveryState.gd")
const STORE := preload("res://runtime/SaveStore.gd")
var world
var folder := ""
var path := ""
var old_launch := ""
var failures: Array[String]=[]
var checks := 0
var routes: Array[Dictionary]=[]
var temporal: Array[Dictionary]=[]
var recording := false
var segment := ""

func _initialize() -> void:
	create_timer(420).timeout.connect(func(): check(false,"420s bounded session timeout"); finish(3))
	run.call_deferred()

func check(ok: bool,label: String) -> bool:
	checks+=1
	if not ok: failures.append(label)
	print("EXPANSION_SESSION ","PASS " if ok else "FAIL ",label)
	return ok

func run() -> void:
	if not check(DisplayServer.get_name()!="headless" and "--no-save" not in OS.get_cmdline_user_args() and OS.get_environment("HARBOR_NO_CSHARP").is_empty(),"rendered .NET with isolated real disk save required"):
		finish(2); return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	root.size=Vector2i(1280,720)
	folder=FIXTURE.output_dir("desert-expansion-session")
	var at: Vector3=SITES.secrets()[0].position+Vector3(0,.08,8)
	var snapshot:=FIXTURE.full_snapshot(at,true)
	snapshot.region_id="desert"
	snapshot.world.pedestrian={"region":"desert","position":[at.x,at.y,at.z]}
	path=FIXTURE.write_fixture(folder,"checkpoint.json",snapshot)
	if not check(not path.is_empty(),"valid isolated checkpoint"): finish(1); return
	old_launch=root.get_node("V2Launch").selected_path
	root.get_node("V2Launch").selected_path=path
	if not await load_world(): finish(1); return
	if "--rail-only" in OS.get_cmdline_user_args():
		await place(Vector3(-1000,0,-566))
		check(await walk_to(Vector3(-1000,0,-535),"rail-crossing"),"physical walk crosses both abandoned rails")
		await photo("rail-crossing")
		finish(0 if failures.is_empty() else 1); return
	var initial_money: int=world.session.state.economy.balance
	var expected:=initial_money
	for site in SITES.secrets():
		await place(site.position+Vector3(0,0,6))
		if not await walk_to(site.position,"approach-"+str(site.id)): finish(1); return
		var action: Dictionary=world.session.nearest()
		check(action.get("target","")=="discovery:"+str(site.id),"contextual cache available "+str(site.id))
		var before: int=world.session.state.economy.balance
		var earned_first_grand: bool="first_grand" in world.session.state.economy.snapshot().achievements
		check(world.session.interact(),"ordinary interaction accepted "+str(site.id))
		# Saving refreshes ordinary achievements. The second cache legitimately
		# crosses R$1000 and grants the existing first_grand bonus as well.
		var achievement_bonus:=int(preload("res://data/catalogs/AchievementCatalog.gd").CASH_REWARDS.first_grand) if not earned_first_grand and before+int(site.amount)>=1000 else 0
		expected+=int(site.amount)+achievement_bonus
		check(STATE.collected(world.session.state.world_state,str(site.id)) and world.session.state.economy.balance==before+int(site.amount)+achievement_bonus,"one real reward with legitimate achievement "+str(site.id))
		await photo(str(site.id))
		world.session.lines.clear(); world.session.close_menu()
		check(not world.session.desert.discoveries.perform(action),"stale action cannot repeat "+str(site.id))
		check(world.session.state.economy.balance==expected,"wallet unchanged after repeat "+str(site.id))
		await create_timer(.5).timeout
		for content in get_nodes_in_group("desert_discovery_contents"):
			if str(content.get_meta("discovery_id",""))==str(site.id): check(not content.visible,"collected contents hidden "+str(site.id))
	check(world.session.save_game(),"productive save wrote isolated checkpoint")
	var disk:=STORE.read_valid(path)
	check(not disk.is_empty() and STATE.valid(disk.get("world",{}).get(STATE.KEY,{})),"disk preserves discoveries")
	for id in STATE.REWARDS: check(STATE.collected(disk.get("world",{}),id),"disk marker "+id)
	world.queue_free(); await process_frame; await process_frame
	if not await load_world(): finish(1); return
	check(world.session.state.economy.balance==expected,"cold Main reload restores exact wallet")
	for id in STATE.REWARDS: check(STATE.collected(world.session.state.world_state,id),"cold reload marker "+id)
	await place(SITES.secrets()[0].position)
	check(world.session.nearest().get("target","")!="discovery:"+str(SITES.secrets()[0].id),"return after cold reload has no repeated cache action")
	# Physical paths use actual CharacterBody movement; fixture placement only sets start.
	Engine.max_fps=30
	RenderingServer.frame_post_draw.connect(capture_temporal)
	for route in LAND.walk_paths():
		if str(route.id)=="wash_floor": continue # long wash is sampled separately below
		var points: PackedVector3Array=route.points
		await place(points[0])
		segment=str(route.id); recording=true
		for i in range(1,points.size()):
			if not await walk_to(points[i],segment): recording=false; finish(1); return
		recording=false
		await photo(segment)
	# Crossing a rail section exercises sleepers/rails without a wagon blocking the route.
	await place(Vector3(-1000,0,-566))
	segment="rail-crossing"; recording=true
	check(await walk_to(Vector3(-1000,0,-535),segment),"physical walk crosses abandoned rail")
	recording=false
	await photo("rail-crossing")
	for record in LIFE.locations():
		if str(record.id) not in ["desert_ecology_0","desert_ecology_1","desert_wind_0"]: continue
		await place(record.approach)
		await create_timer(1.5).timeout
		var ecology: Node3D=world.production.region.expansion_life
		check(is_instance_valid(ecology) and ecology.is_physics_processing(),"ecology active at "+str(record.id))
		segment=str(record.id); recording=true
		await walk_to(record.position+Vector3(6,0,3),segment)
		await create_timer(3).timeout
		recording=false
		await photo(segment)
		print("ECOLOGY_DIAGNOSTIC ",JSON.stringify(ecology.diagnostics()))
	var ecology: Node3D=world.production.region.expansion_life
	var bank:=preload("res://world/places/PlaceCatalog.gd").get_definition("desert_bank")
	await place(bank.entry_position)
	check(await world.session.enter_place("desert_bank",false),"real bank entry")
	await create_timer(.7).timeout
	check(not ecology.visible and not ecology.is_physics_processing(),"ecology suspends in real interior")
	check(await world.session.leave_place(),"real bank exit")
	await create_timer(.7).timeout
	check(ecology.visible and ecology.is_physics_processing(),"ecology resumes after return")
	finish(0 if failures.is_empty() else 1)

func load_world() -> bool:
	world=load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true); world.set_meta("menu_save_path",path)
	root.add_child(world); current_scene=world
	var deadline:=Time.get_ticks_msec()+80000
	while Time.get_ticks_msec()<deadline:
		await physics_frame
		if world.session!=null and world.session.ready_for_play and world.production.startup_streaming_settled: break
	if not check(world.session!=null and world.session.ready_for_play and world.production.store.path==path and not world.production.no_save and not world.production.save_invalid,"Main ready with isolated disk store"): return false
	world.dispatch.router.nearest_edge(world.player.global_position)
	if not check(world.dispatch.router._native!=null,"compiled C# route backend active"): return false
	if world.session.modal: world.session.lines.clear(); world.session.close_menu()
	world.player.controlled_automatically=true; world.player.automatic_direction=Vector3.ZERO
	world.session.weather.time_of_day=.45; world.session.weather.weather_state=0
	world.session.weather.weather_timer=3600; world.session.weather._update()
	return true

func place(at: Vector3) -> void:
	world.player.automatic_direction=Vector3.ZERO
	world.production.region.set_focus(at); world.production.region.prepare_collision_at(at)
	world.player.teleport(at+Vector3.UP*3)
	world.camera.initialized=false
	await create_timer(1.8).timeout
	var ray:=PhysicsRayQueryParameters3D.create(at+Vector3.UP*3,at+Vector3.DOWN*8,1)
	var hit: Dictionary=world.get_world_3d().direct_space_state.intersect_ray(ray)
	if check(not hit.is_empty(),"fixture start has physical support "+str(at)):
		world.player.teleport(hit.position+Vector3.UP*.08)
	for i in 6: await physics_frame

func walk_to(target: Vector3,label: String) -> bool:
	var begin: Vector3=world.player.global_position
	# Automatic Actor walking uses its configured speed (1.6m/s), whereas
	# player-input walking uses3.5. Budget this fixture from the actual mode.
	var deadline:=Time.get_ticks_msec()+int(begin.distance_to(target)/maxf(float(world.player.speed)*.85,.1)*1000)+6000
	var min_height: float=world.player.global_position.y
	var max_height: float=min_height
	while Time.get_ticks_msec()<deadline:
		var offset: Vector3=target-world.player.global_position; offset.y=0
		if offset.length()<.32: break
		world.player.automatic_direction=offset.normalized()
		await physics_frame
		min_height=minf(min_height,world.player.global_position.y)
		max_height=maxf(max_height,world.player.global_position.y)
		if min_height<-.8: break
	world.player.automatic_direction=Vector3.ZERO
	var remaining:=Vector2(target.x-world.player.global_position.x,target.z-world.player.global_position.z).length()
	routes.append({"id":label,"start":str(begin),"end":str(world.player.global_position),"remaining":remaining,"min_height":min_height,"max_height":max_height})
	return check(remaining<.4 and min_height>-.8,"walk reached "+label+" remaining="+str(remaining))

func photo(id: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(folder.path_join(id+".png"))

func capture_temporal() -> void:
	if not recording or temporal.size()>=4200: return
	var filename:="frame-%05d.jpg"%temporal.size()
	root.get_texture().get_image().save_jpg(folder.path_join(filename),.8)
	temporal.append({"file":filename,"segment":segment,"ticks_usec":Time.get_ticks_usec(),"render_frame":Engine.get_frames_drawn(),"player":str(world.player.global_position)})

func finish(code: int) -> void:
	recording=false
	if RenderingServer.frame_post_draw.is_connected(capture_temporal): RenderingServer.frame_post_draw.disconnect(capture_temporal)
	if not old_launch.is_empty(): root.get_node("V2Launch").selected_path=old_launch
	if not folder.is_empty(): FileAccess.open(folder.path_join("report.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"routes":routes,"temporal":temporal,"capture_note":"Every rendered frame during marked walks at cap30, with overhead; not a performance benchmark.","engine":Engine.get_version_info().string},"\t"))
	print("DESERT_EXPANSION_SESSION checks=",checks," failures=",failures," evidence=",folder)
	quit(code)
