extends "res://tests/test_harbor_building_walkthrough.gd"
## Real Main scene: walk in, reach a resident through solids, use the actual
## interaction and buttons, recover control, witness a threat and walk out.
## Rendered captures are presentation evidence, never frame-time certification.
var social_frames: Array[Dictionary] = []

func capture_social(label: String, resident: Node3D, count := 1) -> void:
	for index in count:
		await create_timer(.16).timeout
		var snapshot: Dictionary = resident.social_snapshot() if is_instance_valid(resident) else {}
		social_frames.append({"phase":label,"frame":index,"usec":Time.get_ticks_usec(),"snapshot":snapshot})
		await photo("%s-%02d" % [label,index])

func approach_resident(room: Node3D) -> Node3D:
	var residents := get_nodes_in_group("building_resident")
	for resident in residents:
		if not room.is_ancestor_of(resident) or resident.dead: continue
		var center: Vector3 = room.floor_room.to_local(resident.global_position)
		for offset: Vector3 in [Vector3(0,0,1.3),Vector3(-1.3,0,0),Vector3(1.3,0,0),Vector3(0,0,-1.3)]:
			var candidate := center+offset
			candidate.y = .04
			if not world.session.position_clear(room.floor_room.to_global(candidate)): continue
			if not await roof_walk_to(room.floor_room,candidate): continue
			for frame in 3: await physics_frame
			var action: Dictionary = world.session.nearest()
			if action.get("id","") == "building_social" and action.get("target") == resident: return resident
	return null

func press_option(id: String) -> bool:
	var social = world.session.building_social
	if not social.active or not social.panel.buttons.has(id): return false
	var button: Button = social.panel.buttons[id]
	if button.disabled: return false
	button.pressed.emit()
	await process_frame
	return true

func run() -> void:
	create_timer(200).timeout.connect(func(): check(false,"bounded session timeout"); finish(3))
	rendered = DisplayServer.get_name() != "headless"
	folder = FIXTURE.output_dir("building-social-session")
	seed(100726)
	var definition: Dictionary = CATALOG.find("harbor_customs_house")
	var snapshot := FIXTURE.full_snapshot(definition.return_position+Vector3.UP*.08,true)
	snapshot.campaign.aftermath = {"call_complete":true}
	save_path = FIXTURE.write_fixture(folder,"save.json",snapshot)
	await boot()
	world.dispatch.router.nearest_edge(world.player.global_position)
	check(world.dispatch.router._native != null,"C# runtime active")
	check(is_instance_valid(world.session.building_social),"social controller installed in FullSession")
	var runtime = world.session.building_entrance
	var deadline := Time.get_ticks_msec()+15000
	while (not is_instance_valid(runtime.staged) or runtime.preparing) and Time.get_ticks_msec()<deadline: await physics_frame
	if not check(is_instance_valid(runtime.staged),"building staged from street"): finish(); return
	if not check(await walk(runtime.staged.spawn_position+Vector3.UP*.04),"walk across original entrance"): finish(); return
	var room = world.session.room
	if not check(is_instance_valid(room),"continuous building admission"): finish(); return
	var resident := await approach_resident(room)
	if not check(is_instance_valid(resident),"reach resident through real furniture collision"): finish(); return
	var station: Vector3 = resident.global_position
	check(not resident.test_move(resident.global_transform,Vector3.UP*.002),"resident capsule stays clear of furniture")
	check(world.session.position_clear(world.player.global_position),"player supported and clear beside resident")
	await capture_social("01-work",resident)
	check(await world.session.interact(),"normal interact opens social menu")
	check(world.session.modal and world.session.building_social.active and world.player.input_locked,"conversation owns input without pausing world")
	check(not paused,"conversation does not pause simulation")
	for id: String in ["greet","chat","joke"]:
		check(await press_option(id),"real menu button "+id)
		await capture_social("02-"+id,resident,4)
		await create_timer(1.2).timeout
	check(world.gameplay.stars == 0 and world.gameplay.police_case.pending.is_empty(),"friendly conversation creates no crime")
	check(not world.session.building_social.panel.reply_label.text.is_empty(),"NPC response is visible")
	world.session.building_social.panel.close_button.pressed.emit()
	await physics_frame
	check(not world.session.modal and not world.player.input_locked,"goodbye restores movement")
	await create_timer(.8).timeout
	check(await world.session.interact(),"second conversation opens")
	var cancel := InputEventAction.new()
	cancel.action = "ui_cancel"
	cancel.pressed = true
	Input.parse_input_event(cancel)
	await process_frame
	cancel = InputEventAction.new()
	cancel.action = "ui_cancel"
	cancel.pressed = false
	Input.parse_input_event(cancel)
	check(not world.session.building_social.active and not world.session.modal and not world.player.input_locked,"cancel input restores control")
	await create_timer(1.0).timeout
	check(await world.session.interact(),"threat conversation opens")
	check(await press_option("intimidate"),"intimidation uses player interaction")
	check(not world.session.modal,"threat closes conversation so danger remains live")
	check(world.gameplay.stars == 0,"phone call has a delay before wanted stars")
	check(not world.gameplay.police_case.pending.is_empty(),"witness actually starts pending police testimony")
	await capture_social("03-threat",resident,5)
	await create_timer(2.6).timeout
	check(world.gameplay.stars > 0,"completed witness call reaches real police case")
	check(world.session.building_social.nearest_action().is_empty(),"wanted player cannot use conversation as shelter")
	check(not resident.test_move(resident.global_transform,Vector3.UP*.002),"frightened NPC stays outside furniture")
	await capture_social("04-police-called",resident,3)
	# End the controlled crime scenario using the existing cleanup API; movement
	# and resident recovery afterwards still run through the productive runtime.
	world.gameplay.clear_wanted()
	await create_timer(12.0).timeout
	check(resident.global_position.distance_to(station)<.15,"resident returns to interrupted post")
	await capture_social("05-recovery",resident,3)
	if not check(await roof_walk_to(room.floor_room,room.floor_room.to_local(room.spawn_position+Vector3.UP*.04)),"walk back around furniture"): finish(); return
	check(await walk(definition.return_position+Vector3.UP*.04),"walk back to street")
	check(world.session.state.place_id.is_empty() and not world.player.input_locked,"exit releases controls and context")
	check(not world.session.building_social.active,"no conversation survives room exit")
	world.player.teleport(definition.return_position+Vector3(0,.08,24))
	await create_timer(.8).timeout
	check(world.session.building_social.nearest_action().is_empty(),"unloaded resident cannot be targeted")
	visited.append({"id":definition.id,"floors":1,"social_frames":social_frames})
	FileAccess.open(folder.path_join("social-frames.json"),FileAccess.WRITE).store_string(JSON.stringify(social_frames,"\t"))
	finish()
