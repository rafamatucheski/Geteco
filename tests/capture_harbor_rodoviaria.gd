extends SceneTree
## Production scene evidence, including the real opening disembark.
const OUTPUT := "D:/geteco/artifacts/rodoviaria-3d-0910"
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)

func picture(camera: Camera2D, point: Vector2, zoom_value: float, filename: String) -> void:
	camera.position = point
	camera.zoom = Vector2.ONE * zoom_value
	camera.reset_smoothing()
	for i in 12:
		await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(OUTPUT.path_join(filename)) == OK, "Screenshot saved: " + filename)

func run() -> void:
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	root.size = Vector2i(1440, 900)
	root.content_scale_size = root.size
	root.get_node("CampaignState").reset_campaign()
	root.get_node("SaveManager").clear_pending_save()
	var world = load("res://world/harbor/HarborGame.tscn").instantiate()
	root.add_child(world)
	current_scene = world
	for i in 20:
		await process_frame
	var terminal = world.get_node("ArrivalStop")
	check(terminal.has_node("TerminalArchitecture"), "Production terminal includes the native 3D architecture")
	check(terminal.has_node("TerminalOperations"), "Production terminal includes the guarded coach circuit")
	check(world.get_node("District/FountainSolid").position.y > 1700, "Former fountain no longer obstructs bus platforms")
	world.campaign_controller.skip_cinematic()
	var deadline := Time.get_ticks_msec() + 20000
	while world.campaign_controller.phase != "phone" and Time.get_ticks_msec() < deadline:
		await process_frame
	check(world.campaign_controller.phase == "phone", "Dante completes physical disembark to the phone phase")
	check(world.get_node("Player").global_position.distance_to(world.get_node("ArrivalSpawn").global_position) < 4, "Terminal preserves the arrival walkway")
	world.campaign_controller.answer_phone()
	for i in 4:
		world.campaign_controller.advance_dialogue()
	var camera := Camera2D.new()
	world.add_child(camera)
	camera.make_current()
	world.weather.time_of_day = 0.45
	world.weather.weather_state = 0
	world.weather.set_rain_intensity(0.0)
	world.weather._update_lighting()
	await picture(camera, Vector2(1790, 1020), 1.8, "01_rodoviaria_no_jogo.png")
	for child in world.find_children("*", "CanvasLayer", true, false):
		if child.name != "OceanBackdrop":
			child.hide()
	for child in world.find_children("*", "Control", true, false):
		if child.name != "Sea":
			child.hide()
	await picture(camera, Vector2(1795, 1000), 1.7, "02_terminal_completo.png")
	await picture(camera, Vector2(1710, 905), 3.0, "03_plataformas_onibus_parados.png")
	await picture(camera, Vector2(2005, 1040), 3.4, "04_guarita_circulacao.png")
	var operations = terminal.terminal_operations
	if OS.get_cmdline_user_args().has("--passengers"):
		deadline = Time.get_ticks_msec() + 60000
		while operations.passenger_service.alighted < 2 and Time.get_ticks_msec() < deadline:
			await process_frame
		await picture(camera, Vector2(1920, 985), 3.2, "06_pessoas_desembarcando.png")
		while not is_instance_valid(operations.passenger_service._active_boarder) and Time.get_ticks_msec() < deadline:
			await process_frame
		await picture(camera, Vector2(1920, 985), 3.2, "07_pessoas_embarcando.png")
	deadline = Time.get_ticks_msec() + 90000
	while operations.exits < 1 and Time.get_ticks_msec() < deadline:
		await process_frame
	await picture(camera, Vector2(2005, 1020), 3.0, "05_onibus_saindo.png")
	check(operations.exits >= 1, "Coach passes the exit gate in the rendered production scene")
	print("RODOVIARIA_RENDERED_CIRCUIT ", operations.get_operation_status())
	print("RODOVIARIA_PRODUCTION failures=%d service=%s" % [failures.size(), terminal.get_service_status()])
	world.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
