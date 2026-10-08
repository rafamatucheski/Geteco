extends SceneTree
## Production scene: physical ascent/descent, real session action, optical input,
## pause/recovery and residency return. Readbacks are NOT FPS measurements.
const FIXTURE := preload("res://tests/fixtures/NorthGatewayFixtures.gd")
const SITE := preload("res://world/places/coastal_lookout/CoastalLookout.gd")
var world
var output := ""
var checks := 0
var failures: Array[String] = []
var walk_trace: Array[Dictionary] = []
var frames: Array[Dictionary] = []
var snapshots: Array[String] = []
var fingerprint: Dictionary = {}
var completed := false
var overview: Camera3D
var missed_surf_frames := 0
var lifecycle_only := false

func _initialize() -> void:
	create_timer(360).timeout.connect(func():
		if completed: return
		check(false,"Capture deadline exceeded")
		finish(3))
	run.call_deferred()

func check(value: bool, message: String) -> bool:
	checks += 1
	print("COASTAL_CAPTURE ", "PASS " if value else "FAIL ", message)
	if not value: failures.append(message)
	return value

func run() -> void:
	var args := OS.get_cmdline_user_args()
	lifecycle_only = "--lifecycle-only" in args
	if DisplayServer.get_name() == "headless" or "--no-save" not in args or "--benchmark" not in args or not OS.get_environment("HARBOR_NO_CSHARP").is_empty():
		push_error("Rendered Godot .NET with --benchmark --no-save is required")
		quit(2)
		return
	seed(100726)
	root.size = Vector2i(1280,720)
	output = FIXTURE.output_dir("coastal-lookout-capture")
	for path in ["res://world/places/coastal_lookout/CoastalLookout.gd", "res://world/places/coastal_lookout/coastal_surf.gdshader", "res://runtime/coastal_lookout/CoastalLookoutRuntime.gd", "res://runtime/coastal_lookout/CoastalBinoculars.gd", "res://runtime/coastal_lookout/BinocularOverlay.gd", "res://runtime/coastal_lookout/binocular_mask.gdshader", "res://runtime/FullSession.gd", "res://gameplay/Gameplay.gd"]:
		fingerprint[path] = FileAccess.get_sha256(path)
	var spawn := SITE.entrance_position() + Vector3(.68,.10,2.0)
	if lifecycle_only: spawn = SITE.binocular_interaction_position()+Vector3.UP*.08
	var snapshot := FIXTURE.full_snapshot(spawn,false)
	if lifecycle_only:
		# An unfinished, inactive campaign allows saving while keeping the gate shut.
		var state = preload("res://runtime/GameState.gd").new()
		if not check(state.restore_snapshot(snapshot),"Lifecycle fixture restores before mission cancellation"): finish(); return
		state.campaign.cancel("coastal_lifecycle_fixture")
		snapshot = state.snapshot()
	snapshot.world.time = .45
	snapshot.world.weather = 0
	var save_path := FIXTURE.write_fixture(output,"fixture.json",snapshot)
	if not check(not save_path.is_empty(),"Valid isolated fixture created"): finish(); return
	world = load("res://Main.tscn").instantiate()
	world.set_meta("menu_save_path",save_path)
	world.set_meta("skip_arrival",true)
	root.add_child(world)
	current_scene = world
	while world.session == null or not world.session.ready_for_play or not world.production.startup_streaming_settled: await physics_frame
	if not check(not world.production.save_invalid and world.production.store.path == save_path,"Production session uses the isolated fixture"): finish(); return
	world.dispatch.router.nearest_edge(world.player.global_position)
	if not check(world.dispatch.router._native != null,"Native C# routes active"): finish(); return
	if world.session.modal: world.session.close_menu()
	var return_spawn: Vector3 = world.maciota_place.exterior_return+Vector3(0,.08,2)
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	world.player.speed = 3.5
	world.session.weather.time_of_day = .45
	world.session.weather.weather_state = 0
	world.session.weather.weather_timer = 9999
	world.session.weather._update()
	if lifecycle_only:
		if "--lighthouse-visuals" in args: await lighthouse_visuals()
		await lifecycle(spawn,return_spawn,save_path)
		finish()
		return
	# --skip-arrival returns to Maciota: move only the initial observer to the
	# entrance after startup. Every metre of ascent/descent below uses Actor physics.
	await relocate(spawn)
	await create_timer(2.0).timeout
	var runtime = world.session.coastal_lookout
	if not check(runtime != null and is_instance_valid(runtime.site),"Approach streams the actual coastal site"): finish(); return
	await photo("01-entrance")
	var route := PackedVector3Array([SITE.entrance_position()+Vector3(.68,0,0), SITE.entrance_position()+Vector3(.68,.5,-3.4)])
	var authored := SITE.route_points()
	for index in range(1,authored.size()): route.append(authored[index])
	route.append(SITE.summit_position())
	for index in route.size():
		if not await walk(route[index],"ascent-%02d"%index):
			check(false,"Continuous physical ascent at route point %d"%index)
			await photo("blocked-ascent-%02d"%index)
			finish(); return
		if index in [2,int(route.size()/2),route.size()-1]: await photo("02-ascent-%02d"%index)
	check(true,"Entire pedestrian ascent completed with production collision")
	check(world.player.is_on_floor() and absf(world.player.global_position.y-SITE.summit_position().y)<.3,"Summit supports the player at its authored height")
	await photo("03-summit")
	# Observe the same resident scene from a photographic camera; normal gameplay
	# remains running; a bounded30s sequence covers static, moving and returning views.
	overview = Camera3D.new()
	overview.fov = 58
	overview.far = 3500
	world.add_child(overview)
	overview.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	overview.global_position = Vector3(340,40,-161)
	overview.look_at(Vector3(303,15,-198))
	overview.environment = world.production.environment.environment.duplicate(true)
	overview.environment.fog_depth_begin = 150
	overview.environment.fog_depth_end = 2400
	overview.make_current()
	await create_timer(2).timeout
	await photo("04-promontory-overview")
	overview.global_position = Vector3(340,40,-161)
	overview.look_at(Vector3(303,15,-198))
	await create_timer(.5).timeout
	await temporal_surf(30.0)
	world.session.weather.time_of_day = .02
	world.session.weather._update()
	overview.environment = world.production.environment.environment.duplicate(true)
	overview.environment.fog_depth_begin = 150
	overview.environment.fog_depth_end = 1800
	await create_timer(2).timeout
	await photo("04b-lighthouse-night")
	await temporal_surf(30.0,"night-frames")
	world.session.weather.time_of_day = .45
	world.session.weather._update()
	world.camera.make_current()
	overview.queue_free()
	overview = null
	if not check(await walk(SITE.binocular_interaction_position(),"optic-approach"),"Player walks from terrace to the binocular"): finish(); return
	await create_timer(.5).timeout
	check(world.session.nearest().get("id","")=="coastal_binoculars","Normal session selects the binocular action")
	var before: Vector3 = world.player.global_position
	var street_environment: Environment = world.production.environment.environment
	var street_fog_end: float = street_environment.fog_depth_end
	if not check(await world.session.interact(),"Normal session interaction enters observation"): finish(); return
	if not check(runtime.active,"Optical mode active after interaction"): finish(); return
	check(not world.gameplay.attack_allowed(),"Real gameplay combat is blocked while observing")
	check(not world.session.save_block_reason().is_empty(),"Save refuses transient optical state")
	await create_timer(2).timeout
	await photo("05-binocular-desert-wide")
	# Both mechanical pan limits must show sea/terrain through the whole mask.
	runtime.binoculars.look_delta(Vector2(-10,0))
	await create_timer(.4).timeout
	await photo("05b-pan-east-limit")
	runtime.binoculars.look_delta(Vector2(20,0))
	await create_timer(.4).timeout
	await photo("05c-pan-west-limit")
	runtime.binoculars.look_delta(Vector2(-runtime.binoculars.MAX_YAW,0))
	check(runtime.binoculars.optical_camera.environment!=street_environment and is_equal_approx(street_environment.fog_depth_end,street_fog_end),"Optical panorama preserves the world atmosphere resource")
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	for step in 6:
		Input.parse_input_event(wheel)
		await process_frame
	await create_timer(.7).timeout
	await photo("06-binocular-desert-zoom")
	check(runtime.binoculars.optical_camera.fov < 30.0,"Real mouse wheel events zoom the optic")
	check(world.player.global_position.distance_to(before)<.15,"Player stays on the physical terrace during observation")
	var pause := InputEventAction.new()
	pause.action = &"pause_game"
	pause.pressed = true
	Input.parse_input_event(pause)
	await process_frame
	await process_frame
	pause.pressed = false
	Input.parse_input_event(pause)
	check(paused and not runtime.active,"Pause input exits optical mode and opens the real pause menu")
	check(world.camera.current and not world.player.has_meta("coastal_binoculars_active"),"Pause restores gameplay camera and releases optical ownership")
	await photo("07-pause-restored")
	if paused: world.pause_panel.resume_game()
	await physics_frame
	check(not world.player.input_locked and world.hud.visible and world.player.visual.visible,"Resume restores player, HUD and movement")
	if not check(await walk(SITE.summit_position(),"return-to-centre"),"Player resumes physical movement after observation"): finish(); return
	for index in range(route.size()-2,-1,-1):
		if not await walk(route[index],"descent-%02d"%index):
			check(false,"Continuous physical descent at route point %d"%index)
			await photo("blocked-descent-%02d"%index)
			finish(); return
	check(await walk(spawn,"return-to-street"),"Entire pedestrian descent returns to the city sidewalk")
	await photo("08-return-to-street")
	# Residency lifecycle diagnostic: the path above is physically walked; this
	# bounded repositioning tests unload/re-entry, not the route back to Maciota.
	await relocate(return_spawn)
	await create_timer(2).timeout
	check(not is_instance_valid(runtime.site) and not runtime.active,"Leaving locality unloads optic and scene")
	await relocate(spawn)
	await create_timer(2).timeout
	check(is_instance_valid(runtime.site) and not runtime.active and not world.player.input_locked,"Re-entry recreates scenery without stuck controls")
	await photo("09-streaming-return")
	finish()

