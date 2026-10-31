extends SceneTree
## Rota de integração renderizada finita; rode com o build .NET do projeto e --no-save.
## Os saltos regionais são teleportes de diagnóstico, NÃO prova das rotas de acesso/progressão.
## Padrão: todo quadro desenhado dos clipes é salvo. --external-video delega
## a gravação contínua ao operador. Nenhum dos modos é benchmark de desempenho.
const POLICE := Vector3(66, .15, 129)
const ROAD_START := Vector3(107, .1, 23)
const ROAD_END := Vector3(180, .1, 23)
var world
var weather
var planar
var folder := ""
var external_video := false
var errors: Array[String] = []
var checks := 0
var report := {"stages": [], "clips": [], "scope": "Rendered production restore, two Harbor views, walking out/back, garage entry/exit, regional climate hops and return. Regional teleports do not validate travel access, mission progression or driving. Frame readback is not performance evidence. Visual flicker requires inspection of the recorded sequence."}
var original_fps := 0
var view_ids: Array[int] = []
var operation := "initialization"
var deadline_ms := 0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		errors.append(message)
		push_error(message)

func run() -> void:
	if DisplayServer.get_name() == "headless" or "--no-save" not in OS.get_cmdline_user_args():
		push_error("Requires rendered .NET Godot and --no-save")
		quit(2)
		return
	folder = "res://evidence/coastal-final-route-%d-%d" % [OS.get_process_id(), Time.get_ticks_msec()]
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out-dir="): folder = arg.trim_prefix("--out-dir=")
		external_video = external_video or arg == "--external-video"
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder)) != OK:
		quit(2)
		return
	root.size = Vector2i(1280, 720)
	var watchdog := Timer.new()
	watchdog.wait_time = 1.0
	root.add_child(watchdog)
	watchdog.timeout.connect(func():
		if deadline_ms > 0 and Time.get_ticks_msec() > deadline_ms:
			deadline_ms = 0
			check(false, "Operation timed out: " + operation)
			write_report()
			print("COASTAL_FINAL_TIMEOUT ", operation, " output=", folder)
			quit(1))
	watchdog.start()
	DisplayServer.window_set_title("Coastal Final Route")
	original_fps = Engine.max_fps
	if not external_video: Engine.max_fps = 30
	seed(13102026)
	report.engine = Engine.get_version_info().string
	report.renderer = RenderingServer.get_current_rendering_method()
	report.gpu = RenderingServer.get_video_adapter_name()
	report.external_video = external_video
	report.resolution = str(root.size)
	# O caminho explícito pelo menu permite um load frio real enquanto --no-save impede
	# gravações automáticas. Nenhum caminho de save pessoal é lido ou gravado.
	var state = preload("res://runtime/GameState.gd").new()
	var intro: Dictionary = state.intro.snapshot()
	intro.phase = "complete"
	intro.location_id = "harbor_street"
	intro.inventory = {}
	intro.completed_missions = [preload("res://data/GarageSequence.gd").ID]
	check(state.intro.restore_snapshot(intro), "Isolated intro fixture valid")
	state.set_location("harbor")
	state.world_state.time = .45
	state.world_state.weather = 1
	state.world_state.rain_intensity = .25
	state.world_state.coastal_wetness = .63
	state.world_state.pedestrian = {"region": "harbor", "position": [POLICE.x, POLICE.y, POLICE.z]}
	var store = preload("res://runtime/SaveStore.gd").new()
	store.path = folder.path_join("isolated-checkpoint-%d.json" % Time.get_ticks_usec())
	check(store.save(state) == OK, "Isolated checkpoint saved")
	if not errors.is_empty():
		await finish()
		return
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	world.set_meta("menu_save_path", store.path)
	begin_operation("cold restore and startup", 125)
	root.add_child(world)
	current_scene = world
	var began := Time.get_ticks_msec()
	var first_wetness := -1.0
	while Time.get_ticks_msec() - began < 120000:
		await process_frame
		if world.session != null and world.session.weather != null and first_wetness < 0:
			first_wetness = world.session.weather.coastal_wetness
		if world.session != null and world.session.ready_for_play and world.production.startup_streaming_settled: break
	check(world.session != null and world.session.ready_for_play and world.production.startup_streaming_settled, "Production startup settled within 120 seconds")
	if not errors.is_empty():
		await finish()
		return
	weather = world.session.weather
	planar = world.get_node_or_null("CityLook/CoastalPlanarReflections")
	check(planar != null and is_instance_valid(planar.ground_view) and is_instance_valid(planar.facade_view), "Both production reflection targets exist")
	if not errors.is_empty():
		await finish()
		return
	view_ids = [planar.ground_view.get_instance_id(), planar.facade_view.get_instance_id()]
	check(world.production.loaded_save and world.production.no_save and world.production.store.path == store.path, "Actual cold load uses only the isolated checkpoint")
	check(absf(first_wetness - .63) < .03, "Cold load restores wetness without resetting it")
	check(weather.weather_state == 1 and absf(weather.rain_intensity - .25) < .001, "Cold load restores weather ID and rain intensity")
	check(Vector2(world.player.position.x - POLICE.x, world.player.position.z - POLICE.z).length() < 1.0, "Cold load restores Harbor position")
	world.gameplay.health = 1000000
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	world.camera.set_process_unhandled_input(false)
	world.camera.heading = 0
	world.camera.target_size = 48
	weather.weather_timer = 100000
	world.session.cold.set_process(false)
	world.session.cold.model.weather_clock = 120
	await settle()
	var original_sky: Sky = weather.coastal_look.previous_sky
	check_coast(true)
	check(weather.snow.draw_pass_1 != weather.precipitation.draw_pass_1 and weather.hail.draw_pass_1 != weather.precipitation.draw_pass_1, "Rain mesh does not alias snow/hail mesh")
	await stage("01-restored-police")
	print("COASTAL_FINAL_VIDEO_READY ", folder)
	if external_video: await create_timer(5).timeout
	await clip("02-police-static-orbit-return", 30.0)
	await visit(ROAD_START, "harbor")
	weather.time_of_day = .93
	weather._update()
	await settle()
	check_coast(false)
	await stage("03-second-harbor-night")
	await clip("04-walk-out", 30.0, ROAD_END)
	check(Vector2(world.player.position.x - ROAD_END.x, world.player.position.z - ROAD_END.z).length() < 2.0, "Walking outward reaches the real road endpoint")
	await stage("04-walk-out-endpoint")
	await clip("05-walk-back", 30.0, ROAD_START)
	check(Vector2(world.player.position.x - ROAD_START.x, world.player.position.z - ROAD_START.z).length() < 2.0, "Walking return reaches the starting point")
	await stage("06-second-harbor-return")
	weather.coastal_wetness = .63
	var wet_before: float = weather.coastal_wetness
	begin_operation("enter garage", 45)
	var entered: bool = await world.session.enter_place("maciota", false)
	check(entered, "Real garage entry succeeds")
	weather._update()
	await settle()
	var env: Environment = world.production.environment.environment
	check(not env.fog_enabled and not env.adjustment_enabled, "Garage suspends exterior fog and grading")
	check(not weather.coastal_look.installed and not planar._active, "Garage releases coastal sky and captures")
	check(not weather.precipitation.emitting and not weather.snow.emitting and not weather.hail.emitting, "Garage suppresses precipitation")
	check(not world.session.state.weapons_allowed(), "Garage still blocks weapons")
	check(weather.coastal_wetness >= wet_before and weather.weather_state == 1, "Garage preserves rainy state and retained wetness")
	check_targets_disabled()
	await stage("07-garage")
	if entered:
		begin_operation("leave garage", 45)
		check(await world.session.leave_place(), "Real garage exit succeeds")
	await settle()
	check_coast(false)
	await stage("08-garage-exit")
	await visit(Vector3(-450, .08, -1280), "desert")
	check(weather.drag_sky.installed and not weather.coastal_look.installed, "Drag strip owns sky after coast releases it")
	check(not planar._active, "Drag strip suspends coastal reflections")
	check_targets_disabled()
	await stage("09-drag-strip")
	await visit(Vector3(718, .08, -479), "mountain")
	check(weather.snow.emitting and weather.hail.emitting and not weather.precipitation.emitting, "Mountain peak has snow/hail instead of coastal rain")
	check(not weather.coastal_look.installed and not planar._active, "Mountain releases coastal resources")
	check_targets_disabled()
	await stage("10-mountain")
	await visit(Vector3(600, .08, -285), "mountain")
	check(not weather.snow.emitting and not weather.hail.emitting and not env.fog_enabled, "Tunnel shelters from snow/hail and exterior fog")
	await stage("11-tunnel")
	await visit(POLICE, "harbor")
	weather.time_of_day = .45
	weather._update()
	await settle()
	check_coast(true)
	check(not weather.drag_sky.installed and weather.coastal_look.previous_sky == original_sky, "Regional return restores original sky ownership")
	check(weather.weather_state == 1 and absf(weather.rain_intensity - .25) < .001, "Regional round trip preserves saved weather")
	check(view_ids == [planar.ground_view.get_instance_id(), planar.facade_view.get_instance_id()], "Transitions reuse the same two reflection targets")
	for ref in planar._registered.values():
		check(is_instance_valid(ref.get_ref()), "Streaming registry contains no freed visual")
	for entry in planar._batches.values():
		check(is_instance_valid(entry.visual) and is_instance_valid(entry.source.get_ref()), "Facade subset retains live source and proxy")
	await stage("12-harbor-recovered")
	await clip("13-recovered-static-orbit-return", 30.0)
	weather.weather_state = 0
	weather.coastal_wetness = 0
	weather._update()
	await settle()
	check(not planar._ground_active and planar._active, "Dry return disables wet ground capture while facade remains available")
	check(not weather.precipitation.emitting, "Dry return stops coastal rain")
	await stage("14-dry-return")
	print("COASTAL_FINAL_VIDEO_DONE")
	await finish()

