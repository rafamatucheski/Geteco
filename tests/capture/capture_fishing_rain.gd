extends "res://tests/measure/measure_fishing_life.gd"
## Captura no Main real / entrada nativa de pesca / contato da chuva / resposta da água.
## Padrão: todo quadro renderizado salvo como JPEG, limitado a 30 FPS, 32 s por chuva.
## --measure: 30 s por chuva sem imagens; preserva o limite/resolução configurados.
## Compile Harbor.csproj antes de rodar com o console do Godot 4.7.2 .NET.
const COVERAGE := preload("res://runtime/atmosphere/PrecipitationCoverage.gd")
var failures: Array[String] = []
var checks := 0
var measure_mode := false
var cases: Dictionary = {}
var lifecycle: Dictionary = {}
var source_start: Dictionary = {}
var process_inventory: Array = []
var weather_locked_for_capture := false
var rain_case := "startup"
var complete := false

func check(value: bool, message: String) -> void:
	checks += 1
	print("FISHING_RAIN ", "PASS " if value else "FAIL ", message)
	if not value: failures.append(message)

func _process(delta: float) -> bool:
	# Reaproveita o driver existente de E/segurar/soltar e suas amostras reais de relógio de parede.
	super._process(delta)
	if weather_locked_for_capture and is_instance_valid(world):
		var weather = world.session.weather
		var camera: Camera3D = world.get_viewport().get_camera_3d()
		# Congelar o relógio do clima não pode congelar a precipitação na câmera antiga.
		COVERAGE.follow(weather.precipitation, camera, world.player.global_position)
		weather.drag_rain.apply(weather.precipitation, camera, delta, weather.weather_state == 2)
		weather.drag_sky.update_lightning(weather.storm.envelope(weather.storm.flash_age) if weather.weather_state == 2 else 0.0, weather.storm.flashes)
	return false