func lifecycle(saved_point: Vector3, distant_point: Vector3, save_path: String) -> void:
	# NO relocation before these checks: this is a real cold restore on the top.
	var runtime = world.session.coastal_lookout
	await create_timer(.5).timeout
	if not check(runtime!=null and is_instance_valid(runtime.site),"Cold restore mounts the terrace before gameplay"): return
	check(int(runtime.get_meta("template_generation_count",0))==1,"Scenery templates are generated once during initial loading")
	check(runtime.site.find_children("*","Light3D",true,false).size()==1 and runtime.site.find_children("BinocularHead","Node3D",true,false).size()==1,"Restored template has one lantern and one binocular head")
	if not check(world.player.global_position.distance_to(saved_point)<.25 and world.player.is_on_floor(),"Cold checkpoint restores directly onto the supported top without test teleport"): return
	check(not world.player.input_locked and not runtime.active and world.camera.current,"Cold restore has normal controls/camera and no optical state")
	check(not preload("res://world/north_gateway/NorthGatewayPolicy.gd").campaign_completed(world.session.state.campaign.snapshot()),"Unfinished final mission remains incomplete after summit restore")
	check(not world.production.travel("desert"),"Observation checkpoint never unlocks desert travel")
	var gateway = get_first_node_in_group("north_gateway")
	if is_instance_valid(gateway): check(not gateway.completed,"Resident bridge controller keeps construction closed")
	await photo("lifecycle-01-cold-restored-top")
	check(world.session.save_block_reason().is_empty(),"Supported summit is saveable outside observation")
	# Exercise the actual save path only after isolation has been verified above.
	var no_save: bool = world.production.no_save
	world.production.no_save = false
	var saved: bool = world.session.save_game()
	world.production.no_save = no_save
	check(saved,"Normal session writes the summit checkpoint to its isolated fixture")
	var persisted: Dictionary = preload("res://runtime/SaveStore.gd").read_valid(save_path)
	var pedestrian: Dictionary = persisted.get("world",{}).get("pedestrian",{})
	var coordinates: Array = pedestrian.get("position",[])
	check(coordinates.size()==3 and absf(float(coordinates[1])-SITE.summit_position().y)<.3,"Serialized checkpoint retains supported summit height")
	if not check(await world.session.interact() and runtime.active,"Restored player can use the normal optical interaction"): return
	if "--lighthouse-visuals" in OS.get_cmdline_user_args():
		await photo("final-binocular-wide")
		runtime.binoculars.adjust_zoom(-100)
		await photo("final-binocular-city")
		runtime.binoculars.adjust_zoom(100)
	check(not world.gameplay.attack_allowed() and world.session.save_block_reason().contains("binóculo"),"Observation blocks combat and saving specifically")
	var key := InputEventKey.new()
	key.physical_keycode = KEY_D
	key.pressed = true
	Input.parse_input_event(key)
	await create_timer(.25).timeout
	key.pressed = false
	Input.parse_input_event(key)
	check(runtime.binoculars.yaw < -.03,"Keyboard movement bindings pan optical view without moving Dante")
	var axis := InputEventJoypadMotion.new()
	axis.device = 7
	axis.axis = JOY_AXIS_RIGHT_Y
	axis.axis_value = -.8
	Input.parse_input_event(axis.duplicate())
	await create_timer(.25).timeout
	axis.axis_value = 0
	Input.parse_input_event(axis.duplicate())
	check(runtime.binoculars.pitch > .03,"Gamepad right-stick input raises the optical view")
	axis.axis = JOY_AXIS_TRIGGER_LEFT
	axis.axis_value = 1.0
	Input.parse_input_event(axis.duplicate())
	await create_timer(.3).timeout
	axis.axis_value = 0
	Input.parse_input_event(axis.duplicate())
	check(runtime.binoculars.optical_camera.fov < 44,"Gamepad trigger input zooms the optical view")
	await photo("lifecycle-02-optical-input")
	var cancel := InputEventAction.new()
	cancel.action = &"interact"
	cancel.pressed = true
	Input.parse_input_event(cancel)
	await process_frame
	cancel.pressed = false
	Input.parse_input_event(cancel)
	check(not runtime.active and not world.player.input_locked,"Normal interaction releases optical ownership")
	await relocate(distant_point)
	await create_timer(2).timeout
	check(not is_instance_valid(runtime.site) and not is_instance_valid(runtime.binoculars),"Actual distant departure unloads optical runtime and scenery")
	await relocate(SITE.entrance_position()+Vector3(.68,.10,2.0))
	await create_timer(2).timeout
	check(is_instance_valid(runtime.site) and not runtime.active and not world.player.input_locked,"Streaming return recreates scenery and normal controls")
	check(int(runtime.get_meta("template_generation_count",0))==1 and int(runtime.get_meta("residency_install_count",0))>=2,"Streaming return reuses prepared resources without generating geometry again")
	print("LIGHTHOUSE_CACHE prepare_ms=",runtime.get_meta("template_prepare_ms")," install_ms=",runtime.get_meta("last_residency_install_ms"))
	await photo("lifecycle-03-streaming-return")
	# The full ascent was already tested separately; this relocation isolates
	# optical ownership after recreation without pretending to walk it twice.
	await relocate(saved_point)
	await create_timer(.5).timeout
	if not check(await world.session.interact() and runtime.active,"Recreated optical runtime admits a second interaction"): return
	runtime.leave()
	await process_frame
	check(not runtime.active and world.camera.current and not world.player.input_locked and not world.player.has_meta("coastal_binoculars_active"),"Repeated interaction leaves no camera/input/combat ownership behind")
	check(not preload("res://world/north_gateway/NorthGatewayPolicy.gd").campaign_completed(world.session.state.campaign.snapshot()),"Observation and save keep final-mission bridge condition intact")

