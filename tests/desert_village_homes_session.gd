extends "res://tests/measure/measure_desert_moon_village.gd"
## Native Main: four usable homes, clock-driven occupants, real inventory and isolated disk save.
const HOMES := preload("res://world/desert/village/DesertVillageHomes.gd")
const STORE := preload("res://runtime/SaveStore.gd")
var checks := 0
var save_path := ""
var old_launch := ""
var completed := false

func _initialize() -> void:
	create_timer(540).timeout.connect(func(): failures.append("540s house session watchdog"); finish())
	run.call_deferred()

func check(ok: bool, label: String) -> bool:
	checks+=1
	print("VILLAGE_HOMES ","PASS " if ok else "FAIL ",label)
	if not ok: failures.append(label)
	return ok

func run() -> void:
	if "--no-save" in OS.get_cmdline_user_args() or DisplayServer.get_name()=="headless":
		failures.append("Rendered .NET and real isolated disk writes required"); finish(); return
	seed(6102026)
	root.size=Vector2i(1280,720)
	output=FIXTURE.output_dir("village-homes-session")
	fingerprint=source_fingerprint()
	for source in [get_script().resource_path,"res://world/desert/village/DesertVillageHomes.gd","res://world/desert/village/DesertVillageHomeInterior.gd","res://runtime/desert/DesertVillageLife.gd","res://runtime/desert/DesertVillageResident.gd","res://runtime/desert/DesertVillageResidentModel.gd","res://world/places/NativePlace.gd","res://runtime/GameState.gd"]:
		fingerprint[source]=FileAccess.get_sha256(source)
	print("VILLAGE_HOMES_OUTPUT ",ProjectSettings.globalize_path(output))
	var point := Vector3(-528,.08,-829)
	var data := FIXTURE.full_snapshot(point,true)
	data.region_id="desert"
	data.world.pedestrian={"region":"desert","position":[point.x,point.y,point.z]}
	data.world.time=.5
	data.world.moon_day=4
	save_path=FIXTURE.write_fixture(output,"checkpoint.json",data)
	if not check(not save_path.is_empty(),"valid isolated desert checkpoint"): finish(); return
	var launch=root.get_node("V2Launch")
	old_launch=launch.selected_path
	launch.selected_path=save_path
	world=load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true); world.set_meta("menu_save_path",save_path)
	root.add_child(world); current_scene=world
	if not await ready_world(): finish(); return
	for definition in HOMES.definitions():
		var id: String=definition.id
		set_hour(.5)
		var approach:=Vector3(-528,.08,definition.entry_position.z)
		world.production.region.set_focus(approach)
		world.production.region.prepare_collision_at(approach)
		world.player.teleport(approach)
		for i in 4: await physics_frame
		if not await walk_to(definition.entry_position,12): finish(); return
		check(world.session.nearest().get("place","")==id,id+" doorway publishes the correct entry")
		if not await enter(id): finish(); return
		await create_timer(.7).timeout
		check(residents()==0,id+" empty in daytime")
		check(world.session.position_clear(world.player.global_position),id+" supported clear spawn")
		check(world.camera.locked and world.camera.offset.is_equal_approx(Vector3(0,18,15)),id+" stable native interior camera")
		await photo(id+"-day")
		set_hour(.9)
		await create_timer(.7).timeout
		check(residents()==1,id+" one night resident")
		await photo(id+"-night")
		if "--measure" in OS.get_cmdline_user_args():
			var competing := other_games()
			if competing.is_empty():
				DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
				Engine.max_fps=0
				await create_timer(3).timeout
				await measure(id+"-night")
				var after := other_games()
				reports[-1]["competing_after"]=after
			else: performance_skipped="Other gameplay process prevents interior FPS approval: "+competing
			Engine.max_fps=60
		# Cada coleta é alcançada na posição de piso autoral fisicamente livre.
		# A cobertura varrida de mobília/circulação fica no contrato separado da sala.
		for reward in world.session.room.reward_points:
			check(world.session.position_clear(reward.position+Vector3.UP*.05),id+" pickup capsule has support and clearance")
			world.player.teleport(reward.position+Vector3.UP*.05)
			await create_timer(.35).timeout
			check(world.session.state.world_state.rewards.has(reward.id),"collected "+str(reward.id))
			check(world.session.state.economy.has_reward_receipt(reward.id),"receipt "+str(reward.id))
		world.gameplay.health=70
		for item in ["water","sandwich"]:
			var grid: Dictionary=world.session.state.economy.grid_snapshot()
			var index := -1
			for slot in grid.pockets.size():
				if grid.pockets[slot].id==item: index=slot; break
			var health: float=world.gameplay.health
			check(index>=0 and world.session.field_inventory.consume("pockets",index),id+" can consume "+item+" from inventory")
			check(world.gameplay.health>health,id+" "+item+" restores health")
		set_hour(.25)
		await create_timer(.6).timeout
		check(residents()==0,id+" empties at dawn while player remains inside")
		set_hour(.75)
		await create_timer(.6).timeout
		check(residents()==1,id+" resident returns at 18:00")
		var saved: bool=world.session.save_game()
		if not saved:
			print("SAVE_DIAGNOSTIC ",world.session.save_block_reason()," / ",world.session.last_save_error)
			FileAccess.open(output.path_join("failed-snapshot.json"),FileAccess.WRITE).store_string(JSON.stringify(world.session.state.snapshot(),"\t"))
		if not check(saved,id+" actual isolated save succeeds"): finish(); return
		var disk := STORE.read_valid(save_path)
		check(not disk.is_empty() and disk.place_id==id,id+" disk restores valid interior and reward receipts")
		if id==HOMES.IDS[0] and "--temporal" in OS.get_cmdline_user_args():
			sequence_dir=output.path_join("sequence")
			DirAccess.make_dir_recursive_absolute(sequence_dir)
			phase="cooking-house-night"
			capture_start=Time.get_ticks_usec(); last_render=-1; capturing=true
			RenderingServer.frame_post_draw.connect(capture_frame)
			await create_timer(30).timeout
			capturing=false
			RenderingServer.frame_post_draw.disconnect(capture_frame)
		if id!=HOMES.IDS[-1]:
			if not await leave(): finish(); return
			check(residents()==0,id+" departure releases resident")
	# Recarrega pela substituição de cena da produção e pelo mesmo slot isolado.
	var expected_balance: int=world.session.state.economy.balance
	var prior_instance: int=world.get_instance_id()
	world.session.load_game()
	var reload_deadline:=Time.get_ticks_msec()+15000
	while Time.get_ticks_msec()<reload_deadline:
		await process_frame
		if is_instance_valid(current_scene) and current_scene.get_instance_id()!=prior_instance:
			world=current_scene; break
	if not check(is_instance_valid(world) and world.get_instance_id()!=prior_instance,"cold load replaces actual Main"): finish(); return
	if not await ready_world(): finish(); return
	await create_timer(.7).timeout
	check(world.session.state.place_id==HOMES.IDS[-1] and residents()==1,"cold load restores occupied night home")
	check(world.session.state.economy.balance==expected_balance,"cold load preserves exact balance")
	for definition in HOMES.definitions():
		for reward in definition.rewards: check(world.session.state.world_state.rewards.has(reward.id),"cold load preserves "+str(reward.id))
	for reward in world.session.room.reward_points:
		world.player.teleport(reward.position+Vector3.UP*.05)
		await create_timer(.25).timeout
	check(world.session.state.economy.balance==expected_balance,"collected cash does not respawn on reload")
	if not await leave(): finish(); return
	check(residents()==0,"last exit leaves no resident alive in unloaded room")
	finish()

