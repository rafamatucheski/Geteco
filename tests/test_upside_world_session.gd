extends SceneTree
## Rendered Main/.NET acceptance and finite diagnostics. Fixture relocation only
## establishes the park approach; admission, drinks and return use live APIs.
const FIXTURE := preload("res://tests/fixtures/NorthGatewayFixtures.gd")
const STATE := preload("res://runtime/GameState.gd")
const STORE := preload("res://runtime/SaveStore.gd")
const LAYOUT := preload("res://world/places/amusement_park/AmusementParkLayout.gd")
const RETURNS := preload("res://runtime/upside_world/UpsideReturnPoints.gd")
const WINE_ID := "ag_chardonnay"
var world
var runtime
var folder := ""
var save_path := ""
var mode := "test"
var checks := 0
var failures: Array[String] = []
var cycles: Array[Dictionary] = []
var temporal: Array[Dictionary] = []
var original_source: Dictionary = {}
var original_max_fps := 0
var original_vsync := 0
var cycle_index := -1
var live_record: Dictionary = {}
var previous_frame := 0
var next_capture := 0
var capture_origin := 0
var ending := false
var final_path := ""

func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> bool:
	checks += 1
	print("UPSIDE_SESSION ", "PASS " if ok else "FAIL ", label)
	if not ok: failures.append(label)
	return ok

func run() -> void:
	var args := OS.get_cmdline_user_args()
	if DisplayServer.get_name() == "headless" or "--no-save" not in args or not OS.get_environment("HARBOR_NO_CSHARP").is_empty():
		push_error("Rendered Godot .NET with --no-save required"); quit(2); return
	if "--benchmark" in args and "--capture" in args:
		push_error("Run measurement and image capture separately"); quit(2); return
	mode = "benchmark" if "--benchmark" in args else "capture" if "--capture" in args else "test"
	create_timer(480, true).timeout.connect(func(): check(false, "finite 480s deadline"); finish(3))
	root.size = Vector2i(1280,720)
	seed(7102026)
	folder = FIXTURE.output_dir("upside-world-" + mode)
	original_source = fingerprint()
	original_max_fps = Engine.max_fps
	original_vsync = DisplayServer.window_get_vsync_mode()
	if mode == "benchmark" and "--normal-limits" not in args:
		Engine.max_fps = 0
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	elif mode == "capture":
		Engine.max_fps = 30
	var snapshot := FIXTURE.full_snapshot(LAYOUT.HAUNTED_ENTRY + Vector3(0,0,1.1),true)
	snapshot.campaign.aftermath = {"call_complete":true}
	save_path = FIXTURE.write_fixture(folder,"checkpoint.json",snapshot)
	if not check(not save_path.is_empty(),"isolated valid checkpoint created"): finish(); return
	await boot()
	if not check(is_instance_valid(runtime) and world.session.ready_for_play,"Main exposes the integrated Upside runtime"): finish(); return
	check(world.production.store.path == save_path and not world.production.save_invalid,"Main loaded only the isolated checkpoint")
	world.dispatch.router.nearest_edge(world.player.global_position)
	check(world.dispatch.router._native != null,"compiled C# route backend active")
	check(world.session.state.economy.grant_reward("upside_session_funds",8000),"isolated wallet funded")
	world.session.state.grant_weapon("pistol")
	world.session.activities.refresh_achievements()
	if mode == "test" and not await negative_entries(): finish(); return
	var total := 4 if mode == "benchmark" else 3 if mode == "capture" else 1
	if mode == "capture":
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder.path_join("temporal")))
		RenderingServer.frame_post_draw.connect(capture_frame)
	for index in total:
		if not await positive_cycle(index): finish(); return
	if mode == "benchmark":
		var warm: Array[float] = []
		for row in cycles:
			if int(row.index) > 0: warm.append_array(row.intervals_ms)
		check(float(stats(warm).get("seconds",0)) >= 30.0,"three ordinary warm illusions provide at least30s of actual rendered intervals")
	if mode == "capture":
		var active_seconds := 0.0
		for row in cycles: active_seconds += float(row.playable_wall_seconds)
		check(active_seconds >= 30.0 and temporal.size() > 300,"three bounded real illusions provide over30s of timestamped temporal evidence")
		check(temporal.all(func(row): return bool(row.saved)),"all scheduled JPEG readbacks succeeded")
	await persist_and_restore()
	finish()