func run() -> void:
	measure_mode = "--measure" in OS.get_cmdline_user_args()
	folder = FIXTURE.output_dir("fishing-rain-measure" if measure_mode else "fishing-rain-capture")
	# Só o início numa máquina compartilhada levou >200 s no timeout capturado. Mantém um
	# orçamento total finito, mais um orçamento de observação separado depois da prontidão.
	create_timer(420.0, true, false, true).timeout.connect(_timeout)
	if DisplayServer.get_name() == "headless":
		check(false, "requires the real rendered Main scene")
		_write_report("blocked_headless")
		quit(2)
		return
	if measure_mode and not _exclusive_render_process():
		_write_report("blocked_concurrent_renderer")
		quit(7)
		return
	if not measure_mode: Engine.max_fps = 30
	seed(71026)
	Engine.set_meta("fishing_baseline", false)
	source_start = fingerprint()
	source_start["rain_ground"] = FileAccess.get_sha256("res://runtime/atmosphere/RainGroundPresentation.gd")
	var snapshot := FIXTURE.full_snapshot(ENTRY, false)
	snapshot.campaign.active_id = ""
	snapshot.campaign.step = 0
	snapshot.economy.balance = 500
	var save_path := FIXTURE.write_fixture(folder, "isolated-save.json", snapshot)
	check(not save_path.is_empty(), "valid isolated save created without touching the player's save")
	if save_path.is_empty(): _write_report("blocked_fixture"); quit(2); return
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	world.set_meta("menu_save_path", save_path)
	root.add_child(world)
	current_scene = world
	while world.session == null or not world.session.ready_for_play or not world.production.startup_streaming_settled:
		await physics_frame
	create_timer(120.0, true, false, true).timeout.connect(_timeout)
	if not measure_mode:
		Engine.max_fps = 30
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(Vector2i(1280, 720))
		root.size = Vector2i(1280, 720)
		root.get_node("V2Settings").text_language = "pt_BR"
		TranslationServer.set_locale("pt_BR")
	world.production.no_save = true
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	world.camera.set_process_unhandled_input(false)
	world.driving.set_process_unhandled_input(false)
	world.session.state.campaign.cancel("fishing_rain_capture")
	for line in 12:
		if not world.session.dialogue_open: break
		fishing_input(true)
		fishing_input(false)
		await physics_frame
	check(not world.session.modal, "normal session controls available")
	world.dispatch.router.nearest_edge(world.player.global_position)
	check(world.dispatch.router._native != null, "production C# router loaded")
	if world.dispatch.router._native == null: _write_report("blocked_native"); quit(5); return
	world.production.region.set_focus(ENTRY)
	world.production.region.prepare_collision_at(ENTRY)
	world.player.teleport(ENTRY)
	world.session.fishing_runtime.refresh()
	var site = world.session.fishing_runtime.site
	check(is_instance_valid(site) and site.water_dynamics != null, "native venue owns a water height field")
	if not is_instance_valid(site): _write_report("blocked_site"); quit(6); return
	var station: Vector3 = site.fishing_spots()[0].position + Vector3.UP * .03
	world.player.teleport(station)
	site.set_focus(station)
	world.camera.initialized = false
	_set_weather(0, 0.0)
	await create_timer(2.0).timeout
	fishing_driver = world.session.fishing
	fishing_driver._rng.seed = 71026
	check(fishing_driver.start(-1), "normal free fishing equips the native rod and camera")
	if not fishing_driver.active: _write_report("blocked_fishing"); quit(6); return
	await create_timer(1.0).timeout
	var conditions := [{"id":"light_rain", "state":1, "level":.22}, {"id":"storm", "state":2, "level":1.0}]
	if "--storm-only" in OS.get_cmdline_user_args(): conditions = [conditions[1]]
	for condition in conditions:
		_set_weather(int(condition.state), float(condition.level))
		await create_timer(3.0).timeout
		await _record_case(str(condition.id), site, 30.0 if measure_mode else 32.0)
		_write_report("running")
	fishing_input(false)
	fishing_driver = null
	rain_case = "drying"
	_set_weather(0, 0.0)
	var dry_started := Time.get_ticks_usec()
	var impacts_at_stop: int = site.water_dynamics.impact_count
	await create_timer(9.0, true, false, true).timeout
	lifecycle.drying = {"seconds":float(Time.get_ticks_usec() - dry_started) / 1000000.0, "impacts_at_stop":impacts_at_stop, "impacts_after_pending":site.water_dynamics.impact_count, "active":site.water_dynamics.active, "max_abs_height":_max_height(site)}
	check(not site.water_dynamics.active, "wave field sleeps nine seconds after rain stops")
	check(_max_height(site) <= .000001, "sleeping wave field returns to zero height")
	check(not world.session.weather.rain_ground.is_physics_processing(), "rain contact probes stop with dry weather")
	world.session.fishing.cancel_attempt("rain_capture_complete")
	check(not world.session.fishing.active and not world.player.input_locked, "ending fishing restores player control")
	var old_id: int = site.get_instance_id()
	var old_field: WeakRef = weakref(site.water_dynamics)
	# Exercita a liberação e a remontagem do dono real da residência, nunca clona o local.
	var away := Vector3(132, .15, 72)
	world.production.region.set_focus(away)
	world.production.region.prepare_collision_at(away)
	world.player.teleport(away)
	world.session.fishing_runtime._release()
	for frame in 8: await process_frame
	check(not is_instance_valid(world.session.fishing_runtime.site), "leaving releases the lake through FishingRuntime")
	check(old_field.get_ref() == null, "leaving releases the old water simulation")
	world.production.region.set_focus(ENTRY)
	world.production.region.prepare_collision_at(ENTRY)
	world.player.teleport(ENTRY)
	world.session.fishing_runtime.refresh()
	var returned = world.session.fishing_runtime.site
	check(is_instance_valid(returned), "return remounts the real venue")
	if is_instance_valid(returned):
		returned.set_focus(ENTRY)
		lifecycle.returned = {"different_site":returned.get_instance_id() != old_id, "impact_count":returned.water_dynamics.impact_count, "active":returned.water_dynamics.active, "max_abs_height":_max_height(returned), "center_height":returned.water_dynamics.height_at(Vector2(0, -4))}
		check(returned.get_instance_id() != old_id, "return uses a new site instance")
		check(returned.water_dynamics.impact_count == 0 and not returned.water_dynamics.active and _max_height(returned) <= .000001, "returned lake starts dry and flat without stale impacts")
	complete = true
	_write_report("passed" if failures.is_empty() else "failed")
	print("FISHING_RAIN_RESULT ", folder, " checks=", checks, " failures=", failures)
	weather_locked_for_capture = false
	world.queue_free()
	for frame in 8: await process_frame
	quit(0 if failures.is_empty() else 1)

