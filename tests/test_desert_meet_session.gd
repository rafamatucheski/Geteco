extends SceneTree
## Main/.NET integration with an isolated authored checkpoint. Fixture teleports
## locate the meet; this does not claim the highway approach was driven manually.
const FIXTURE := preload("res://tests/fixtures/NorthGatewayFixtures.gd")
const LAYOUT := preload("res://world/desert/DesertLayout.gd")
var world
var checks := 0
var failures: Array[String] = []
var output := ""

func _initialize() -> void:
	create_timer(180).timeout.connect(func(): push_error("DESERT_MEET_SESSION timeout"); quit(3))
	run.call_deferred()

func check(value: bool, label: String) -> bool:
	checks += 1
	print("DESERT_MEET_SESSION ","PASS " if value else "FAIL ",label)
	if not value: failures.append(label)
	return value

func frames(count: int) -> void:
	for i in count: await physics_frame

func run() -> void:
	if not check("--no-save" in OS.get_cmdline_user_args() and OS.get_environment("HARBOR_NO_CSHARP").is_empty(),"isolated compiled .NET run required"): finish(); return
	output = FIXTURE.output_dir("desert-meet-session")
	var at := LAYOUT.drag_meet_center()+Vector3(0,.08,6)
	var data := FIXTURE.full_snapshot(at,true)
	data.campaign.aftermath = {"call_complete":true}
	data.region_id = "desert"
	data.world.pedestrian = {"region":"desert","position":[at.x,at.y,at.z]}
	var path := FIXTURE.write_fixture(output,"checkpoint.json",data)
	if not check(not path.is_empty(),"valid isolated desert checkpoint created"): finish(); return
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	world.set_meta("menu_save_path",path)
	root.add_child(world)
	current_scene = world
	for i in 4800:
		await physics_frame
		if world.session!=null and world.session.ready_for_play and world.production.startup_streaming_settled: break
	if not check(world.session!=null and world.session.ready_for_play,"Main loads meet checkpoint"): finish(); return
	var session = world.session
	check(world.production.store.path==path and world.production.no_save,"personal saves are not read or overwritten")
	world.dispatch.router.nearest_edge(at)
	check(world.dispatch.router._native!=null,"actual C# routing backend loaded")
	var meet = session.desert.meet_life
	var routine = session.desert.digo_routine
	for i in 1500:
		await physics_frame
		if int(meet.diagnostics().residents)>=34 and is_instance_valid(routine.actor): break
	check(get_nodes_in_group("desert_drag_crew").size()==7,"Vicente has six distinct protected crew members")
	check(int(meet.diagnostics().residents)>=34,"authored meet population fills all teams and social circles")
	check(int(meet.diagnostics().voices)>0 and int(meet.diagnostics().voices)<=7,"spatial ambience plays within its seven-voice budget")
	check(meet.members.values().all(func(actor): return not actor is CharacterBody3D or not world.people.has(actor)),"authored residents remain independent of ambient population slots")
	check(is_instance_valid(routine.actor),"working Digo is admitted beside the meet")
	for identity in ["livia","raul","jessica","nadir"]:
		check(is_instance_valid(session.desert.story.actors.get(identity)),"race opponent is physically present: "+identity)
	var vicente = session.desert.story.actors.get("vicente")
	if not check(is_instance_valid(vicente),"Vicente is present at the new meeting place"): finish(); return
	check(vicente.global_position.distance_to(LAYOUT.drag_vicente_point())<.5,"campaign Vicente uses the new venue")
	world.gameplay._damage(vicente,10000.0,world.player)
	await frames(2)
	check(is_instance_valid(vicente) and not vicente.is_queued_for_deletion() and vicente.collision_layer!=0,"production damage preserves Vicente and his physical body")
	for member in get_nodes_in_group("desert_drag_crew"):
		world.gameplay._damage(member,10000.0,world.player)
	check(get_nodes_in_group("desert_drag_crew").size()==7,"crew remains present after production damage")
	await overview()
	await approach(vicente.global_position+Vector3(0,.08,1.2))
	check(session.desert.story.nearest_action().get("target","")=="vicente","Vicente remains approachable for story dialogue")
	check(session.desert.story.perform("vicente",false),"normal story dialogue opens at the meet")
	await frames(45)
	var ducked := true
	for voice in meet.ambience.voices:
		if voice.playing: ducked=ducked and voice.volume_db<=-34.0
	check(ducked,"conversation reduces surrounding sound while dialogue is open")
	for i in 12:
		if not session.dialogue_open: break
		session._advance_dialogue()
	check(not session.modal and session.state.world_state.get("desert_story",{}).get("met_vicente",false),"completed conversation records the existing story flag")
	await photo("vicente-gameplay")
	var jessica = session.desert.story.actors.get("jessica")
	if is_instance_valid(jessica):
		await approach(jessica.global_position+Vector3(0,.08,1.2))
		check(session.desert.story.perform("jessica",false),"Jessica can be approached beside her team")
		for i in 12:
			if not session.dialogue_open: break
			session._advance_dialogue()
		check(not session.state.world_state.get("desert_story",{}).get("jessica_met",false),"casual Jessica conversation does not bypass the race story milestone")
		await photo("jessica-gameplay")
		await approach(vicente.global_position+Vector3(0,.08,1.2))
	if "--temporal" in OS.get_cmdline_user_args(): await temporal_meet(session)
	if is_instance_valid(routine.actor):
		await approach(routine.actor.global_position+Vector3(-1.15,.08,0))
		check(session.position_clear(world.player.global_position) and world.player.global_position.y<.3,"Digo's customer stands on the clear aisle beside the car")
		var action: Dictionary = session.desert.nearest_action()
		check(action.get("target","")=="digo_workshop","moving Digo exposes ordinary contextual interaction")
		check(session.desert.perform(action) and session.dialogue_open,"Digo stops working to speak through the real service flow")
		var paused_at: Vector3 = routine.actor.global_position
		await frames(45)
		check(routine.actor.global_position.distance_to(paused_at)<.04,"Digo stays with the player during conversation")
		for i in 12:
			if not session.dialogue_open: break
			session._advance_dialogue()
		await frames(30)
		check(not routine.diagnostics().talking and not session.modal,"Digo returns to his routine after dialogue")
		await photo("digo-gameplay")
		await check_service(session,routine)
	# Leaving and returning exercises the production region transition and owner cleanup.
	check(world.production.travel("harbor"),"ordinary regional travel leaves the meet")
	await settle()
	await frames(35)
	check(get_nodes_in_group("desert_drag_crew").is_empty() and not is_instance_valid(routine.actor),"leaving releases crew and the working Digo")
	check(get_nodes_in_group("desert_drag_meet_resident").is_empty() and int(meet.diagnostics().voices)==0,"leaving releases every resident and its spatial audio")
	# The completed-campaign fixture legitimately delivers its Harbor epilogue
	# on this first return. Finish it before testing calm re-entry at the meet.
	for i in 12:
		if not session.dialogue_open: break
		session._advance_dialogue()
	check(world.production.travel("desert",at),"ordinary return to the meet admitted")
	await settle()
	for i in 1500:
		await physics_frame
		if int(meet.diagnostics().residents)>=34 and is_instance_valid(routine.actor): break
	check(get_nodes_in_group("desert_drag_crew").size()==7 and is_instance_valid(routine.actor),"return rebuilds exactly one crew and one working Digo")
	check(int(meet.diagnostics().residents)==34,"return restores the authored population without duplicates")
	print("DESERT_MEET_DIAGNOSTICS ",JSON.stringify(meet.diagnostics()))
	finish()