func settle() -> void:
	begin_operation("settle " + str(world.player.position), 35)
	var began := Time.get_ticks_msec()
	while Time.get_ticks_msec() - began < 30000:
		await process_frame
		if Time.get_ticks_msec() - began < 1500: continue
		if world.production.region.is_streaming_idle() and planar._pending.is_empty(): return
	check(false, "Streaming and reflection registration settle within 30 seconds")

func visit(point: Vector3, region_id: String) -> void:
	begin_operation("diagnostic hop to " + region_id, 40)
	world.player.teleport(point)
	world.production._update_physical_residency(point)
	world.production._update_logical_region(point)
	world.production.region.set_focus(point)
	world.camera.initialized = false
	world.camera.heading = 0
	weather._update()
	await settle()
	check(world.session.state.region_id == region_id, "Diagnostic hop mounts expected region: " + region_id)

func check_coast(facade_required: bool) -> void:
	check(weather.coastal_look.installed and planar._active and planar._ground_active, "Rainy Harbor owns atmosphere and wet reflections")
	check(weather.precipitation.emitting and not weather.snow.emitting and not weather.hail.emitting, "Harbor emits only local rain")
	if facade_required:
		check(is_instance_valid(planar._facade), "Police facade selected after streaming")
		if is_instance_valid(planar._facade):
			check(planar._facade.material_override.get_shader_parameter("reflection_enabled"), "Selected facade receives real capture")
	var puddles = world.get_node_or_null("RainPuddles")
	check(puddles != null, "Production puddle consumer exists")
	if puddles != null: check(absf(puddles.wetness - weather.coastal_wetness) < .03, "Puddles share weather wetness")