func boot() -> void:
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	world.set_meta("menu_save_path",save_path)
	root.add_child(world)
	current_scene = world
	var deadline := Time.get_ticks_msec() + 70000
	while Time.get_ticks_msec() < deadline:
		await physics_frame
		if world.session != null and world.session.ready_for_play and world.production.startup_streaming_settled: break
	if world.session == null or not world.session.ready_for_play: return
	runtime = world.session.get("upside_world")
	if world.session.modal: world.session.close_menu()
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	world.player.speed = 3.5
	world.session.weather.weather_state = 0
	world.session.weather.weather_timer = 3600
	await create_timer(.6).timeout

func approach() -> bool:
	if not world.session.state.place_id.is_empty() or runtime.busy(): return false
	# Setup relocates between distant areas. Hold the real residency gate so
	# streaming cannot refocus the old player point while the new floor loads.
	var gate: int = world.session._begin_transition("upside_fixture_approach")
	if not check(gate > 0,"isolated approach fixture owns its streaming transition"): return false
	var physics_enabled: bool = world.player.is_physics_processing()
	world.player.set_physics_process(false)
	var point: Vector3 = LAYOUT.HAUNTED_ENTRY + Vector3(0,0,1.1)
	world.production.region.set_focus(point)
	world.production.region.prepare_collision_at(point)
	await physics_frame
	await physics_frame
	if not check(world.session.position_clear(point),"park fixture approach has floor and capsule clearance"):
		world.player.set_physics_process(physics_enabled)
		world.session._finish_transition(gate)
		return false
	world.player.teleport(point)
	world.player.set_physics_process(physics_enabled)
	world.session._finish_transition(gate)
	world.camera.initialized = false
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	world.session.amusement_park._update_residency()
	await create_timer(.6).timeout
	return check(await walk(LAYOUT.HAUNTED_ENTRY),"walk the final approach to the authored Umbra doorway")

func walk(point: Vector3) -> bool:
	var deadline := Time.get_ticks_msec() + 10000
	while flat_distance(world.player.global_position,point) > .2 and Time.get_ticks_msec() < deadline:
		var offset: Vector3 = point - world.player.global_position
		offset.y = 0
		world.player.automatic_direction = offset.normalized()
		await physics_frame
	world.player.automatic_direction = Vector3.ZERO
	return flat_distance(world.player.global_position,point) < .35

func enter_live() -> bool:
	if not check(world.session.nearest().get("id","") == "enter","Umbra entry is the live mapped interaction"): return false
	var accepted: bool = await world.session.interact()
	var deadline := Time.get_ticks_msec() + 15000
	# The interaction dispatches entry asynchronously; stop at its admission,
	# before the newly armed illusion takes ownership of the transition gate.
	while world.session.transition_kind == "enter_place" and Time.get_ticks_msec() < deadline: await physics_frame
	return check(accepted and world.session.state.place_id == LAYOUT.HAUNTED_ID,"live doorway interaction enters Umbra")

func leave_normal() -> bool:
	world.player.controlled_automatically = true
	if not await walk(world.session.room.exit_position): return false
	return await world.session.interact() and world.session.state.place_id.is_empty()

func negative_entries() -> bool:
	for amount in [0.0,89.9]:
		if not await approach(): return false
		world.session.wine.model.data.alcohol = amount
		if not await enter_live(): return false
		await create_timer(.55).timeout
		check(not runtime.busy() and runtime.state.pending_entry == 0,"entry below90 does not trigger: " + str(amount))
		check(world.session.amusement_park.house_view,"ordinary Umbra retains its own first-person camera")
		if amount > 0.0:
			check(world.session.wine.model.purchase(WINE_ID,world.session.state.economy).ok,"inside-drink fixture has a paid bottle")
			# Boundary fixture starts at72; the last24 points come from a real drink.
			world.session.wine.model.data.alcohol = 72.0
			world.session.wine.model.data.cooldown = 0.0
			check(world.session.wine.drink(WINE_ID) and is_equal_approx(float(world.session.wine.model.data.alcohol),96.0),"real drink reaches96 while already inside Umbra")
			await create_timer(.6).timeout
			check(not runtime.busy() and runtime.state.pending_entry == 0,"becoming extremely drunk inside does not synthesize a fresh entry")
		world.session.wine.recover()
		if not check(await leave_normal(),"ordinary house visit leaves through its live doorway"): return false
	return true