func lighthouse_visuals() -> void:
	overview = Camera3D.new()
	overview.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	overview.fov = 58
	overview.far = 3500
	world.add_child(overview)
	overview.global_position = Vector3(340,40,-161)
	overview.look_at(Vector3(303,15,-198))
	overview.make_current()
	for setting in [{"hour":.45,"id":"final-day"},{"hour":.02,"id":"final-night"}]:
		world.session.weather.time_of_day = setting.hour
		world.session.weather._update()
		overview.environment = world.production.environment.environment.duplicate(true)
		overview.environment.fog_depth_begin = 150
		overview.environment.fog_depth_end = 2400
		await create_timer(2).timeout
		await photo(setting.id)
		await temporal_surf(30,setting.id+"-frames")
	var lamp := world.session.coastal_lookout.site.get_node("LighthouseLanternLight") as OmniLight3D
	check(lamp.position.is_equal_approx(Vector3(303,26,-198)) and is_equal_approx(lamp.omni_range,6.5),"Final bounded lighthouse light is mounted")
	world.session.weather.time_of_day = .45
	world.session.weather._update()
	world.camera.make_current()
	overview.queue_free()
	overview = null
	await create_timer(.5).timeout

func relocate(point: Vector3) -> void:
	world.player.automatic_direction = Vector3.ZERO
	world.production.region.set_focus(point)
	world.production.region.prepare_collision_at(point)
	world.player.teleport(point)
	world.camera.initialized = false
	await physics_frame