func _set_weather(state: int, level: float) -> void:
	var weather = world.session.weather
	weather.set_process(false)
	weather.time_of_day = .45
	weather.weather_state = state
	weather.weather_timer = 9999.0
	weather.rain_intensity = .22
	weather.rain_level = level
	weather._update()
	weather_locked_for_capture = true

func _record_case(title: String, site: Node3D, seconds: float) -> void:
	rain_case = title
	phase = title
	intervals[phase] = []
	var output := folder.path_join(title)
	if not measure_mode: DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	var weather = world.session.weather
	var before_impacts: int = site.water_dynamics.impact_count
	var before_water_hits: int = weather.rain_ground.water_impact_count
	var before_catches: int = fishing_driver.caught
	var case_started := Time.get_ticks_usec()
	last_tick = case_started
	tracing = true
	var frames: Array = []
	var images := 0
	var maximum_height := 0.0
	var last_observation := -1000000
	var observed_height := 0.0
	var statuses: Dictionary = {}
	while Time.get_ticks_usec() - case_started < seconds * 1000000.0:
		await RenderingServer.frame_post_draw
		var now := Time.get_ticks_usec()
		if not measure_mode or now - last_observation >= 500000:
			observed_height = _max_height(site)
			maximum_height = maxf(maximum_height, observed_height)
			last_observation = now
		var status := str(fishing_driver.phase)
		statuses[status] = int(statuses.get(status, 0)) + 1
		if not measure_mode:
			var image_path := output.path_join("frame-%05d.jpg" % images)
			var error := root.get_texture().get_image().save_jpg(image_path, .88)
			if error != OK:
				check(false, title + " could not save complete rendered sequence")
				break
			images += 1
		frames.append({"ms":float(now - case_started) / 1000.0, "phase":status, "water_impacts":site.water_dynamics.impact_count, "ground_water_hits":weather.rain_ground.water_impact_count, "max_abs_height":observed_height, "surface_at_cast":site.rain_surface_height_at(fishing_driver._cast_water), "catches":fishing_driver.caught})
	tracing = false
	var elapsed := float(Time.get_ticks_usec() - case_started) / 1000000.0
	var values: Array[float] = []
	values.assign(intervals[phase])
	var contact := _contacts(site, weather.rain_ground)
	var result := {"requested_seconds":seconds, "seconds":elapsed, "rendered_frames":frames.size(), "saved_frames":images, "every_rendered_frame":not measure_mode, "weather_state":weather.weather_state, "rain_level":weather.rain_level, "rain_strength":weather.rain_strength_at(world.player.global_position), "water_impacts":site.water_dynamics.impact_count - before_impacts, "ground_water_hits":weather.rain_ground.water_impact_count - before_water_hits, "maximum_abs_height":maximum_height, "fish_caught":fishing_driver.caught - before_catches, "phases":statuses, "water_contacts":contact, "frames":frames, "frame_intervals_ms":values}
	if not values.is_empty(): result.timing = stats(values)
	cases[title] = result
	check(elapsed >= seconds, title + " completes the bounded real-time observation")
	check(int(result.water_impacts) > 0 and int(result.ground_water_hits) > 0, title + " native raindrops reach and disturb the lake")
	check(maximum_height > .000001 and maximum_height <= .03501, title + " water responds within its bounded physical height")
	check(statuses.has("reeling") and int(result.fish_caught) > 0, title + " ordinary fishing inputs reel and capture a fish")
	check(int(contact.count) > 0 and float(contact.max_error) <= .081, title + " rendered drop contacts align with the moving water")
	check(measure_mode or images == frames.size(), title + " saves every observed frame")

