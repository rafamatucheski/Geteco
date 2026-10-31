extends "res://tests/test_harbor_building_walkthrough.gd"
## Portão da campanha, varanda física, entrada automática, evento de capítulo e revisita.
## O checkpoint é isolado; este teste não simula a corrida anterior.
const LEADER := "cobra_leader_house"

func wait_condition(predicate: Callable, seconds := 8.0) -> bool:
	var deadline := Time.get_ticks_msec()+int(seconds*1000)
	while Time.get_ticks_msec()<deadline:
		await physics_frame
		if predicate.call(): return true
	return false

func enter_by_walking(definition: Dictionary) -> bool:
	var outward := Vector3.BACK.rotated(Vector3.UP,float(definition.editor_rotation))
	world.player.teleport(definition.return_position+Vector3.UP*.08)
	world.player.automatic_direction = Vector3.ZERO
	await create_timer(.9).timeout
	check(world.session.nearest().get("id","")!="enter","no orange entrance action at the actual threshold")
	check(world.session.state.place_id.is_empty(),"standing near unlocked door does not transfer")
	await photo("leader-open-threshold")
	world.player.automatic_direction = -outward
	var entered := await wait_condition(func(): return world.session.state.place_id==LEADER)
	world.player.automatic_direction = Vector3.ZERO
	if not entered:
		print("LEADER_WALK_BLOCKED player=",world.player.global_position," door=",definition.walkup_door_position)
		for index in world.player.get_slide_collision_count():
			var hit = world.player.get_slide_collision(index)
			print("LEADER_BLOCKER ",hit.get_collider().get_path()," at=",hit.get_position())
	check(entered,"real capsule walks over porch steps and enters the house")
	if not entered: return false
	await wait_condition(func(): return not world.session.weapon_shop_entrance._entering)
	check(not world.player.input_locked and world.session.position_clear(world.player.global_position),"interior body and controls restored")
	check(not world.session.marker.visible,"automatic arrival has no floor marker")
	return true

func leave_by_walking() -> bool:
	world.player.teleport(world.session.room.exit_position+Vector3(0,.08,-.8))
	for frame in 3: await physics_frame
	check(world.session.nearest().get("id","")!="exit","interior exit needs no action")
	world.player.automatic_direction = Vector3.BACK
	var exited := await wait_condition(func(): return world.session.state.place_id.is_empty())
	world.player.automatic_direction = Vector3.ZERO
	check(exited,"walking exits through the interior doorway")
	if not exited: return false
	await wait_condition(func(): return not world.session.weapon_shop_entrance._leaving)
	check(not world.player.input_locked and world.session.position_clear(world.player.global_position+Vector3.UP*.04),"outside return is clear and controllable")
	await create_timer(.3).timeout
	check(world.session.state.place_id.is_empty(),"return does not loop into entrance")
	return true

func run() -> void:
	create_timer(150).timeout.connect(func(): push_error("LEADER_WALK timeout"); finish(3))
	rendered = DisplayServer.get_name()!="headless"
	folder = FIXTURE.output_dir("cobra-leader-walkup")
	var definition: Dictionary = preload("res://world/places/PlaceCatalog.gd").get_definition(LEADER)
	var snapshot := FIXTURE.full_snapshot(definition.return_position+Vector3.UP*.08,false)
	snapshot.campaign.step = 0
	save_path = FIXTURE.write_fixture(folder,"save.json",snapshot)
	check(not save_path.is_empty(),"valid pre-race checkpoint created")
	await boot()
	check(world.production.no_save and world.production.loaded_save,"isolated no-save Main loaded")
	world.dispatch.router.nearest_edge(world.player.global_position)
	check(world.dispatch.router._native!=null,"native C# runtime active")
	var access = world.session.weapon_shop_entrance
	check(access.handles_place(LEADER),"leader house uses shared walking access")
	var facade: Node3D
	var deadline := Time.get_ticks_msec()+12000
	while Time.get_ticks_msec()<deadline:
		for node in get_nodes_in_group("v2_walkin_facade"):
			if node.get_meta("place_id","")==LEADER: facade=node
		if is_instance_valid(facade): break
		await physics_frame
	if not check(is_instance_valid(facade),"actual edited leader facade streamed"): finish(); return
	var outward := Vector3.BACK.rotated(Vector3.UP,float(definition.editor_rotation))
	var door: Vector3 = definition.walkup_door_position
	check(facade.hinge.global_position.distance_to(door+Vector3.LEFT.rotated(Vector3.UP,float(definition.editor_rotation))*.475)<.01,"catalog door matches actual edited hinge")
	check(not await world.session.enter_place(LEADER,false),"direct entry preserves pre-victory campaign gate")
	world.player.automatic_direction = -outward
	await create_timer(1.7).timeout
	world.player.automatic_direction = Vector3.ZERO
	check(world.session.state.place_id.is_empty() and facade.open_amount<.01,"pre-victory walking preserves the closed physical gate")
	check(world.player.global_position.y>.28,"walking climbed the authored porch, not through it")
	check((world.player.global_position-door).dot(outward)>.28,"locked leaf stops the full player capsule")
	await photo("leader-locked-porch")
	var unlocked: Dictionary = world.session.state.campaign.snapshot()
	unlocked.step = 6
	check(world.session.state.campaign.restore_snapshot(unlocked),"valid post-race checkpoint accepted")
	if not await enter_by_walking(definition): finish(); return
	check(world.session.state.campaign.step==7,"walking admission advances the actual leader-house event")
	await photo("leader-walked-inside")
	var completed: Dictionary = FIXTURE.final_event(world.session.state.campaign)
	check(completed.ok and world.session.state.campaign.has_progress("cobra_finale"),"authored final event unlocks revisits")
	world.session.state.campaign.complete_aftermath_call()
	if not await leave_by_walking(): finish(); return
	if not await enter_by_walking(definition): finish(); return
	check(world.session.state.campaign.has_progress("cobra_finale"),"completed campaign remains accessible without restarting mission")
	await photo("leader-revisit")
	await leave_by_walking()
	finish()

func finish(code := -1) -> void:
	FileAccess.open(folder.path_join("result.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"rendered":rendered},"\t"))
	print("COBRA_LEADER_WALKUP ",folder," checks=",checks," failures=",failures)
	quit((0 if failures.is_empty() else 1) if code<0 else code)
