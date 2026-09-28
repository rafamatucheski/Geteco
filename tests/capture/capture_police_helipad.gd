extends SceneTree
## Captura o heliponto da delegacia com o helicóptero estacionado.
## Renderizado, sem --headless. Imagem em evidence/ (fora do Git).
var world: Node3D
func _initialize() -> void: run.call_deferred()
func run() -> void:
	if DisplayServer.get_name() == "headless" or "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	root.size = Vector2i(1280, 720)
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	root.add_child(world)
	for frame in 1800:
		await process_frame
		if world.session != null and world.session.ready_for_play: break
	if world.session == null or not world.session.ready_for_play: quit(3); return
	world.player.teleport(Vector3(68, .1, 138))
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	world.production._update_physical_residency(world.player.position)
	for frame in 90: await process_frame
	var parked := world.find_child("ParkedHelicopter", true, false) as Node3D
	print("HELIPAD parked=", parked != null, " at=", parked.global_position if parked != null else Vector3.ZERO)
	if parked == null: quit(4); return
	world.camera.target = parked
	world.camera.heading = 0
	world.camera.target_size = 16
	world.camera.initialized = false
	world.camera.set_process_unhandled_input(false)
	world.session.weather.time_of_day = .35
	world.session.weather._update()
	world.session.weather.set_process(false)
	for frame in 120: await process_frame
	await RenderingServer.frame_post_draw
	var folder := ProjectSettings.globalize_path("res://evidence/police-helipad-20260928")
	DirAccess.make_dir_recursive_absolute(folder)
	root.get_texture().get_image().save_png(folder.path_join("helipad.png"))
	print("HELIPAD saved")
	quit(0)
