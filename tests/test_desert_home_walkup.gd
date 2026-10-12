extends "res://tests/desert_village_homes_session.gd"

func run() -> void:
	output=FIXTURE.output_dir("desert-home-walkup")
	fingerprint=source_fingerprint()
	var point := Vector3(-528,.08,-829)
	var data := FIXTURE.full_snapshot(point,true)
	data.region_id="desert"
	data.world.pedestrian={"region":"desert","position":[point.x,point.y,point.z]}
	save_path=FIXTURE.write_fixture(output,"checkpoint.json",data)
	world=load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	world.set_meta("menu_save_path",save_path)
	root.add_child(world)
	current_scene=world
	if not await ready_world(): finish(); return
	for definition in HOMES.definitions():
		var id: String=definition.id
		world.production.region.set_focus(definition.entry_position)
		world.production.region.prepare_collision_at(definition.entry_position)
		world.player.teleport(definition.return_position)
		world.player.automatic_direction=Vector3.ZERO
		await create_timer(2).timeout
		var access=world.session.weapon_shop_entrance
		check(world.session.state.place_id.is_empty(),id+" standing still does not enter")
		check(is_instance_valid(access._facade) and access._door_amount < .01,id+" stationary closed door")
		await photo(id+"-closed")
		world.player.automatic_direction=access._inward(id)
		var deadline := Time.get_ticks_msec()+12000
		while Time.get_ticks_msec()<deadline and world.session.state.place_id != id:
			await physics_frame
		world.player.automatic_direction=Vector3.ZERO
		await create_timer(1).timeout
		if not check(world.session.state.place_id==id,id+" enters by pushing without interact"): finish(); return
		check(world.session.position_clear(world.player.global_position),id+" supported admission")
		await photo(id+"-inside")
		world.player.automatic_direction=Vector3.BACK
		deadline=Time.get_ticks_msec()+12000
		while Time.get_ticks_msec()<deadline and not world.session.state.place_id.is_empty():
			await physics_frame
		world.player.automatic_direction=Vector3.ZERO
		await create_timer(1).timeout
		if not check(world.session.state.place_id.is_empty(),id+" walking exits before floor edge"): finish(); return
		check(world.session.position_clear(world.player.global_position) and world.player.global_position.y > -.2,id+" exterior support without falling")
		await photo(id+"-returned")
	finish()