func check_service(session,routine) -> void:
	# Simulate a legitimate completed first race through the production result ledger.
	var progress := preload("res://activities/desert_drag/DesertDragProgress.gd")
	var result := progress.record_finish(session.state.world_state,"digo",false,24.0)
	session.desert.story.race_finished(result)
	var car = world.production.spawn_vehicle("desert_faisca",routine.parking_point(),PI)
	if not check(is_instance_valid(car),"new workshop delivery bay admits a real car"): return
	var previous_car = world.driving.car
	world.driving.car = car
	await approach(routine.actor.global_position+Vector3(-1.15,.08,0))
	check(session.desert.perform(session.desert.nearest_action()) and session.modal,"unlocked Digo opens preparation service at the meet")
	for i in 12:
		if not session.dialogue_open: break
		session._advance_dialogue()
	check(session.desert.tuning_car==car,"new workshop selects the nearby player's car")
	session.close_menu()
	await frames(20)
	check(not routine.diagnostics().talking,"closing preparation resumes Digo's work")
	car.queue_free()
	world.driving.car = previous_car if is_instance_valid(previous_car) else null

func approach(point: Vector3) -> void:
	world.production.region.prepare_collision_at(point)
	await frames(2)
	world.player.teleport(point)
	await frames(40)

func settle() -> void:
	for i in 1200:
		await physics_frame
		if not world.production.travel_busy and world.session.ready_for_play: return

