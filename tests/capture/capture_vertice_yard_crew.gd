extends SceneTree
## Fotos reais da Vértice: reach-stackers novos, empilhadeiras dirigíveis,
## operadores no pátio e o escritório bagunçado com funcionários.
const OUT := "res://evidence/vertice-yard-crew-20260928/"
func _initialize() -> void: run.call_deferred()
func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path(OUT+name))
func run() -> void:
	if DisplayServer.get_name()=="headless" or "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	root.add_child(world)
	current_scene = world
	for i in 2400:
		await process_frame
		if world.session != null and world.session.ready_for_play: break
	if world.session == null or not world.session.ready_for_play: quit(3); return
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	world.session.weather.time_of_day = .42
	world.session.weather.weather_state = 0
	world.session.weather._update()
	world.session.weather.set_process(false)
	var origin := Vector3(-340,0,-80)
	world.player.teleport(origin+Vector3(0,.1,38))
	world.production.region.set_focus(world.player.position)
	world.camera.heading = 0
	world.camera.target_size = 38
	world.camera.locked = true
	world.camera.initialized = false
	for i in 420: await process_frame
	await _shot("yard.png")
	world.camera.target_size = 16
	world.camera.initialized = false
	world.player.teleport(origin+Vector3(22,.1,43))
	for i in 150: await process_frame
	await _shot("forklifts.png")
	world.player.teleport(origin+Vector3(0,.1,30))
	for i in 120: await process_frame
	await _shot("reach-stacker.png")
	world.player.teleport(origin+Vector3(35,.1,18))
	for i in 150: await process_frame
	await _shot("office.png")
	print("VERTICE_CREW_CAPTURE saved")
	quit()