func prepare_drinks() -> bool:
	world.session.wine.recover()
	for bottle in 2:
		if not check(world.session.wine.model.purchase(WINE_ID,world.session.state.economy).ok,"paid six-serving fixture for cycle " + str(cycle_index)): return false
	world.gameplay.health = 37.0
	for glass in 4:
		if not check(world.session.wine.drink(WINE_ID),"deliberate runtime Chardonnay drink " + str(glass + 1)): return false
		if glass < 3: await create_timer(2.6).timeout
	check(world.session.state.equip_weapon("pistol"),"player deliberately re-equips the owned pistol after sipping")
	return check(world.session.wine.get_intensity() >= .9,"four real glasses meet extreme threshold before entry")

func positive_cycle(index: int) -> bool:
	cycle_index = index
	if mode == "capture":
		world.session.weather.time_of_day = .35 if index == 0 else .90
		world.session.weather._update()
	if not await approach() or not await prepare_drinks(): return false
	var saved := preserved_state()
	if mode != "benchmark": await photo("cycle-%d-entry" % index)
	live_record = {"index":index,"kind":"cold" if index == 0 else "warm","duration":0.0,"max_elapsed":0.0,"playable_wall_seconds":0.0,"intervals_ms":[],"cpu_ms":[],"physics_ms":[],"context_start":context(),"context_end":{}}
	previous_frame = 0
	next_capture = 0
	if not await enter_live(): return false
	var deadline := Time.get_ticks_msec() + 12000
	while not runtime.exploring() and Time.get_ticks_msec() < deadline:
		if not runtime.busy() and runtime.state.pending_entry == 0: break
		await process_frame
	if not check(runtime.exploring(),"extreme entry starts one playable illusion"): return false
	live_record.duration = runtime.state.duration
	live_record["context_active"] = context()
	check(runtime.state.duration >= 10.0 and runtime.state.duration <= 15.0,"productive duration remains10–15 playable seconds")
	check(not runtime.arm_entry(LAYOUT.HAUNTED_ID),"duplicate entry callback cannot create another active illusion")
	check(root.get_camera_3d() == runtime.view and world.player.camera == runtime.view,"isolated first-person camera owns both view and movement basis")
	check(world.player.is_physics_processing() and not world.player.input_locked,"real capsule locomotion remains enabled")
	check(not world.gameplay.attack_allowed() and not world.gameplay.enabled,"combat is disabled throughout the visual illusion")
	var ammunition: Dictionary = world.session.state.get_ammo("pistol")
	check(not world.gameplay.fire_at(world.player.global_position + Vector3.FORWARD*10) and world.session.state.get_ammo("pistol") == ammunition,"a real firing request is refused without consuming ammunition")
	check(world.session.nearest().is_empty() and not await world.session.interact(),"normal interactions cannot escape the held transition")
	check(not world.session.save_block_reason().is_empty() and not world.session.save_game(),"remote illusion coordinates cannot be saved")
	if mode != "benchmark":
		await controls_probe()
		if index == 0:
			var before: Dictionary = runtime.state.snapshot()
			var pose: Transform3D = runtime.view.global_transform
			paused = true
			await create_timer(.3,true).timeout
			check(runtime.state.snapshot() == before and runtime.view.global_transform == pose,"pause freezes duration and camera for0.3 real seconds")
			paused = false
		await photo("cycle-%d-upside" % index)
	deadline = Time.get_ticks_msec() + 30000
	while runtime.busy() and Time.get_ticks_msec() < deadline: await process_frame
	previous_frame = 0
	live_record.context_end = context()
	live_record["return_trace"] = runtime.get_meta("return_trace",{})
	live_record["end_reason"] = runtime.get_meta("end_reason","")
	cycles.append(live_record.duplicate(true))
	live_record.clear()
	if not check(not runtime.busy() and not world.session.is_transition_blocked(),"bounded illusion and normal return release every transition"): return false
	check(float(cycles[-1].max_elapsed) + .05 >= float(cycles[-1].duration),"return waits for the complete playable duration, excluding fades and pause")
	check(world.session.state.region_id == "harbor" and world.session.state.place_id.is_empty(),"return finishes in Harbor exterior")
	check(world.player.global_position.distance_to(LAYOUT.HAUNTED_ENTRY) > 30.0,"random safe return is away from Umbra")
	check(world.session.position_clear(world.player.global_position),"returned capsule has collision clearance and floor support")
	var nearest := INF
	for point in RETURNS.candidates(): nearest = minf(nearest,world.player.global_position.distance_to(point))
	check(nearest < .55,"return uses a curated Harbor sidewalk candidate")
	check(world.session.wine.get_intensity() == 0.0,"automatic return is completely sober")
	check(preserved_state() == saved,"illusion preserves health, stock, wallet items, ammunition, equipped weapon and campaign flags")
	check(world.player.visual.visible and world.hud.visible and world.gameplay.enabled,"return restores visible player, HUD and gameplay")
	check(not world.player.input_locked and world.player.is_physics_processing(),"return restores real player controls and physics")
	check(root.get_camera_3d() == world.camera and world.player.camera == world.camera,"return restores the ordinary Harbor camera")
	check(not is_instance_valid(runtime.view) and not is_instance_valid(runtime.arena) and not is_instance_valid(runtime.veil),"return retains no owned arena, camera or curtain")
	cycles[-1]["return_position"] = vector_data(world.player.global_position)
	if mode != "benchmark": await photo("cycle-%d-return" % index)
	return true