func _max_height(site: Node3D) -> float:
	var peak := 0.0
	for value in site.water_dynamics.heights: peak = maxf(peak, absf(float(value)))
	return peak

func _contacts(site: Node3D, ground: Node3D) -> Dictionary:
	var result := {"count":0, "max_error":0.0}
	var batch: MultiMesh = ground.rings.multimesh
	for index in batch.instance_count:
		if batch.get_instance_custom_data(index).a < .5: continue
		var point: Vector3 = batch.get_instance_transform(index).origin
		if not site.contains_water(point): continue
		result.count += 1
		# Os anéis ficam quatro cm acima do contato; as ondas seguintes podem mover ±3.5 cm.
		result.max_error = maxf(float(result.max_error), absf(point.y - .04 - site.rain_surface_height_at(point)))
	return result

func _exclusive_render_process() -> bool:
	if OS.get_name() != "Windows":
		check(false, "measurement requires a supported external-renderer inventory")
		return false
	var command := "$ErrorActionPreference='Stop'; @(Get-CimInstance Win32_Process | Where-Object { $_.Name -match 'Godot' -and $_.Name -notmatch '_console' -and $_.ProcessId -ne %d -and $_.CommandLine -notmatch '(--headless|--editor|--import)' } | Select-Object ProcessId,Name,CommandLine) | ConvertTo-Json -Compress" % OS.get_process_id()
	var output: Array = []
	var exit_code := OS.execute("powershell.exe", PackedStringArray(["-NoProfile", "-NonInteractive", "-Command", command]), output, true)
	if exit_code != 0:
		check(false, "could not establish an exclusive renderer for measurement")
		return false
	var raw := "".join(output).strip_edges()
	if not raw.is_empty():
		var parsed: Variant = JSON.parse_string(raw)
		if parsed is Dictionary: process_inventory.append(parsed)
		elif parsed is Array: process_inventory = parsed
		else:
			check(false, "renderer process inventory could not be parsed")
			return false
	check(process_inventory.is_empty(), "measurement has no other active Godot renderer")
	return process_inventory.is_empty()

func _write_report(status: String) -> void:
	if folder.is_empty(): return
	var report := {"status":status, "checks":checks, "failures":failures, "current_case":rain_case, "performance_evidence":measure_mode and process_inventory.is_empty() and status == "passed", "capture_warning":"JPEG readback/encoding changes frame time; capture timings never approve performance.", "measure_mode":measure_mode, "process_inventory":process_inventory, "engine":Engine.get_version_info(), "gpu":RenderingServer.get_video_adapter_name(), "renderer":RenderingServer.get_current_rendering_method(), "resolution":str(root.size), "vsync":DisplayServer.window_get_vsync_mode(), "max_fps":Engine.max_fps, "cases":cases, "lifecycle":lifecycle, "source_before":source_start, "source_after":fingerprint(), "fixture":"Main.tscn, native C# routing, isolated save, frozen weather clock and normal fishing action input"}
	FileAccess.open(folder.path_join("report.json"), FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))

func _timeout() -> void:
	if complete: return
	check(false, "bounded startup/observation timeout during " + rain_case)
	_write_report("timed_out")
	quit(3)
