extends "res://tests/measure/measure_full.gd"
## Current budget of the new room. No comparable before sample exists.
const MISSIONS := preload("res://data/campaign/HarborMissions.gd")
const CAMPAIGN := preload("res://systems/campaign/CampaignRuntime.gd")
const STORY := preload("res://systems/campaign/HarborStory.gd")
const JESSICA := preload("res://systems/campaign/JessicaProgress.gd")
const STATE := preload("res://runtime/GameState.gd")
const STORE := preload("res://runtime/SaveStore.gd")
const CATALOG := preload("res://world/places/PlaceCatalog.gd")
const PORT_POLICY := preload("res://gameplay/urban_v1/HarborPortPolicy.gd")
var isolated_path := ""
var sample_context: Dictionary = {}
var sample_start_distance := 0.0
var invalid_context := false
var exterior_population_context: Dictionary = {}

func finish_list_dialogue(session) -> bool:
	# Same Continue callback as the house test; completing it supplies the real
	# mission event. An active mission must never bypass the normal save guard.
	var advances := 0
	while session.dialogue_open and advances<40:
		session._advance_dialogue()
		advances += 1
	return not session.dialogue_open and session.state.campaign.has_progress("cobra_finale") and session.state.campaign.active_id.is_empty()

func population_policy_at(point: Vector3) -> Dictionary:
	var candidates: Array[Dictionary] = []
	var short_segments := 0
	for road: Dictionary in world.production.ambient_roads_cache:
		var points: PackedVector3Array = road.points
		for index in range(points.size()-1):
			var distance := Geometry3D.get_closest_point_to_segment(point,points[index],points[index+1]).distance_to(point)
			if distance>=world.production.POPULATION_SPAWN_MAX: continue
			var length := points[index].distance_to(points[index+1])
			if length<=4:
				short_segments += 1
				continue
			candidates.append({"road":road.id,"length":length,"nearest_distance":distance})
	return {"point":point,"private_port_area":PORT_POLICY.contains_private_area(point),"ambient_road_count":world.production.ambient_roads_cache.size(),"near_long_segments":candidates,"excluded_near_short_segments":short_segments,"spawn_min_distance":world.production.POPULATION_SPAWN_MIN,"spawn_max_distance":world.production.POPULATION_SPAWN_MAX,"despawn_distance":world.production.POPULATION_DESPAWN,"requested":world.production.requested_population,"effective_population":world.people.size(),"scope":"Normal production spawning rejects segments <=4m and unsafe/on-road/private/visible points. Requested count is an intention, not a guaranteed physical count at this sparse place."}

func install_post_race_prefix(session) -> bool:
	# Same consistent fixture as test_cobra_leader_house.install_post_race_prefix.
	# Bank/Jessica history is a checkpoint; bank staging is not an FPS workload.
	var value: Dictionary = session.state.campaign.snapshot()
	value.completed = MISSIONS.ORDER.slice(0,MISSIONS.ORDER.find("cobra_finale"))
	value.claimed_rewards = value.completed.duplicate()
	value.flags = {}
	value.active_id = "cobra_finale"
	value.step = 6
	value.pending_rewards = {}
	value.race_elapsed = 0.0
	value.race_outside = 0.0
	value.race_run = {}
	value.failure = ""
	for id in value.completed:
		for flag in MISSIONS.MISSIONS[id].sets_flags: value.flags[flag] = true
		session.state.economy.grant_reward("campaign:"+str(id),int(MISSIONS.MISSIONS[id].reward))
	if not CAMPAIGN.validate_snapshot(value) or not session.state.campaign.restore_snapshot(value): return false
	var bank: Dictionary = session.robberies.snapshot()
	bank.bank_cash0 = true
	bank.bank_alarm = true
	bank.bank_dispatched = true
	bank.vault_open = true
	bank.keycard_available = true
	bank.keycard_taken = true
	bank.guards[0] = 0.0
	if not session.robberies.restore_snapshot(bank): return false
	var jessica := JESSICA.fresh_snapshot()
	jessica.met = true
	jessica.bank_complete = true
	jessica.bank_phase = "complete"
	jessica.bank_cycle = int(bank.bank_cycle)
	jessica.haul_mask = 1
	jessica.haul_receipt = "bank_haul:%d:1" % int(bank.bank_cycle)
	jessica.conversations = ["first_meeting","bank_debrief"]
	if not JESSICA.validate_snapshot(jessica): return false
	session.state.world_state.jessica = jessica
	session.state.economy.grant_reward(jessica.haul_receipt,5000)
	session.state.intro.set_location("harbor_garage")
	session.state.intro.complete_meeting()
	STORY.mark_opening(session.state.world_state)
	STORY.mark_maciota(session.state.world_state)
	return true