func photo(id: String) -> void:
	if DisplayServer.get_name()=="headless": return
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(output.path_join(id+".png"))==OK,"rendered photo "+id)

func overview() -> void:
	if DisplayServer.get_name()=="headless": return
	var previous := root.get_camera_3d()
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 130
	camera.far = 1400
	world.add_child(camera)
	camera.global_position = LAYOUT.drag_meet_center()+Vector3(15,100,95)
	camera.look_at(LAYOUT.drag_meet_center())
	camera.make_current()
	await frames(5)
	await photo("meet-overview")
	previous.make_current()
	camera.queue_free()

func temporal_meet(session) -> void:
	if DisplayServer.get_name()=="headless":
		check(false,"temporal inspection requires rendering")
		return
	var capture = load("res://tests/capture/DesertDragTemporalCapture.gd").new()
	root.add_child(capture)
	var was_weather: bool = session.weather.is_processing()
	var was_automatic: bool = world.player.controlled_automatically
	var previous_heading: float = world.camera.heading
	session.weather.set_process(false)
	check(capture.begin(world,session.desert.drag,output.path_join("temporal")),"continuous rendered meet recording starts")
	if not capture.recording:
		session.weather.set_process(was_weather)
		capture.queue_free()
		return
	capture._report.coverage = "Actual Main gameplay camera: Vicente's meet, day/dusk/night, short ordinary walk and camera orbit; no FPS verdict"
	capture._report.clock_control = "Fixture fixes day at .45 for 8 s, sweeps .72 to .90 for 8 s, then holds night during ordinary movement"
	capture._report.not_covered = ["whole strip","rain","performance","audible sound quality"]
	world.player.controlled_automatically = true
	var began := Time.get_ticks_usec()
	while float(Time.get_ticks_usec()-began)/1000000.0<32.0:
		var elapsed := float(Time.get_ticks_usec()-began)/1000000.0
		capture.segment = "meet_day" if elapsed<8 else ("meet_dusk" if elapsed<16 else "meet_night")
		session.weather.time_of_day = .45 if elapsed<8 else (lerpf(.72,.90,(elapsed-8)/8) if elapsed<16 else .9)
		session.weather._update()
		world.player.automatic_direction = Vector3.LEFT if elapsed>18 and elapsed<21 else Vector3.ZERO
		world.camera.heading = previous_heading+sin(maxf(0,elapsed-20)*.2)*.3 if elapsed>20 else previous_heading
		await process_frame
	world.player.automatic_direction = Vector3.ZERO
	world.player.controlled_automatically = was_automatic
	world.camera.heading = previous_heading
	session.weather.set_process(was_weather)
	var report: Dictionary = capture.stop()
	check(str(report.failure).is_empty() and float(report.duration_seconds)>=30,"day/dusk/night movement sequence recorded for at least 30 seconds")
	capture.queue_free()

func finish() -> void:
	print("DESERT_MEET_SESSION checks=%d failures=%d evidence=%s"%[checks,failures.size(),output])
	quit(0 if failures.is_empty() else 1)