func check_targets_disabled() -> void:
	check(planar.ground_view.render_target_update_mode == SubViewport.UPDATE_DISABLED and planar.facade_view.render_target_update_mode == SubViewport.UPDATE_DISABLED, "Both coastal capture targets suspended outside Harbor")

func stage(label: String) -> void:
	begin_operation("screenshot " + label, 10)
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(folder.path_join(label + ".png")) == OK, "Screenshot saved: " + label)
	report.stages.append({"id": label, "time_ms": Time.get_ticks_msec(), "position": str(world.player.position), "region": world.session.state.region_id, "place": world.session.state.place_id, "wetness": weather.coastal_wetness, "coastal": weather.coastal_look.installed, "planar": planar._active, "ground": planar._ground_active, "facade": is_instance_valid(planar._facade)})
	write_report()
	print("COASTAL_FINAL_STAGE ", label)

func clip(label: String, seconds: float, destination := Vector3.INF) -> void:
	begin_operation("temporal clip " + label, int(seconds) + 15)
	var directory := folder.path_join(label)
	if not external_video: check(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory)) == OK, "Clip folder created: " + label)
	var controls = root.get_node("GameInput")
	var walking := destination.is_finite()
	world.player.controlled_automatically = not walking
	controls.touch_sprint = false
	var began := Time.get_ticks_usec()
	var previous_draw := -1
	var missed := 0
	var writes_ok := true
	var frames: Array = []
	while Time.get_ticks_usec() - began < int(seconds * 1000000):
		var elapsed := (Time.get_ticks_usec() - began) / 1000000.0
		if walking:
			var direction: Vector3 = destination - world.player.global_position
			direction.y = 0
			var right: Vector3 = world.camera.global_basis.x
			var back: Vector3 = world.camera.global_basis.z
			right.y = 0
			back.y = 0
			var flat := direction.normalized()
			controls.touch_move = Vector2(flat.dot(right.normalized()), flat.dot(back.normalized())) if direction.length() > .8 else Vector2.ZERO
		else:
			world.camera.heading = 0.0 if elapsed < 10 else minf(elapsed - 10, seconds - elapsed) * .025
		await RenderingServer.frame_post_draw
		var drawn := Engine.get_frames_drawn()
		if previous_draw >= 0: missed += maxi(0, drawn - previous_draw - 1)
		previous_draw = drawn
		if not external_video:
			var frame := root.get_texture().get_image()
			frame.resize(960, 540, Image.INTERPOLATE_BILINEAR)
			writes_ok = frame.save_jpg(directory.path_join("%05d.jpg" % frames.size()), .88) == OK and writes_ok
		frames.append({"seconds": (Time.get_ticks_usec() - began) / 1000000.0, "draw": drawn, "position": str(world.player.position), "wetness": weather.coastal_wetness})
	controls.touch_move = Vector2.ZERO
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	world.camera.heading = 0
	check(writes_ok, "Clip frames written: " + label)
	report.clips.append({"id": label, "seconds": seconds, "missed_render_frames": missed, "writes_ok": writes_ok, "frames": frames})
	write_report()
	print("COASTAL_FINAL_CLIP ", label, " frames=", frames.size(), " missed=", missed)

func write_report() -> void:
	report.checks = checks
	report.errors = errors
	report.last_operation = operation
	var file := FileAccess.open(folder.path_join("result.json"), FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify(report, "\t"))

func finish() -> void:
	deadline_ms = 0
	write_report()
	Engine.max_fps = original_fps
	if is_instance_valid(world):
		world.queue_free()
		for index in 6: await process_frame
	print("COASTAL_FINAL_ROUTE ", "PASS" if errors.is_empty() else "FAIL", " checks=", checks, " errors=", errors, " output=", folder)
	quit(0 if errors.is_empty() else 1)

func begin_operation(label: String, timeout_seconds: int) -> void:
	operation = label
	deadline_ms = Time.get_ticks_msec() + timeout_seconds * 1000
	print("COASTAL_FINAL_BEGIN ", label)