func controls_probe() -> void:
	var prior_yaw: float = runtime.yaw
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(32,-9)
	world.session._input(motion)
	await physics_frame
	check(absf(runtime.yaw - prior_yaw) > .01,"mouse look reaches the isolated first-person camera")
	var input := root.get_node("GameInput")
	var prior_touch: Vector2 = input.touch_move
	var prior_aim: Vector2 = input.touch_aim
	var point: Vector3 = world.player.global_position
	input.touch_move = Vector2.RIGHT
	input.touch_aim = Vector2(.15,0)
	await create_timer(.25).timeout
	input.touch_move = -Vector2.RIGHT
	await create_timer(.25).timeout
	input.touch_move = prior_touch
	input.touch_aim = prior_aim
	check(world.player.global_position.distance_to(point) > .005 or world.player.velocity.length() > .1,"normal movement and touch look remain active during the illusion")
	check(world.session.position_clear(world.player.global_position),"moving visitor retains supported physical collision")

func _process(delta: float) -> bool:
	if live_record.is_empty() or not is_instance_valid(runtime): return false
	if runtime.state.active: live_record.max_elapsed = maxf(float(live_record.max_elapsed),runtime.state.elapsed)
	if not runtime.exploring() or paused:
		previous_frame = 0
		return false
	if mode == "capture" and cycle_index > 0:
		# Cycle0 stays still after the control probe; cycle1 gradually inspects
		# the meteor sky, and cycle2 sweeps the side ruins. Only view input moves.
		var elapsed: float = runtime.state.elapsed
		var desired_yaw := sin(elapsed*.24)*(.65 if cycle_index == 1 else 1.05)
		var desired_pitch := .50 + sin(elapsed*.2)*.12 if cycle_index == 1 else .12 + cos(elapsed*.25)*.12
		runtime.look_delta(Vector2(runtime.yaw - desired_yaw,runtime.pitch - desired_pitch)*minf(delta*1.6,1.0))
	var now := Time.get_ticks_usec()
	if previous_frame > 0:
		var ms := float(now - previous_frame)/1000.0
		live_record.playable_wall_seconds += ms/1000.0
		if mode == "benchmark":
			live_record.intervals_ms.append(ms)
			live_record.cpu_ms.append(Performance.get_monitor(Performance.TIME_PROCESS)*1000.0)
			live_record.physics_ms.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000.0)
	previous_frame = now
	return false

