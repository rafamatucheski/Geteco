extends "res://tests/test_upside_world_session.gd"
## Three real Main interruptions. Alcohol and paid stock are explicit boundary
## fixtures; the ordinary session test already exercises four timed real drinks.
var lifecycle: Array[Dictionary] = []

func run() -> void:
	var args := OS.get_cmdline_user_args()
	if DisplayServer.get_name() == "headless" or "--no-save" not in args or not OS.get_environment("HARBOR_NO_CSHARP").is_empty():
		push_error("Rendered Godot .NET with --no-save required"); quit(2); return
	if "--benchmark" in args or "--capture" in args:
		push_error("Lifecycle acceptance has no capture or benchmark mode"); quit(2); return
	mode = "lifecycle"
	create_timer(240,true).timeout.connect(func(): check(false,"finite240s lifecycle deadline"); finish(3))
	root.size = Vector2i(1280,720)
	folder = FIXTURE.output_dir("upside-world-lifecycle")
	original_source = fingerprint()
	original_source["res://tests/test_upside_world_lifecycle.gd"] = FileAccess.get_sha256("res://tests/test_upside_world_lifecycle.gd")
	original_max_fps = Engine.max_fps
	original_vsync = DisplayServer.window_get_vsync_mode()
	var snapshot := FIXTURE.full_snapshot(LAYOUT.HAUNTED_ENTRY + Vector3(0,0,1.1),true)
	snapshot.campaign.aftermath = {"call_complete":true}
	save_path = FIXTURE.write_fixture(folder,"checkpoint.json",snapshot)
	if not check(not save_path.is_empty(),"isolated lifecycle checkpoint created"): finish(); return
	await boot()
	if not check(is_instance_valid(runtime) and world.session.ready_for_play,"Main lifecycle ready"): finish(); return
	check(world.production.store.path == save_path and not world.production.save_invalid,"lifecycle uses only the isolated save")
	world.dispatch.router.nearest_edge(world.player.global_position)
	check(world.dispatch.router._native != null,"compiled C# router active for lifecycle")
	world.session.state.economy.grant_reward("upside_lifecycle_funds",500)
	check(world.session.wine.model.purchase(WINE_ID,world.session.state.economy).ok,"paid wine inventory fixture established")
	var stock: Dictionary = world.session.wine.snapshot().servings

	if not await chaos_entry("death"): finish(); return
	world.gameplay.damage_environment(1000.0)
	check(world.gameplay.health == 0.0 and world.session.rescue_pending,"real fatal environment damage starts the actual rescue flow")
	check(not runtime.busy() and world.player.input_locked and not world.player.is_physics_processing(),"death cancels illusion and preserves the dead actor's locks")
	if not await await_recovery("death",stock): finish(); return
	await photo("death-recovered")

	if not await chaos_entry("arrest"): finish(); return
	# The crime case is real; no private call to _on_arrest or _respawn bypasses
	# the signal ordering that must keep the input lock during presentation.
	world.gameplay.register_crime(12,world.player.global_position,"theft")
	check(world.gameplay.police_can_arrest(),"a real low-level case permits custody")
	if not check(world.gameplay.arrest_player(),"actual arrest_player emits the real custody signal"): finish(); return
	check(world.session.arrest_pending and world.player.input_locked and not runtime.busy(),"arrest signal preserves the lock immediately after illusion cancellation")
	await create_timer(.35,true).timeout
	check(world.session.arrest_pending and world.player.input_locked and world.gameplay.health > 0,"custody presentation retains its input lock and living player")
	check(world.session.position_clear(world.player.global_position),"arrest cancellation restores supported original-room ground")
	await photo("arrest-presentation")
	if not await await_recovery("arrest",stock): finish(); return
	await photo("arrest-recovered")

	if not await chaos_entry("released-load-menu"): finish(); return
	var deadline := Time.get_ticks_msec() + 26000
	while runtime.busy() and not runtime._released and Time.get_ticks_msec() < deadline: await process_frame
	if not check(runtime.busy() and runtime._released and world.session.transition_kind == "leave_place","ordinary duration reaches the live released-to-departure handoff"): finish(); return
	# Reproduce a live occupancy race AFTER candidate approval, during the
	# normal departure fade. The physical blocker covers local fallback offsets.
	var blocked_destination: Vector3 = world.session.return_point
	var blocker := StaticBody3D.new()
	blocker.name = "ReturnRaceFixture"
	blocker.collision_layer = 1
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(10,4,10)
	collision.shape = box
	blocker.add_child(collision)
	blocker.position = blocked_destination + Vector3.UP*2.0
	world.add_child(blocker)
	var instance_id: int = world.get_instance_id()
	var generation: int = world.session.transition_generation
	var owned_token: int = runtime.token()
	var curtain: CanvasLayer = runtime.veil
	paused = true
	world.session.load_game()
	world.session.return_to_main_menu()
	check(runtime.busy() and runtime._released and runtime.token() == owned_token and runtime.veil == curtain,"load and main-menu requests retain the pending illusion completion and veil")
	check(world.session.transition_generation == generation and world.session.transition_kind == "leave_place","refused requests do not alter the departing owner's generation")
	await create_timer(.12,true).timeout
	check(is_instance_valid(world) and not world.is_queued_for_deletion() and current_scene == world and world.get_instance_id() == instance_id,"paused handoff refuses both scene-replacement requests")
	paused = false
	deadline = Time.get_ticks_msec() + 20000
	while is_instance_valid(runtime) and runtime.busy() and Time.get_ticks_msec() < deadline: await process_frame
	if not check(not runtime.busy(),"normal return still completes after refused load and menu requests"): finish(); return
	var trace: Dictionary = runtime.get_meta("return_trace",{})
	var attempts: Array = trace.get("attempts",[])
	check(attempts.any(func(item): return item.has("departed") and not item.departed) and trace.get("result","") == "returned","occupancy during the fade retries another destination within the same illusion")
	check(world.player.global_position.distance_to(blocked_destination) > 6.0,"return avoids the pavement that became physically blocked")
	blocker.queue_free()
	await physics_frame
	assert_recovered("released-load-menu",stock)
	check(world.player.global_position.distance_to(LAYOUT.HAUNTED_ENTRY) > 30.0,"handoff still returns away from Umbra to Harbor")
	await photo("handoff-returned-sober")
	await persist_and_restore()
	finish()