func walk(point: Vector3, label: String) -> bool:
	var deadline := Time.get_ticks_msec()+12000
	var sample_at := 0
	while Time.get_ticks_msec()<deadline:
		var displacement: Vector3 = point-world.player.global_position
		var horizontal := Vector2(displacement.x,displacement.z)
		if horizontal.length()<.19:
			world.player.automatic_direction = Vector3.ZERO
			for frame in 3: await physics_frame
			return absf(world.player.global_position.y-point.y)<.65
		displacement.y = 0
		world.player.automatic_direction = displacement.normalized()
		if Time.get_ticks_msec()>=sample_at:
			sample_at = Time.get_ticks_msec()+100
			walk_trace.append({"label":label,"ms":Time.get_ticks_msec(),"position":str(world.player.global_position),"on_floor":world.player.is_on_floor(),"target":str(point)})
		await physics_frame
	world.player.automatic_direction = Vector3.ZERO
	print("COASTAL_WALK_BLOCKED ",label," expected=",point," actual=",world.player.global_position)
	for index in world.player.get_slide_collision_count():
		var collision = world.player.get_slide_collision(index)
		var collider = collision.get_collider()
		print("COASTAL_BLOCKER ",collider.get_path() if is_instance_valid(collider) else "freed"," point=",collision.get_position()," normal=",collision.get_normal())
	return false

