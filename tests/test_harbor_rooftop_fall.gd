extends "res://tests/test_harbor_building_walkthrough.gd"
## A real controlled walk through the roof gate followed by native gravity.
func run() -> void:
	create_timer(240).timeout.connect(func(): push_error("ROOF_FALL timeout"); finish(3))
	rendered = DisplayServer.get_name() != "headless"
	folder = FIXTURE.output_dir("harbor-rooftop-fall")
	var definition: Dictionary = CATALOG.find("harbor_customs_house")
	for candidate in CATALOG.definitions():
		if candidate.roof_height >= 4.0 and candidate.roof_height < 6.0 and candidate.size.x >= 10.0 and candidate.size.y >= 10.0:
			definition = candidate
			break
	var snapshot := FIXTURE.full_snapshot(definition.return_position+Vector3.UP*.08,true)
	snapshot.campaign.aftermath = {"call_complete":true}
	save_path = FIXTURE.write_fixture(folder,"save.json",snapshot)
	await boot()
	var runtime = world.session.building_entrance
	var deadline := Time.get_ticks_msec()+15000
	while runtime.preparing or not is_instance_valid(runtime.staged):
		if Time.get_ticks_msec()>deadline: check(false,"nearby building staged"); finish(); return
		await physics_frame
	if not check(await world.session.enter_place(definition.id,true),"enter real building"):
		finish(); return
	var room = world.session.room
	for level in range(1,int(definition.floor_count)+1):
		world.player.teleport(room.to_global(room.stair_point())+Vector3.UP*.04)
		if not check(await room.change_floor(level),"reach roof route level "+str(level)):
			finish(); return
	var roof = room.floor_room
	var access: Dictionary = roof.jump_access()
	var landing: Vector3 = roof.to_local(world.player.global_position)
	check(await walk(roof.to_global(Vector3(landing.x,.04,access.point.z))),"walk along roof side")
	check(await walk(roof.to_global(access.point+Vector3.UP*.04)),"walk across roof to gate")
	await photo("roof-gate-before-jump")
	check(world.session.nearest().get("id","")!="building_rooftop_jump","roof has no jump interaction prompt")
	var health: float = world.gameplay.health
	var roof_height: float = world.player.global_position.y
	world.player.automatic_direction = roof.global_basis * access.outward
	world.player.speed = 3.5
	deadline = Time.get_ticks_msec()+5000
	while not runtime.falling and Time.get_ticks_msec()<deadline: await physics_frame
	world.player.automatic_direction = Vector3.ZERO
	if not check(runtime.falling,"walking into edge physically crosses solid parapet"):
		finish(); return
	check(runtime.falling and world.session.state.place_id.is_empty(),"fall belongs to exterior world")
	check(not world.session.save_block_reason().is_empty(),"airborne save blocked")
	await photo("falling-over-street")
	deadline = Time.get_ticks_msec()+8000
	while runtime.falling and Time.get_ticks_msec()<deadline: await physics_frame
	while world.player.air_movement.phase in ["land", "recover"] and Time.get_ticks_msec()<deadline: await physics_frame
	check(not runtime.falling,"landed in street or recovery owns actor")
	check(world.player.global_position.y < roof_height-2.0,"real fall height")
	check(world.gameplay.health < health,"fall applies environmental damage")
	check(not world.player.input_locked and not world.session.is_transition_blocked(),"jump releases controls and transition")
	check(not is_instance_valid(world.session.room),"roof room cleaned up")
	await photo("street-after-fall")
	finish()
