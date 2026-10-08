extends "res://tests/test_harbor_building_walkthrough.gd"
## Real Main/FullSession death and rescue interrupt both sides of a floor commit.
## These finite cases use an isolated checkpoint and never save user data.

func _observe_change(room: Node3D, destination: int, result: Dictionary) -> void:
	result.ok = await room.change_floor(destination)
	result.completed = true

func _observe_prepare(runtime: Node, id: String, result: Dictionary) -> void:
	result.room = await runtime.prepare_room(id,true)
	result.completed = true

func _enter_building(definition: Dictionary) -> Node3D:
	var runtime = world.session.building_entrance
	var outward := Basis(Vector3.UP,float(definition.exterior_rotation))*Vector3.BACK
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	world.player.speed = 5.0
	world.production.region.set_focus(definition.entry_position)
	world.player.teleport(definition.entry_position+outward*1.6+Vector3.UP*.08)
	var deadline := Time.get_ticks_msec()+15000
	while Time.get_ticks_msec()<deadline:
		await physics_frame
		if is_instance_valid(runtime.staged) and runtime.staged.definition.id == definition.id and not runtime.preparing: break
	if not check(is_instance_valid(runtime.staged) and not runtime.preparing,"recovery building prepared"): return null
	var candidate: Node3D = runtime.staged
	if not check(await walk(candidate.spawn_position+Vector3.UP*.04),"recovery walking admission"): return null
	for frame in 3: await physics_frame
	if not check(world.session.room == candidate and world.session.state.place_id == definition.id,"recovery continuous admission owns room"): return null
	check(candidate.floor_index == 0,"fresh entry starts on ground floor after recovery")
	return candidate

func _wait_for_rescue(label: String, former_facade: Node3D) -> bool:
	var deadline := Time.get_ticks_msec()+18000
	while Time.get_ticks_msec()<deadline:
		await physics_frame
		if world.gameplay.health>0 and not world.session.rescue_pending and not world.session.respawn_busy: break
	var rescued: bool = world.gameplay.health>0 and not world.session.rescue_pending and not world.session.respawn_busy
	check(rescued,label+" real rescue completes within finite deadline")
	if not rescued: return false
	check(world.session.state.place_id.is_empty() and not is_instance_valid(world.session.room),label+" old interior released")
	check(world.session.transition_kind.is_empty() and not world.session.vehicle_transition_busy,label+" transition token released")
	check(not world.player.input_locked and world.player.is_physics_processing() and world.player.collision_mask == 7,label+" player control and physical capsule restored")
	check(world.session.position_clear(world.player.global_position),label+" rescued body has free supported spawn")
	check(not world.camera.locked and world.camera.target == world.player,label+" outdoor camera restored")
	check(not world.session.building_entrance.sightline.debug_snapshot().active,label+" railway presentation restored after rescue")
	check(not world.session.door_transition.veil.visible,label+" no abandoned floor curtain")
	var runtime = world.session.building_entrance
	check(not runtime.falling and not runtime.crossing and not runtime.preparing,label+" building runtime has no stale operation")
	check(not is_instance_valid(runtime.staged) and not is_instance_valid(runtime.facade),label+" staged ownership released")
	if is_instance_valid(former_facade): check(not former_facade.access_ready,label+" facade shell restored")
	return true

func run() -> void:
	create_timer(180).timeout.connect(func(): push_error("BUILDING_RECOVERY timeout"); finish(3))
	rendered = false
	folder = FIXTURE.output_dir("harbor-building-recovery")
	var definition: Dictionary = CATALOG.find("harbor_customs_house")
	var snapshot := FIXTURE.full_snapshot(definition.return_position+Vector3.UP*.08,true)
	snapshot.campaign.aftermath = {"call_complete":true}
	save_path = FIXTURE.write_fixture(folder,"save.json",snapshot)
	await boot()
	check(world.production.no_save,"no-save process keeps user and fixture checkpoints unchanged")
	check(world.production.loaded_save and not world.production.save_invalid,"isolated valid checkpoint loaded")
	world.dispatch.router.nearest_edge(world.player.global_position)
	check(world.dispatch.router._native != null,"Godot .NET native C# route path active")
	if not check(int(definition.floor_count)>1,"fixture contains an upper inhabited floor"): finish(); return
	for phase in ["before_commit","after_commit"]:
		var room: Node3D = await _enter_building(definition)
		if room == null: finish(); return
		world.player.teleport(room.to_global(room.stair_point())+Vector3.UP*.04)
		var former_facade: Node3D = world.session.building_entrance.facade
		var outcome := {"completed":false,"ok":false}
		_observe_change(room,1,outcome)
		var deadline := Time.get_ticks_msec()+4000
		while Time.get_ticks_msec()<deadline:
			if world.session.transition_kind == "building_stairs" and (phase == "before_commit" or room.floor_index == 1): break
			await physics_frame
		check(world.session.transition_kind == "building_stairs",phase+" death occurs inside owned floor transition")
		check(room.floor_index == (0 if phase == "before_commit" else 1),phase+" expected commit boundary observed")
		world.gameplay.damage_environment(1000.0)
		check(world.gameplay.health == 0 and world.session.rescue_pending,phase+" real gameplay death starts rescue")
		if not await _wait_for_rescue(phase,former_facade): finish(); return
		check(outcome.completed and not outcome.ok,phase+" interrupted stairs report failure and finish")
		await physics_frame
		check(get_nodes_in_group("building_resident").is_empty(),phase+" old residents released")
	# A third visit proves that cancellation did not poison floor ownership.
	var returned: Node3D = await _enter_building(definition)
	if returned == null: finish(); return
	world.player.teleport(returned.to_global(returned.stair_point())+Vector3.UP*.04)
	check(await returned.change_floor(1),"reentry can ascend after both interruptions")
	world.player.teleport(returned.to_global(returned.stair_point())+Vector3.UP*.04)
	check(await returned.change_floor(0),"reentry can descend after both interruptions")
	world.player.teleport(returned.spawn_position+Vector3.UP*.04)
	check(await walk(definition.return_position+Vector3.UP*.04),"reentry can walk out normally")
	check(world.session.state.place_id.is_empty(),"reentry leaves no active room")
	# Interrupt a street-side preload after the facade opens but before room
	# admission. A generation/health change must dispose the candidate.
	var runtime = world.session.building_entrance
	runtime.reset()
	await physics_frame
	var preparation := {"completed":false,"room":null}
	_observe_prepare(runtime,str(definition.id),preparation)
	check(runtime.preparing,"street preload asynchronous window observed")
	var prep_facade: Node3D = runtime.facade
	world.gameplay.damage_environment(1000.0)
	if not await _wait_for_rescue("preparation",prep_facade): finish(); return
	check(preparation.completed and not is_instance_valid(preparation.room),"interrupted preparation returns no candidate")
	finish()

func finish(code := -1) -> void:
	FileAccess.open(folder.path_join("result.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"rendered":false},"\t"))
	print("HARBOR_BUILDING_RECOVERY ",folder," checks=",checks," failures=",failures)
	quit((0 if failures.is_empty() else 1) if code < 0 else code)
