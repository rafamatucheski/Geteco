extends SceneTree
const DEFINITIONS := preload("res://activities/ActivityDefinitions.gd")
var world
var failures: Array[String] = []
var checks := 0

func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	print("PHONE ","PASS " if ok else "FAIL ",label)
	if not ok: failures.append(label)

func run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	seed(28092026)
	for action in InputMap.get_actions(): InputMap.action_erase_events(action)
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	root.add_child(world)
	current_scene = world
	var deadline := Time.get_ticks_msec()+90000
	while Time.get_ticks_msec()<deadline:
		await process_frame
		if world.session != null and world.session.ready_for_play: break
	if world.session == null or not world.session.ready_for_play: quit(3); return
	var session = world.session
	var activities = session.activities
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	world.gameplay.health = 1000000
	session.weather.set_process(false)
	session.weather.time_of_day = .93
	session.weather._update()
	await create_timer(.4).timeout
	check(activities._phones.size() == DEFINITIONS.races("harbor").size(),"all street races have phones")
	var folder := "res://evidence/race-phone-20261002/functional"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	for id in activities._phones:
		var phone = activities._phones[id]
		var point: Vector3 = phone.position+phone.basis.z*1.2+Vector3.UP*.1
		world.player.teleport(point)
		world.production.region.set_focus(point)
		world.camera.target_size = 14
		await create_timer(3).timeout
		phone.cooldown = 0
		await create_timer(.2).timeout
		check(phone.audio.playing,id+" rings nearby on foot")
		check(activities.nearest_action().get("target","") == "race:"+id,id+" phone interaction on foot")
		var ray := PhysicsRayQueryParameters3D.create(phone.position+Vector3(0,1,1),phone.position+Vector3(0,1,-1),1)
		var hit: Dictionary = world.get_world_3d().direct_space_state.intersect_ray(ray)
		check(hit.get("collider") == phone,id+" physical solid blocks passage")
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(folder+"/"+id+".png")
		check(activities.perform("race:"+id),id+" answering opens menu")
		await create_timer(.2).timeout
		check(session.modal and not phone.audio.playing and activities.motorsport.mode == "",id+" answering silences phone, no automatic race")
		session.close_menu()
		check(activities.motorsport.mode == "",id+" hanging up preserves state")
		world.player.teleport(point+Vector3(12,0,0))
		await create_timer(.3).timeout
		check(not phone.audio.playing and not activities.perform("race:"+id),id+" distant phone silent and cannot be activated")
	# Actual vehicle entry and confirmation, including existing night restriction.
	var car = world.driving.car
	var spec: Dictionary = DEFINITIONS.races("harbor").harbor_docks
	car.place(DEFINITIONS.at(spec.phone)+Vector3(0,.12,-2.3),PI/2)
	world.production.region.set_focus(car.position)
	world.player.teleport(car.to_global(Vector3(-car.half_width-.7,.1,.15)))
	await create_timer(2).timeout
	check(world.driving.interact(),"enter actual car beside phone")
	await create_timer(3).timeout
	check(world.driving.occupied,"driver seated")
	# Traffic can make another nearby vehicle the selected entry candidate.
	# Exercise the phone with the actual occupied car, not the earlier candidate.
	car = world.driving.car
	car.place(DEFINITIONS.at(spec.phone)+Vector3(0,.12,-2.3),PI/2)
	car.speed = 0
	car.velocity = Vector3.ZERO
	car.external_input = true
	car.brake_input = true
	print("PHONE_DRIVER distance=",car.position.distance_to(activities._phone_position("harbor_docks"))," modal=",session.modal," vehicle=",car.vehicle_id," action=",activities.nearest_action())
	check(activities.perform("race:harbor_docks"),"driver answers phone")
	session.weather.time_of_day = .4
	_press("Entrar na corrida")
	check(activities.motorsport.mode == "","day restriction preserved")
	session.weather.time_of_day = .93
	check(activities.perform("race:harbor_docks"),"driver can call again")
	_press("Entrar na corrida")
	check(activities.motorsport.mode == "race" and activities.motorsport.countdown > 0,"confirmation starts actual countdown")
	await create_timer(3.5).timeout
	check(activities.motorsport.mode == "race" and activities.motorsport.countdown == 0,"curbside countdown completes without false cancellation")
	check(activities.perform("activity_cancel") and activities.motorsport.mode == "","race cancellation preserved")
	activities._rebuild()
	await process_frame
	check(activities._phones.size() == 2,"rebuild restores exactly two optional contacts")
	var mission = session.mission_world
	var campaign: Dictionary = session.state.campaign.snapshot()
	campaign.completed = ["primeiro_giro","cobra_contact"]
	campaign.claimed_rewards = campaign.completed.duplicate()
	campaign.flags = {"harbor_delivery_complete":true,"cobra_contact_complete":true}
	check(session.state.campaign.restore_snapshot(campaign) and session.state.campaign.begin("cobra_race"),"campaign pre-race checkpoint")
	car.place(mission.targets.ashbend_start+Vector3(-1.4,.12,3),0)
	world.production.region.set_focus(car.position)
	await create_timer(4).timeout
	print("PHONE_COBRA distance=",car.position.distance_to(mission.race_phone_position())," modal=",session.modal," health=",car.health," position=",car.position)
	check(mission.nearest_vehicle_action().get("target","") == "race_start","Cobra phone reachable in start lane")
	check(mission.perform("race_start") and session.modal and session.state.campaign.step == 0,"Cobra answering waits for confirmation")
	session.close_menu()
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(folder+"/cobra.png")
	check(mission.perform("race_start"),"Cobra phone can be answered again")
	_press("Entrar na corrida")
	check(session.state.campaign.step == 1 and not session.state.campaign.race_status().is_empty(),"Cobra real countdown started")
	print("RACE_PHONES checks=",checks," failures=",failures)
	world.free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

func _press(text: String) -> void:
	for child in world.session.column.get_children():
		if child is Button and child.text == text:
			child.pressed.emit()
			return
	check(false,"missing button: "+text)