func capture_frame() -> void:
	if ending or mode != "capture" or not is_instance_valid(runtime) or not runtime.exploring() or paused: return
	var now := Time.get_ticks_usec()
	# Keep the target cadence tied to its epoch; scheduling from each actual
	# render timestamp would halve capture frequency under harmless frame jitter.
	if now + 1500 < next_capture: return
	if capture_origin == 0: capture_origin = now
	next_capture = maxi(now,next_capture) + 33333 if next_capture == 0 else maxi(next_capture + 33333,now)
	var filename := "%05d.jpg" % temporal.size()
	var result := root.get_texture().get_image().save_jpg(folder.path_join("temporal").path_join(filename),.86)
	temporal.append({"cycle":cycle_index,"frame":Engine.get_frames_drawn(),"time_us":now - capture_origin,"active_elapsed":runtime.state.elapsed,"yaw":runtime.yaw,"pitch":runtime.pitch,"file":filename,"saved":result == OK})

func preserved_state() -> Dictionary:
	var state = world.session.state
	var economy: Dictionary = state.economy.snapshot()
	return {"health":world.gameplay.health,"wine_servings":world.session.wine.snapshot().servings,"weapons":economy.weapons,"inventory":economy.inventory,"equipped":state.equipped_weapon,"flags":state.campaign.snapshot().flags,"completed":state.campaign.snapshot().completed,"collision_layer":world.player.collision_layer,"collision_mask":world.player.collision_mask}

func persist_and_restore() -> void:
	check(world.session.save_game(),"returned exterior can be captured by the live save path")
	var full: Dictionary = world.session.state.snapshot()
	full.combat = world.gameplay.snapshot()
	final_path = FIXTURE.write_fixture(folder,"returned-exterior.json",full)
	if not check(not final_path.is_empty(),"valid returned exterior saved to a new isolated disk file"): return
	var loaded := STORE.read_valid(final_path)
	var restored = STATE.new()
	check(restored.restore_snapshot(loaded) and restored.region_id == "harbor" and restored.place_id.is_empty(),"SaveStore and GameState load the final Harbor exterior")
	# JSON numbers become floats. Use the same canonical wine restore as Main,
	# instead of comparing raw JSON dictionary types with integer serving counts.
	var restored_wine = preload("res://gameplay/wine/WineState.gd").new()
	check(restored_wine.restore_snapshot(restored.world_state.wine_cellar) and restored_wine.intensity() == 0.0 and restored_wine.snapshot().servings == world.session.wine.snapshot().servings,"saved return remains sober and preserves stock")
	var at: Array = restored.world_state.get("pedestrian",{}).get("position",[])
	check(at.size() == 3 and absf(float(at[2])) < 1000,"disk checkpoint cannot contain the remote arena coordinate")
	# One cold Main restore in the functional mode checks actual ownership reset.
	if mode != "test": return
	var saved := preserved_state()
	world.queue_free()
	await process_frame
	await process_frame
	save_path = final_path
	await boot()
	check(is_instance_valid(runtime) and not runtime.busy() and runtime.state.pending_entry == 0,"cold Main restore does not resurrect the transient hallucination")
	check(world.session.state.place_id.is_empty() and world.session.position_clear(world.player.global_position),"cold restore is on a supported Harbor sidewalk")
	check(preserved_state() == saved and world.session.wine.get_intensity() == 0.0,"cold Main preserves returned health, equipment, stock and story flags")
	await photo("cold-restored-exterior")

func context() -> Dictionary:
	var result := {"ticks_usec":Time.get_ticks_usec(),"people":world.people.size(),"vehicles":world.production.vehicles.size(),"requested_population":world.production.requested_population,"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),"render_objects":Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),"nodes":Performance.get_monitor(Performance.OBJECT_NODE_COUNT),"memory_bytes":Performance.get_monitor(Performance.MEMORY_STATIC),"max_fps":Engine.max_fps,"vsync":DisplayServer.window_get_vsync_mode(),"player":vector_data(world.player.global_position),"wine_intensity":world.session.wine.get_intensity()}
	if is_instance_valid(runtime) and is_instance_valid(runtime.arena): result["arena"] = runtime.arena.get_stats()
	result["time_of_day"] = world.session.weather.time_of_day
	return result

func photo(label: String) -> void:
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(folder.path_join(label + ".png")) == OK,"saved screenshot " + label)

