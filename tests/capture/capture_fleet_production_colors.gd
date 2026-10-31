extends "res://tests/measure/measure_fleet_redesign.gd"
## Acompanhamento visual finito no Main real. Reaproveita o posicionamento do alvo e a pintura real
## de spawn; nunca chama scenario() nem coleta outra comparação de desempenho.
## Godot 4.7.2 .NET --path . --script res://tests/capture/capture_fleet_production_colors.gd
## -- --no-save --skip-arrival --population=24
## Prazo interno: 180 s. Watchdog externo sugerido: 210 s.

var _capture_finished := false
var _capture_started := 0
var _capture_anchor: Node3D
var _capture_report: Dictionary = {}

func run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if DisplayServer.get_name() == "headless" or "--no-save" not in args:
		push_error("Requires rendered Main and --no-save")
		quit(2)
		return
	if not ClassDB.class_exists(&"CSharpScript") or not OS.get_environment("HARBOR_NO_CSHARP").is_empty():
		push_error("Requires compiled Godot .NET; no GDScript routing fallback")
		quit(2)
		return
	label = "police-production-colors-v2"
	for arg: String in args:
		if arg.begins_with("--label="):
			label = arg.trim_prefix("--label=").validate_filename()
	folder = "res://evidence/fleet-redesign-20261011/validation/visual/" + label
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	_capture_started = Time.get_ticks_msec()
	_capture_report = {
		"purpose":"Real Main photographs after removing the benchmark's uniform red paint override; no new benchmark",
		"no_save_required":true, "capture_deadline_seconds":180,
		"seed":11102026, "requested_population":24, "time_of_day":.4, "weather":0,
		"targets":[], "photos":[], "runtime_sha256":{},
		"limits":["Still images do not certify temporal light stability or FPS.",
			"City/traffic remain active; this short follow-up does not reproduce their exact historical positions.",
			"The overview preserves the earlier benchmark camera; detail photographs change only the camera."]
	}
	create_timer(180.0).timeout.connect(func():
		if not _capture_finished: _capture_abort("Capture exceeded its finite 180 s deadline", 6))
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://evidence/fleet-redesign-20261011/manifest.json"))
	if not parsed is Dictionary:
		_capture_abort("Fleet manifest missing or invalid", 3)
		return
	manifest = parsed
	seed(11102026)
	for action: StringName in InputMap.get_actions():
		InputMap.action_erase_events(action)
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	root.add_child(world)
	current_scene = world
	var ready_deadline: int = Time.get_ticks_msec() + 120000
	while Time.get_ticks_msec() < ready_deadline:
		await process_frame
		if world.session != null and world.session.ready_for_play:
			break
	if world.session == null or not world.session.ready_for_play or not world.production.no_save:
		_capture_abort("Isolated Main did not become ready", 3)
		return
	if world.dispatch.router._native_graph() == null:
		_capture_abort("Native C# router is unavailable", 3)
		return
	OS.low_processor_usage_mode = false
	world.production.set_population(24)
	world.gameplay.health = 1000000
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	world.session.weather.set_process(false)
	world.player.teleport(Vector3(150, .05, 107.8))
	world.production.region.set_focus(world.player.global_position)
	_capture_anchor = Node3D.new()
	_capture_anchor.name = "FleetColorCaptureAnchor"
	world.add_child(_capture_anchor)
	_capture_camera(Vector3(150, .7, 107.8), Vector3(0, 40, 40), 48.0)
	var warm_deadline: int = Time.get_ticks_msec() + 15000
	while Time.get_ticks_msec() < warm_deadline:
		await process_frame
	if not await place_targets():
		_capture_abort("Could not place all ten real vehicles", 4)
		return
	car = targets[0].body
	world.player.teleport(Vector3(147, .05, 111.3))
	select_paired_model("final")
	world.session.weather.time_of_day = .4
	world.session.weather.weather_state = 0
	world.production.state.world_state.time = .4
	world.production.state.world_state.weather = 0
	world.session.weather._update()
	car.equipment.headlights_on = false
	var police: CharacterBody3D
	for target: Dictionary in targets:
		var body: CharacterBody3D = target.body
		var paint_colors: Array[String] = []
		for material: StandardMaterial3D in body._paint.materials:
			paint_colors.append(material.albedo_color.to_html(true))
		_capture_report.targets.append({
			"id":target.id, "paint":body.paint_color.to_html(true),
			"bound_paint_material_colors":paint_colors,
			"catalog_colors":FLEET.spec(target.id).get("colors", []),
			"position":str(body.global_position), "yaw":body.rotation.y,
			"scene":FLEET.REDESIGNED.scene_path(target.id),
			"scene_sha256":FileAccess.get_sha256(FLEET.REDESIGNED.scene_path(target.id)),
			"headlights_on":body.equipment.headlights_on,
			"model":target.after_metrics})
		if target.id == "police_cruiser":
			police = body
	if police == null or not police.paint_color.is_equal_approx(Color.WHITE):
		_capture_abort("Police did not retain its real white spawn paint", 5)
		return
	for source: String in [
		"res://tests/capture/capture_fleet_production_colors.gd",
		"res://tests/measure/measure_fleet_redesign.gd", "res://runtime/FleetCatalog.gd",
		"res://runtime/VehiclePaint.gd", "res://scripts/Vehicle.gd", "res://assets/fleet/catalog.json"]:
		_capture_report.runtime_sha256[source] = FileAccess.get_sha256(source)
	_capture_report.engine = Engine.get_version_info()
	_capture_report.native_router = true
	_capture_report.no_save = world.production.no_save
	_capture_report.renderer = RenderingServer.get_current_rendering_method()
	_capture_report.resolution = str(root.size)
	_capture_report.vsync = DisplayServer.window_get_vsync_mode()
	_capture_report.max_fps = Engine.max_fps
	if not await _capture_photo("ten-cars-real-colors", "Same overview camera as the earlier day-04-final image"):
		return
	# Usa pontos de vista mais altos a oeste para evitar os telhados que tamparam a primeira tentativa.
	_capture_camera(police.global_position + Vector3(0, .8, 0), Vector3(-12, 28, -16), 8.0)
	if not await _capture_photo("police-white-front", "Elevated western front three-quarter view; unchanged model, paint and day lighting"):
		return
	_capture_camera(police.global_position + Vector3(0, .8, 0), Vector3(-12, 32, 18), 8.0)
	if not await _capture_photo("police-white-rear", "Elevated western rear three-quarter view; unchanged model, paint and day lighting"):
		return
	_capture_finished = true
	_capture_report.ok = true
	_capture_report.elapsed_seconds = float(Time.get_ticks_msec() - _capture_started) / 1000.0
	write_json("capture", _capture_report)
	print("FLEET_PRODUCTION_COLOR_CAPTURE ", folder, " police=", police.paint_color.to_html(true))
	world.free()
	await process_frame
	quit(0)