func photo(label: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var path := output.path_join(label+".png")
	if check(root.get_texture().get_image().save_png(path)==OK,"Screenshot "+label): snapshots.append(path)

func temporal_surf(seconds: float, scenario := "surf-frames") -> void:
	var folder := output.path_join(scenario)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var began := Time.get_ticks_usec()
	var previous := -1
	var ok := true
	var previous_cap := Engine.max_fps
	Engine.max_fps = 30
	var initial_position := overview.global_position
	var focus := Vector3(303,15,-198)
	while float(Time.get_ticks_usec()-began)/1000000.0<seconds:
		var elapsed := float(Time.get_ticks_usec()-began)/1000000.0
		var movement := 0.0 if elapsed<10.0 else minf(elapsed-10.0,30.0-elapsed)*.35
		overview.global_position = initial_position+Vector3(movement,movement*.18,-movement*.5)
		overview.look_at(focus)
		await RenderingServer.frame_post_draw
		var drawn := Engine.get_frames_drawn()
		if previous>=0: missed_surf_frames += maxi(0,drawn-previous-1)
		previous = drawn
		var path := folder.path_join("%04d.jpg"%frames.size())
		ok = root.get_texture().get_image().save_jpg(path,.80)==OK and ok
		frames.append({"path":path,"scenario":scenario,"drawn_frame":drawn,"usec":Time.get_ticks_usec(),"elapsed":float(Time.get_ticks_usec()-began)/1000000.0,"camera":str(overview.global_transform)})
	Engine.max_fps = previous_cap
	check(ok and frames.size()>1,"Temporal surf frames recorded")
	print("COASTAL_SURF frames=",frames.size()," missed=",missed_surf_frames)

func finish(code := -1) -> void:
	if completed: return
	completed = true
	var stable := true
	for path in fingerprint:
		if FileAccess.get_sha256(path)!=fingerprint[path]: stable = false
	var report := {"checks":checks,"failures":failures,"screenshots":snapshots,"walk_trace":walk_trace,"surf_frames":frames,"missed_surf_frames":missed_surf_frames,"source_sha256":fingerprint,"source_stable":stable,"engine":Engine.get_version_info(),"gpu":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),"resolution":str(root.size),"vsync":DisplayServer.window_get_vsync_mode(),"max_fps":Engine.max_fps,"notes":"Rendered Main with native C# routing and isolated fixture. Observer initially relocated after skip-arrival, then all ascent/descent and optic approach through Actor physics. Residency departure/return explicitly relocated. Photographic overview camera for scenery and continuous30s surf at temporary30FPS cap:10s static,10s slow camera displacement,10s return. Readbacks and JPEG overhead are NOT performance evidence. Screenshots/sequence need visual inspection; coverage is dry daytime, not global/night/storm certification."}
	if lifecycle_only:
		report.notes = "Rendered Main cold-restores an isolated unfinished/inactive-campaign checkpoint directly on the supported lookout top; NO test teleport before restoration checks. Actual session save writes only that isolated fixture. Keyboard/gamepad events exercise optical input. Residency departure/return and second optical approach use explicit test relocations, not claimed walking. Full walking/temporal coverage belongs to the previous complete runner. No FPS claim."
	report["lifecycle_only"] = lifecycle_only
	if not output.is_empty(): FileAccess.open(output.path_join("report.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("COASTAL_LOOKOUT_CAPTURE ",output," checks=",checks," failures=",failures.size()," source_stable=",stable)
	quit(code if code>=0 else (0 if failures.is_empty() else 1))