func context() -> Dictionary:
	var traffic := 0
	for car in world.production.vehicles:
		if is_instance_valid(car) and car.traffic and car.health>0: traffic += 1
	var visible_people := 0
	var live_people := 0
	for person in world.people:
		if not is_instance_valid(person): continue
		if not person.dead: live_people += 1
		if person.visible: visible_people += 1
	var settings = root.get_node("V2Settings")
	return {"place":world.session.state.place_id,"health":world.gameplay.health,"wanted":world.gameplay.stars,"modal":world.session.modal,"population":world.people.size(),"live_population":live_people,"visible_population":visible_people,"requested_population":world.production.requested_population,"effective_population_cap":world.production._population_cap(),"density_scale":world.production.density_scale,"cars":world.production.vehicles.size(),"active_traffic":traffic,"traffic_cap":world.production._traffic_cap(),"time_of_day":world.session.weather.time_of_day,"weather":world.session.weather.weather_state,"rain":world.session.weather.rain_intensity,"campaign_id":world.session.state.campaign.active_id,"campaign_step":world.session.state.campaign.step,"no_save":world.production.no_save,"loaded_save":world.production.loaded_save,"store_path":world.production.store.path,"camera_size":world.camera.size,"camera_target_size":world.camera.target_size,"camera_offset":world.camera.offset,"msaa":root.msaa_3d,"render_scale":settings.render_scale,"shadow_quality":settings.shadow_quality,"camera_view":settings.camera_view}

func run() -> void:
	if DisplayServer.get_name()=="headless" or "--no-save" not in OS.get_cmdline_user_args():
		push_error("Takeshi budget requires rendered Main and --no-save"); quit(2); return
	interior_mode = true
	label = "takeshi-current"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--label="): label = arg.trim_prefix("--label=")
		if arg.begins_with("--evidence-dir="): evidence_dir = arg.trim_prefix("--evidence-dir=")
	if evidence_dir.is_empty() or not evidence_dir.is_absolute_path():
		push_error("Takeshi budget requires an absolute evidence directory"); quit(2); return
	isolated_path = evidence_dir.path_join(label+"-isolated-progress.json")
	root.get_node("V2Launch").selected_path = isolated_path
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	root.add_child(world)
	setup_started_msec = Time.get_ticks_msec()
	var deadline := Time.get_ticks_msec()+80000
	while Time.get_ticks_msec()<deadline:
		await physics_frame
		guard_interior_preparation()
		if world.session != null and world.session.ready_for_play: break
	if world.session == null or not world.session.ready_for_play:
		fail_setup("Takeshi benchmark Main startup failed"); return
	var session = world.session
	if not world.production.no_save or world.production.loaded_save or world.production.requested_population!=24:
		fail_setup("Takeshi benchmark requires a fresh no-save world with 24 requested NPCs"); return
	world.camera.set_process_unhandled_input(false)
	world.driving.set_process_unhandled_input(false)
	for child in world.hud.get_children():
		if child.get_script()==preload("res://scripts/PauseInput.gd"): child.set_process_unhandled_input(false)
	session.arrival.active = false
	if not install_post_race_prefix(session):
		fail_setup("Takeshi post-race checkpoint invalid"); return
	session.weather.time_of_day = .94
	session.weather.weather_state = 0
	session.weather.rain_intensity = 0.0
	session.weather._update()
	var definition: Dictionary = CATALOG.get_definition("cobra_leader_house")
	world.player.teleport(definition.entry_position+Vector3.UP*.08)
	world.production.region.set_focus(world.player.global_position)
	var next_note := Time.get_ticks_msec()
	while Time.get_ticks_msec()<deadline:
		await physics_frame
		if Time.get_ticks_msec()>=next_note:
			note_setup("admitting_house_collision_and_action")
			next_note = Time.get_ticks_msec()+5000
		if world.production.region.is_streaming_idle() and session.mission_world.nearest_action().get("target","")=="leader_house": break
	if not world.production.region.is_streaming_idle():
		fail_setup("Takeshi benchmark failed to prepare house collision"); return
	if not session.position_clear(world.player.global_position):
		fail_setup("Takeshi house street entrance is not capsule-clear"); return
	exterior_population_context = population_policy_at(world.player.global_position)
	print("TAKESHI_POPULATION_POLICY ",JSON.stringify(exterior_population_context))
	if not session.mission_world.perform("leader_house"):
		fail_setup("Takeshi post-race house interaction unavailable"); return
	deadline = Time.get_ticks_msec()+15000
	while Time.get_ticks_msec()<deadline:
		await physics_frame
		if session.state.place_id=="cobra_leader_house" and session.state.campaign.step==7 and not session.has_position_transition(): break
	if session.state.place_id!="cobra_leader_house" or session.state.campaign.step!=7 or session.has_position_transition():
		fail_setup("Takeshi physical room admission did not complete"); return
	var room: Node3D = session.room
	world.player.set_physics_process(false)
	var list_point: Vector3 = session.mission_world.target_position()
	if not session.position_clear(list_point) or not await session.arrival._walk(world.player,list_point):
		fail_setup("Takeshi benchmark could not physically reach the list"); return
	if not session.mission_world.perform("transfer_document") or not finish_list_dialogue(session):
		fail_setup("Takeshi benchmark did not complete the real list interaction"); return
	var story := STORY.data(session.state.world_state)
	if not story.brother_route_found or not story.act_two_available:
		fail_setup("Takeshi benchmark list did not unlock its actual story route"); return
	route = PackedVector3Array()
	# The passage stays west of the desk, east of the sofa and north of the exit.
	for local in [Vector3(0,0,1.5),Vector3(-2,0,1.5),Vector3(-2,0,-1.8),Vector3(0,0,-1.8)]:
		var point: Vector3 = room.to_global(local)
		if not session.position_clear(point+Vector3.UP*.08):
			fail_setup("Takeshi benchmark waypoint is not on clear supported ground"); return
		route.append(point)
	world.player.speed = 1.5
	world.player.set_physics_process(true)
	if not session.save_game(true):
		fail_setup("Takeshi completed checkpoint refused by the normal save guard: "+session.save_block_reason()); return
	var serialized: Variant = JSON.parse_string(JSON.stringify(session.state.snapshot()))
	var restored := STATE.new()
	if not serialized is Dictionary or not restored.restore_snapshot(serialized):
		fail_setup("Takeshi benchmark checkpoint cannot roundtrip consistently"); return
	var store := STORE.new()
	store.path = isolated_path
	if store.save(session.state)!=OK or not store.load_into(STATE.new()).get("ok",false):
		fail_setup("Takeshi completed checkpoint failed isolated disk save/load"); return
	note_setup("takeshi_room_prepared")
	release_preparation_guard()
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(evidence_dir.path_join(label+"-start.png"))
	started = Time.get_ticks_usec()
	previous = started

