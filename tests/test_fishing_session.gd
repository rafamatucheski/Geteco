extends SceneTree
## Productive rendered venue walk, UI selection, input loop and isolated save.
const FIXTURE := preload("res://tests/fixtures/NorthGatewayFixtures.gd")
const STATE := preload("res://runtime/GameState.gd")
const FISH_STATE := preload("res://activities/fishing/FishingState.gd")
const STORE := preload("res://runtime/SaveStore.gd")
const LOCATION := preload("res://runtime/FishingLocation.gd")
var world
var folder := ""
var checks := 0
var failures: Array[String] = []

func _initialize() -> void: run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	print("FISHING_SESSION ","PASS " if value else "FAIL ",message)
	if not value: failures.append(message)

func press(action: String, down := true) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = down
	world.session._input(event)

func capture(filename: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(folder.path_join(filename+".png"))

func walk(point: Vector3) -> bool:
	for frame in 600:
		var direction: Vector3 = point-world.player.global_position
		direction.y = 0
		if direction.length() < .25: break
		world.player.automatic_direction = direction.normalized()
		await physics_frame
	world.player.automatic_direction = Vector3.ZERO
	var distance: Vector3 = point-world.player.global_position
	distance.y = 0
	return distance.length() < .35

func residency_cycle() -> void:
	# Exercise the real proximity owner while staying in Harbor's valid state.
	# Each actor is admitted on a separate render frame, not a wall-clock timer.
	var return_point: Vector3 = world.player.global_position
	var away := Vector3(132,.15,72)
	world.production.region.set_focus(away)
	world.production.region.prepare_collision_at(away)
	world.player.teleport(away)
	world.session.fishing_runtime.refresh()
	for frame in 8: await process_frame
	check(not is_instance_valid(world.session.fishing_runtime.site) and get_nodes_in_group("fishing_angler").is_empty(),"leaving lake residency frees venue and anglers")
	world.production.region.set_focus(return_point)
	world.production.region.prepare_collision_at(return_point)
	world.player.teleport(return_point)
	world.session.fishing_runtime.refresh()
	for frame in 8: await process_frame
	var count := get_nodes_in_group("fishing_angler").size()
	check(count==5,"return mounts exactly five anglers (actual %d)"%count)

func run() -> void:
	create_timer(260).timeout.connect(func(): push_error("Fishing session timeout"); quit(3))
	folder = FIXTURE.output_dir("fishing-session")
	var data := FIXTURE.full_snapshot(LOCATION.ENTRY+Vector3.UP*.1,true)
	data.economy.balance = 500
	var path := FIXTURE.write_fixture(folder,"isolated-save.json",data)
	world = load("res://Main.tscn").instantiate()
	world.set_meta("menu_save_path",path)
	root.add_child(world)
	current_scene = world
	while world.session == null or not world.session.ready_for_play or not world.production.startup_streaming_settled: await physics_frame
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	world.camera.set_process_unhandled_input(false)
	world.driving.set_process_unhandled_input(false)
	world.production.region.set_focus(LOCATION.ENTRY+Vector3.UP*.1)
	world.production.region.prepare_collision_at(LOCATION.ENTRY+Vector3.UP*.1)
	world.player.teleport(LOCATION.ENTRY+Vector3.UP*.1)
	world.session.fishing_runtime.refresh()
	await create_timer(2).timeout
	# The completed-campaign fixture still has the final phone epilogue pending.
	# A player must finish that dialogue before walking; exercise its actual input.
	for line in 12:
		if not world.session.dialogue_open: break
		press("interact")
		await physics_frame
	check(not world.session.modal,"pending campaign epilogue releases controls normally")
	var site = world.session.fishing_runtime.site
	var fishing = world.session.fishing
	check(is_instance_valid(site) and fishing.site == site,"production session owns one fishing venue")
	if not is_instance_valid(site): quit(1); return
	world.dispatch.router.nearest_edge(world.player.global_position)
	check(world.dispatch.router._native != null,"production C# router loaded")
	if "--lifecycle-only" in OS.get_cmdline_user_args():
		await residency_cycle()
		await capture("return")
		FileAccess.open(folder.path_join("result.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"scenario":"residency"},"\t"))
		print("FISHING_LIFECYCLE_RESULT ",folder," checks=",checks," failures=",failures)
		quit(1 if not failures.is_empty() else 0)
		return
	check(await walk(site.entry_position()),"walk through entrance to reception in real Harbor")
	await capture("reception")
	check(await world.session.interact() and world.session.modal,"real interaction opens fishing menu")
	await capture("menu")
	var selected := false
	for child in world.session.column.get_children():
		if child is Button and child.text.begins_with("Torneio da lagoa"):
			child.pressed.emit()
			selected = true
			break
	check(selected and fishing.active and fishing.phase == "walking","menu buys competition and keeps walking available")
	if not fishing.active: quit(1); return
	fishing._rng.seed = 12345
	for waypoint in site.approach_waypoints(0):
		check(await walk(waypoint),"walk along dry approach "+str(waypoint))
	check(await world.session.interact() and fishing.controls_locked(),"E at actual platform equips rod")
	check(not world.session.state.can_attack() and world.session.blocks_driving_change(),"rod blocks combat and vehicle entry")
	check(not world.session.save_block_reason().is_empty(),"active tournament cannot save a partial attempt")
	if not fishing.controls_locked(): quit(1); return
	await create_timer(.3).timeout
	await capture("rod-ready")
	var clock_before: float = fishing.remaining
	paused = true
	await create_timer(.3,true,false,true).timeout
	check(is_equal_approx(clock_before,fishing.remaining),"pause preserves competition time")
	paused = false
	var reel := false
	var photographed := {}
	var trace := []
	var old_phase := ""
	var observed_water_fish := false
	var observed_landing := false
	var observed_release := false
	var landing_id := 0
	var catches_before_landing := 0
	var simulation_start := Time.get_ticks_msec()
	while fishing.active and Time.get_ticks_msec()-simulation_start < 110000:
		if fishing.phase != old_phase:
			old_phase = fishing.phase
			trace.append({"ms":Time.get_ticks_msec()-simulation_start,"phase":old_phase,"tension":fishing.fight.tension,"progress":fishing.fight.progress})
			if old_phase == "landing":
				observed_landing = true
				landing_id = fishing._rod._fish.get_instance_id()
				catches_before_landing = fishing.caught
			if old_phase == "caught" and landing_id != 0:
				check(fishing._rod._fish.get_instance_id() == landing_id, "the hooked fish is the same visible fish lifted from water")
				check(fishing.caught == catches_before_landing + 1, "landing awards exactly one catch after extraction")
				landing_id = 0
			if old_phase == "releasing": observed_release = true
		if fishing.phase == "reeling" and is_instance_valid(fishing._rod):
			observed_water_fish = observed_water_fish or fishing._rod._fish.visible
		if fishing.phase == "landing" and not photographed.has("landing"):
			check(fishing.caught == catches_before_landing, "fish is not awarded while still being lifted")
		match str(fishing.phase):
			"ready": press("interact"); reel = true
			"charging":
				if fishing._charge > .7: press("interact",false); reel = false
			"bite": press("interact"); reel = true
			"reeling":
				if reel and fishing.fight.tension > .72: press("interact",false); reel = false
				elif not reel and fishing.fight.tension < .30: press("interact"); reel = true
			"caught":
				if reel: press("interact",false); reel = false
				if fishing._phase_time >= .6:
					press("reload")
					press("reload",false)
			"missed", "line_broke":
				if reel: press("interact",false); reel = false
		if fishing.phase in ["waiting","bite","hooking","reeling","landing","caught","releasing"] and not photographed.has(fishing.phase):
			photographed[fishing.phase] = true
			await capture("fishing-"+fishing.phase)
		await physics_frame
	check(not fishing.active and fishing.last_result.get("finished",false),"full 90 second competition settles after resolving any held catch")
	var competition_result: Dictionary = fishing.last_result.duplicate(true)
	check(fishing.caught > 0 and fishing.best > 0,"casts and controlled reeling land real generated fish")
	check(observed_water_fish and observed_landing, "normal gameplay enables the fish node and extraction phase (pixels reviewed separately)")
	check(observed_release, "release input resolves the held catch through its animation")
	check(not world.player.input_locked and not fishing.controls_locked(),"completion restores movement and frees rod")
	check(world.get_viewport().get_camera_3d() == world.camera and not world.camera.locked, "tournament restores the ordinary gameplay camera")
	var expected: int = 490 + (100 if fishing.last_result.get("won",false) else 0)
	check(world.session.state.economy.balance == expected,"cash equals entry debit plus exactly the earned prize")
	check(FISH_STATE.claim(world.session.state.world_state,world.session.state.economy)==0,"completed award cannot be claimed twice")
	world.production.no_save = false
	check(world.session.save_game(),"session writes completed record to isolated checkpoint")
	world.production.no_save = true
	var restored := STATE.new()
	check(restored.restore_snapshot(STORE.read_valid(path)) and restored.economy.balance==expected,"disk restore keeps fishing result and wallet consistent")
	check(FISH_STATE.data(restored.world_state).best==fishing.best,"best catch survives real JSON storage")
	await capture("result")
	# Reenter freely at the same physical station, then exercise input cancellation.
	check(fishing.start(-1) and fishing.controls_locked(),"reenter after tournament without a stuck menu or actor")
	press("exit_vehicle")
	check(not fishing.active and not world.player.input_locked,"F cancellation restores controls")
	check(world.get_viewport().get_camera_3d() == world.camera and not world.camera.locked, "cancellation restores camera ownership and lock")
	check(fishing.start(-1),"next visit starts after cancellation")
	var token: int = world.session._begin_transition("fishing_test")
	check(token>0 and not fishing.active,"position transition cancels rod before moving the actor")
	world.session._finish_transition(token)
	await residency_cycle()
	var map := preload("res://ui/hud/WorldMapData.gd").new()
	map.collect(world.production)
	check(map.markers.any(func(marker): return marker.id=="fishing" and marker.kind=="fishing"),"world map exposes Lago Sereno fishing destination")
	FileAccess.open(folder.path_join("result.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"competition":competition_result,"trace":trace},"\t"))
	print("FISHING_SESSION_RESULT ",folder," checks=",checks," failures=",failures)
	world.queue_free()
	for frame in 8: await process_frame
	quit(1 if not failures.is_empty() else 0)