func ready_world() -> bool:
	var deadline:=Time.get_ticks_msec()+100000
	while Time.get_ticks_msec()<deadline:
		await physics_frame
		if world.session!=null and world.session.ready_for_play and world.production.startup_streaming_settled: break
	if not check(world.session!=null and world.session.ready_for_play and world.production.startup_streaming_settled,"Main ready"): return false
	if not check(is_instance_valid(world.session.desert) and is_instance_valid(world.session.desert.village_life) and is_instance_valid(world.session.field_inventory),"village runtime and inventory fully initialized"): return false
	if world.session.modal: world.session.close_menu()
	world.player.controlled_automatically=true
	world.player.automatic_direction=Vector3.ZERO
	world.session.weather.weather_state=0
	world.session.weather.weather_timer=3600
	world.dispatch.router.nearest_edge(world.player.global_position)
	return check(world.production.store.path==save_path and not world.production.no_save and not world.production.save_invalid and world.dispatch.router._native!=null,"isolated writable slot and compiled C# routing")

func set_hour(hour: float) -> void:
	world.session.weather.time_of_day=hour
	world.session.state.world_state.time=hour
	world.session.weather._update()

func residents() -> int:
	var count := 0
	for actor in get_nodes_in_group("desert_village_resident"):
		if is_instance_valid(actor) and not actor.is_queued_for_deletion(): count+=1
	return count