func _process(delta: float) -> bool:
	if started!=0 and (world.session.state.place_id!="cobra_leader_house" or world.gameplay.health<=0 or world.session.modal): invalid_context = true
	var was_measuring := measuring
	var result := super._process(delta)
	if measuring and not was_measuring:
		sample_start_distance = float(world.player.travelled)
		sample_context = context()
	return result

func finish() -> void:
	var summary := stats(samples)
	var measured_distance: float = world.player.travelled-sample_start_distance
	var workload_valid: bool = not invalid_context and measured_distance>10 and world.session.state.place_id=="cobra_leader_house" and world.production.requested_population==24 and world.gameplay.health>0 and guarded_player==null and guarded_gameplay==null
	var report := {"label":label,"scenario":"takeshi","baseline":null,"budget_fps":60,"budget_frame_ms":16.67,"budget_scope":"New interior current budget only, no causal before/after comparison.","engine":Engine.get_version_info().string,"gpu":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),"resolution":str(root.size),"vsync":DisplayServer.window_get_vsync_mode(),"max_fps":Engine.max_fps,"msaa":root.msaa_3d,"summary":summary,"warmup":stats(cold),"cpu_process":stats(cpu),"physics":stats(physics),"frame_intervals_ms":samples,"warmup_intervals_ms":cold,"sample_context":sample_context,"final_context":context(),"population":world.people.size(),"requested_population":world.production.requested_population,"cars":world.production.vehicles.size(),"sample_player_distance":measured_distance,"workload_valid":workload_valid,"preparation_snapshots":preparation_snapshots,"setup_protection_removed_before_warmup":guarded_player==null and guarded_gameplay==null,"isolated_progress_path":isolated_path,"fixture_prefix":"Consistent after race victory, includes prior bank/Jessica receipts; entered through the public mission/FullSession API.","quality_ablation":false,"notes":"Outside NPCs/traffic follow normal interior suspension; no benchmark density/trafic reduction or fake resident was added."}
	report.population_policy_at_entrance = exterior_population_context
	report.list_completed_through_api = true
	report.isolated_checkpoint_saved_and_reloaded = true
	report.requested_population_gap = world.production.requested_population-world.people.size()
	report.population_scope_limit = "Natural effective population at Takeshi's sparse access/normal interior context, requested 24 unchanged. Does not certify a forced 24-NPC room or an unrelated populated district."
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(evidence_dir.path_join(label+".png"))
	FileAccess.open(evidence_dir.path_join(label+".json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("TAKESHI_BUDGET ",JSON.stringify(summary)," context=",JSON.stringify(report.final_context)," workload_valid=",workload_valid)
	world.free()
	await process_frame
	if not workload_valid: push_error("Takeshi budget workload left its intended room, population or walking context")
	quit(0 if workload_valid else 1)