func chaos_entry(label: String) -> bool:
	if not await approach(): return false
	world.session.wine.recover()
	world.session.wine.model.data.alcohol = 96.0
	world.session.wine.model.data.cooldown = 0.0
	check(world.session.wine.get_intensity() >= .95,"extreme boundary fixture before " + label)
	if not await enter_live(): return false
	var deadline := Time.get_ticks_msec() + 12000
	while not runtime.exploring() and Time.get_ticks_msec() < deadline:
		if not runtime.busy() and runtime.state.pending_entry == 0: break
		await process_frame
	var ok := check(runtime.exploring(),"real extreme doorway entry reaches playable illusion for " + label)
	if ok: lifecycle.append({"id":label,"start_usec":Time.get_ticks_usec(),"duration":runtime.state.duration,"token":runtime.token()})
	return ok

func await_recovery(label: String,stock: Dictionary) -> bool:
	var deadline := Time.get_ticks_msec() + 30000
	while (world.session.rescue_pending or world.session.arrest_pending or world.session.respawn_busy or world.gameplay.health <= 0) and Time.get_ticks_msec() < deadline: await physics_frame
	if not check(not world.session.rescue_pending and not world.session.arrest_pending and not world.session.respawn_busy and world.gameplay.health > 0,label + " finishes the real recovery flow"): return false
	await process_frame
	assert_recovered(label,stock)
	return true

func assert_recovered(label: String,stock: Dictionary) -> void:
	check(not runtime.busy() and not world.session.is_transition_blocked() and world.session.state.region_id == "harbor" and world.session.state.place_id.is_empty(),label + " ends at an unlocked Harbor exterior")
	check(world.session.wine.get_intensity() == 0.0 and world.session.wine.snapshot().servings == stock,label + " is sober and retains paid wine stock")
	check(world.session.position_clear(world.player.global_position) and world.player.is_physics_processing() and not world.player.input_locked,label + " has real supported collision and playable controls")
	check(root.get_camera_3d() == world.camera and world.player.camera == world.camera and world.player.visual.visible and world.hud.visible and world.gameplay.enabled,label + " restores ordinary camera, visible presentation and gameplay")
	check(not is_instance_valid(runtime.arena) and not is_instance_valid(runtime.view) and not is_instance_valid(runtime.veil),label + " leaves no owned arena, camera or curtain")
	check(not world.player.has_meta("upside_world_owner") and not world.hud.has_meta("upside_world_owner") and not world.gameplay.has_meta("upside_world_owner"),label + " removes stale ownership metadata")
	lifecycle[-1]["end_usec"] = Time.get_ticks_usec()
	lifecycle[-1]["returned_position"] = vector_data(world.player.global_position)

func finish(code := -1) -> void:
	if ending: return
	ending = true
	paused = false
	var current := fingerprint(original_source)
	var report := {"mode":mode,"checks":checks,"failures":failures,"scenarios":lifecycle,"source_stable":current == original_source,"source_before":original_source,"source_after":current,"engine":Engine.get_version_info().string,"gpu":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),"isolated_save":save_path,"returned_save":final_path,"notes":"Three real Main/.NET entries with96-alcohol boundary fixtures. Actual environment damage/death and rescue; real confirmed low-level crime, arrest_player signal, locked custody presentation and respawn; normal10–15s illusion with load/menu requests refused during paused released/leave_place handoff. Paid stock survives. No benchmark or claim of drink cooldown coverage; ordinary session test covers deliberate consumption. All writes use new isolated evidence files and --no-save."}
	if not folder.is_empty(): FileAccess.open(folder.path_join("report.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("UPSIDE_LIFECYCLE_RESULT ",folder," checks=",checks," failures=",failures)
	quit(code if code >= 0 else 0 if failures.is_empty() else 1)