func fingerprint(reference: Dictionary = {}) -> Dictionary:
	if not reference.is_empty():
		var result := {}
		for path in reference: result[path] = FileAccess.get_sha256(path) if FileAccess.file_exists(path) else "MISSING"
		return result
	var result := FIXTURE.source_fingerprint()
	for directory in ["res://runtime/upside_world","res://world/places/upside_world"]:
		for file in DirAccess.get_files_at(directory):
			if file.ends_with(".gd") or file.ends_with(".gdshader"): result[directory.path_join(file)] = FileAccess.get_sha256(directory.path_join(file))
	for path in ["res://runtime/amusement_park/AmusementParkRuntime.gd","res://gameplay/Gameplay.gd","res://scripts/Actor.gd","res://scripts/CameraRig.gd","res://ui/AndroidControls.gd","res://tests/test_upside_world_session.gd"]:
		result[path] = FileAccess.get_sha256(path) if FileAccess.file_exists(path) else "MISSING"
	return result

func stats(values: Array) -> Dictionary:
	if values.is_empty(): return {}
	var ordered := values.duplicate()
	ordered.sort()
	var total := 0.0
	var over33 := 0
	var over66 := 0
	for value in values:
		total += float(value)
		if float(value) > 33.3: over33 += 1
		if float(value) > 66.7: over66 += 1
	return {"frames":values.size(),"seconds":total/1000.0,"fps":values.size()*1000.0/maxf(total,.001),"p50_ms":ordered[int((ordered.size() - 1)*.5)],"p95_ms":ordered[int((ordered.size() - 1)*.95)],"p99_ms":ordered[int((ordered.size() - 1)*.99)],"max_ms":ordered[-1],"over_33_3_ms":over33,"over_66_7_ms":over66}

func flat_distance(a: Vector3,b: Vector3) -> float: return Vector2(a.x - b.x,a.z - b.z).length()
func vector_data(point: Vector3) -> Array: return [point.x,point.y,point.z]

func finish(code := -1) -> void:
	if ending: return
	ending = true
	paused = false
	var current := fingerprint(original_source)
	var warm: Array[float] = []
	for row in cycles:
		row["summary"] = stats(row.intervals_ms)
		if int(row.index) > 0: warm.append_array(row.intervals_ms)
	var report := {"mode":mode,"checks":checks,"failures":failures,"source_stable":original_source == current,"source_before":original_source,"source_after":current,"engine":Engine.get_version_info().string,"gpu":RenderingServer.get_video_adapter_name(),"cpu":OS.get_processor_name(),"renderer":RenderingServer.get_current_rendering_method(),"resolution":str(root.size),"cycles":cycles,"warm_summary":stats(warm),"temporal":temporal,"isolated_save":save_path,"returned_save":final_path,"original_limits":{"max_fps":original_max_fps,"vsync":original_vsync},"notes":"Main .NET, live population, isolated checkpoint and paid wine fixture. Four actual runtime drinks with ordinary cooldown; all entries use the live doorway. Productive duration is never extended. Benchmark: cold plus three warm illusions, only real frame intervals while exploring, no readbacks. Capture: three real illusions, scheduled JPEGs at most30Hz with timestamps; readback cost is not FPS evidence. Normal test additionally covers two negative entries, inside drinking, pause, movement/look and one cold exterior restore. Foreign-owner/death/arrest cleanup is covered separately. Fixture relocations establish park approaches and do not claim route coverage."}
	if not folder.is_empty(): FileAccess.open(folder.path_join("report.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	Engine.max_fps = original_max_fps
	DisplayServer.window_set_vsync_mode(original_vsync)
	print("UPSIDE_SESSION_RESULT ",folder," checks=",checks," failures=",failures)
	quit(code if code >= 0 else 0 if failures.is_empty() else 1)