func _capture_camera(focus: Vector3, offset: Vector3, size: float) -> void:
	_capture_anchor.global_position = focus
	world.camera.target = _capture_anchor
	world.camera.locked = true
	world.camera.heading = 0.0
	world.camera.offset = offset
	world.camera.target_size = size
	world.camera.size = size
	world.camera.global_position = focus + offset
	world.camera.look_at(focus)
	world.camera.make_current()

func _capture_photo(name: String, note: String) -> bool:
	for frame in 30:
		await process_frame
	await RenderingServer.frame_post_draw
	var path: String = folder + "/" + name + ".png"
	var result: Error = root.get_texture().get_image().save_png(ProjectSettings.globalize_path(path))
	if result != OK:
		_capture_abort("Could not save " + name + ": " + str(result), 7)
		return false
	_capture_report.photos.append({"file":path, "note":note,
		"camera_transform":str(world.camera.global_transform), "camera_size":world.camera.size,
		"focused":DisplayServer.window_is_focused(), "window_mode":DisplayServer.window_get_mode(),
		"engine_usec":Time.get_ticks_usec(), "load":load_snapshot()})
	return true

func _capture_abort(message: String, code: int) -> void:
	_capture_finished = true
	_capture_report.ok = false
	_capture_report.error = message
	_capture_report.elapsed_seconds = float(Time.get_ticks_msec() - _capture_started) / 1000.0
	write_json("capture", _capture_report)
	push_error(message)
	quit(code)
