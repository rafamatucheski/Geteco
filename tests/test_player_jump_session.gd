extends "res://tests/test_harbor_building_walkthrough.gd"

func run() -> void:
	create_timer(240).timeout.connect(func(): check(false,"bounded high fall session"); finish(3))
	rendered = DisplayServer.get_name() != "headless"
	folder = FIXTURE.output_dir("player-jump-session")
	var definition: Dictionary = {}
	for candidate in CATALOG.definitions():
		if candidate.region == "harbor" and candidate.roof_height > 13.0 and candidate.roof_height < 23.0:
			definition = candidate
			break
	if not check(not definition.is_empty(),"authored tall roof selected"): finish(); return
	# Use open pavement and verify full overhead clearance independently.
	var outward := Basis(Vector3.UP,float(definition.exterior_rotation)) * Vector3.BACK
	var snapshot := FIXTURE.full_snapshot(definition.return_position+outward*3.0+Vector3.UP*.08,true)
	snapshot.campaign.aftermath = {"call_complete":true}
	save_path = FIXTURE.write_fixture(folder,"save.json",snapshot)
	await boot()
	world.player.controlled_automatically = false
	var support_deadline := Time.get_ticks_msec()+3000
	while (not world.player.is_on_floor() or world.player.air_movement.phase != "ground") and Time.get_ticks_msec()<support_deadline: await physics_frame
	check(world.player.is_on_floor() and world.player.air_movement.phase == "ground", "checkpoint capsule settled before keyboard jump")
	check(not world.player.test_move(world.player.global_transform,Vector3.UP*1.2), "street jump has full overhead clearance")
	var former_start: Transform3D = world.player.global_transform
	former_start.origin -= outward*3.0
	var overhead := KinematicCollision3D.new()
	if world.player.test_move(former_start,Vector3.UP*1.2,overhead):
		print("DOOR_RETURN_OVERHEAD ",overhead.get_collider().get_path() if overhead.get_collider() is Node else overhead.get_collider())
	var initial_y: float = world.player.global_position.y
	var jump := InputEventKey.new()
	jump.physical_keycode = KEY_SPACE
	jump.pressed = true
	check(jump.is_action_pressed("jump"), "Space resolves the new remappable action")
	print("JUMP_INPUT_CONTEXT ", JSON.stringify({"phase":world.player.air_movement.phase,"floor":world.player.is_on_floor(),"locked":world.player.input_locked,"modal":world.session.modal,"transition":world.session.transition_kind,"point":str(world.player.global_position)}))
	Input.parse_input_event(jump)
	# Input is delivered on a process tick. Several catch-up physics frames
	# can precede that delivery, so observe actual lift instead of assuming
	# six awaited physics signals mean six steps after the key was consumed.
	var input_deadline := Time.get_ticks_msec()+2000
	while world.player.global_position.y <= initial_y+.15 and Time.get_ticks_msec()<input_deadline: await physics_frame
	print("JUMP_INPUT_RESULT ",JSON.stringify({"phase":world.player.air_movement.phase,"age":world.player.air_movement.age,"point":str(world.player.global_position),"velocity":str(world.player.velocity)}))
	check(world.player.global_position.y > initial_y + .15, "Space event jumps in actual Main input flow")
	check(not world.session.state.can_attack(), "airborne combat blocked")
	check(not world.driving.can_enter(), "airborne vehicle boarding blocked")
	await photo("space-jump")
	jump = InputEventKey.new()
	jump.physical_keycode = KEY_SPACE
	jump.pressed = false
	Input.parse_input_event(jump)
	var deadline := Time.get_ticks_msec()+5000
	while world.player.air_movement.phase != "ground" and Time.get_ticks_msec()<deadline: await physics_frame
	check(world.gameplay.health == 100.0 and not world.player.get_meta("player_air_busy",true), "normal jump recovers without damage")
	if "--input-only" in OS.get_cmdline_user_args(): finish(); return
	world.player.controlled_automatically = true
	if not check(await world.session.enter_place(definition.id,false),"enter tall building"): finish(); return
	var room = world.session.room
	for level in range(1,int(definition.floor_count)+1):
		world.player.teleport(room.to_global(room.stair_point())+Vector3.UP*.04)
		if not check(await room.change_floor(level),"tall roof route level "+str(level)): finish(); return
	var roof = room.floor_room
	var landing: Vector3 = roof.to_local(world.player.global_position)
	check(await walk(roof.to_global(Vector3(landing.x,.04,roof.jump_point.z))),"tall roof aisle")
	check(await walk(roof.to_global(roof.jump_point+Vector3.UP*.04)),"tall roof edge approach")
	check(world.session.nearest().get("id","") != "building_rooftop_jump", "tall roof offers no jump button")
	world.player.automatic_direction = roof.global_basis * roof.jump_outward
	world.player.speed = 3.5
	var saw_fall := false
	var captured := false
	deadline = Time.get_ticks_msec()+8000
	while not world.player.dead and Time.get_ticks_msec()<deadline:
		await physics_frame
		if world.player.air_movement.phase == "fall":
			saw_fall = true
			if not captured and world.player.air_movement.age > .30:
				captured = true
				await photo("high-freefall")
	world.player.automatic_direction = Vector3.ZERO
	check(saw_fall and world.player.dead and world.gameplay.health == 0, "high drop falls physically and is fatal")
	check(world.player.last_death_clip == "mixamo/death_forward", "fatal landing is prone")
	check(world.session.state.place_id.is_empty() and not is_instance_valid(world.session.room), "fatal fall releases room owner")
	await photo("fatal-ground-impact")
	finish()
