extends "res://tests/test_arcade_session.gd"
## Restauração fria do Main a partir dos bytes gravados por test_arcade_session.
func run() -> void:
	create_timer(120).timeout.connect(func(): quit(3))
	var source := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--arcade-save="): source = arg.trim_prefix("--arcade-save=")
	if not source.begins_with("res://evidence/arcade-session-"): quit(4); return
	var snapshot := preload("res://runtime/SaveStore.gd").read_valid(source)
	if snapshot.is_empty(): quit(5); return
	folder = FIXTURE.output_dir("arcade-restore")
	world = load("res://Main.tscn").instantiate()
	world.set_meta("menu_save_path",FIXTURE.write_fixture(folder,"save.json",snapshot))
	root.add_child(world)
	current_scene = world
	while world.session == null or not world.session.ready_for_play or not world.production.startup_streaming_settled: await physics_frame
	var session = world.session
	check(session.state.place_id == PLACE.ID,"cold save restores Fagulha interior")
	check(session.room_npcs.size() == 2,"cold restore reinstalls exactly two residents")
	check(not session.arcade.active and not session.modal and not world.player.input_locked,"cold restore returns ordinary player controls")
	check(session.position_clear(world.player.global_position+Vector3.UP*.04),"cold restore has full body clearance")
	for id in ["pinball","blocks","racer","fighter"]: check(session.arcade.records.get(id,0)==1234,"cold restore record "+id)
	check(await walk(session.room.to_global(Vector3(0,0,-1.1))),"restored player reaches cabinet aisle")
	check(await walk(session.room.interaction_points.arcade_blocks),"restored player reaches blocks")
	check(session.arcade.perform("blocks"),"play after cold load")
	world.gameplay.health -= 1
	var interruption_deadline := Time.get_ticks_msec()+1000
	while session.arcade.active and Time.get_ticks_msec()<interruption_deadline: await process_frame
	check(not session.arcade.active and not session.modal and not world.player.input_locked,"damage interrupts on next idle frame and restores controls")
	check(await walk(session.room.to_global(Vector3(0,0,-1.1))),"return to central aisle")
	check(await walk(session.room.to_global(Vector3(0,0,3.5))),"walk clear central path after restore")
	var previous: int = session.state.economy.inventory.get("first_aid",0)
	check(await walk(session.room.to_global(Vector3(-4.1,0,3.5))),"walk onto useful pickup")
	await frames(5)
	check(session.state.economy.inventory.get("first_aid",0)==previous+1,"first aid collected on foot")
	check("fagulha_first_aid" in session.state.world_state.rewards,"pickup has persistent receipt")
	check(await walk(session.room.to_global(Vector3(0,0,3.5))),"return around furniture")
	check(await walk(session.room.exit_position+Vector3.FORWARD*.8),"walk to restored exit interaction zone")
	check(session.nearest().get("id","") == "exit","restored exit action available at approach")
	check(await session.interact(),"leave cold-restored room")
	var definition := PLACE.definition_data()
	check(world.player.global_position.distance_to(definition.return_position)<2.5,"cold restore returns to original storefront")
	check(await walk(definition.entry_position),"walk back to shop")
	check(await session.interact(),"reenter after pickup")
	await settle_transition()
	check(await walk(session.room.to_global(Vector3(-4.1,0,3.5))),"revisit pickup floor")
	await frames(5)
	check(session.state.economy.inventory.get("first_aid",0)==previous+1,"reentry cannot duplicate first aid")
	await photo("restored-room")
	finish()