func walk_to(point: Vector3, seconds: float) -> bool:
	var deadline:=Time.get_ticks_msec()+int(seconds*1000)
	while Time.get_ticks_msec()<deadline:
		var delta: Vector3=point-world.player.global_position
		delta.y=0
		if delta.length()<.5: break
		world.player.automatic_direction=delta.normalized()
		await physics_frame
	world.player.automatic_direction=Vector3.ZERO
	return check(Vector2(world.player.global_position.x,world.player.global_position.z).distance_to(Vector2(point.x,point.z))<.65,"physical walk to home porch")

func interact_input() -> void:
	var event:=InputEventAction.new()
	event.action="interact"; event.pressed=true
	Input.parse_input_event(event)
	await process_frame
	event=InputEventAction.new(); event.action="interact"; event.pressed=false
	Input.parse_input_event(event)

func enter(id: String) -> bool:
	await interact_input()
	var deadline:=Time.get_ticks_msec()+12000
	while Time.get_ticks_msec()<deadline:
		await physics_frame
		if world.session.state.place_id==id and not world.session.is_transition_blocked(): break
	return check(world.session.state.place_id==id and not world.player.input_locked,id+" actual input enters and returns control")

func leave() -> bool:
	var point: Vector3=world.session.room.exit_position
	world.player.teleport(point+Vector3.UP*.02)
	for i in 3: await physics_frame
	await interact_input()
	var deadline:=Time.get_ticks_msec()+12000
	while Time.get_ticks_msec()<deadline:
		await physics_frame
		if world.session.state.place_id.is_empty() and not world.session.is_transition_blocked(): break
	await create_timer(.35).timeout
	return check(world.session.state.place_id.is_empty() and not world.player.input_locked and world.session.position_clear(world.player.global_position),"actual exit returns to clear exterior with control")

func photo(id: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(id+".png"))

func finish() -> void:
	if completed: return
	completed=true
	if not old_launch.is_empty(): root.get_node("V2Launch").selected_path=old_launch
	if not output.is_empty():
		FileAccess.open(output.path_join("homes-report.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"scenarios":reports,"temporal_frames":frames,"skipped_render_frames":skipped,"performance_limitation":performance_skipped,"save":save_path,"source_stable":fingerprint==source_fingerprint(fingerprint),"source_sha256_start":fingerprint,"source_sha256_end":source_fingerprint(fingerprint),"engine":Engine.get_version_info().string,"renderer":RenderingServer.get_current_rendering_method(),"gpu":RenderingServer.get_video_adapter_name(),"resolution":str(root.size),"notes":"Real Main/input/native routing. Entry porch physically walked. Interior pickup poses are fixture placements; separate swept physics/depth contracts cover furniture. No personal saves used. 30s uncapped per-room measurements separate from image capture; comparison to a controlled before-baseline is unavailable."},"\t"))
	print("VILLAGE_HOMES_DONE ",output," checks=",checks," failures=",failures)
	quit(0 if failures.is_empty() else 1)
