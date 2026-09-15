extends SceneTree

const OUTPUT := "D:/geteco/game/docs/measurements/cemetery-house-0910/"
var failures: Array[String] = []

func _initialize() -> void: run.call_deferred()

func screenshot(file: String) -> void:
	for i in 8: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUTPUT + file)
	print("CAPTURE ", file)

func run() -> void:
	create_timer(150).timeout.connect(func(): printerr("KEEPER_CAPTURE TIMEOUT"); quit(2))
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	root.size = Vector2i(1280,720)
	root.get_node("CampaignState").set_campaign_flag(&"harbor_arrival_seen", true)
	root.get_node("CampaignState").set_campaign_flag(&"harbor_call_complete", true)
	root.get_node("CampaignState").set_campaign_flag(&"cemetery_keeper_dead", false)
	var world = load("res://world/harbor/HarborGame.tscn").instantiate()
	root.add_child(world)
	current_scene = world
	while not world.gameplay_ready: await process_frame
	for i in 12: await process_frame
	var home = world.get_node("Cemetery/KeeperHouse")
	while home.room == null: await process_frame
	var room = home.room
	var keeper = home.keeper
	var player = world.get_node("Player")
	var weather = get_first_node_in_group("day_night_manager")
	weather.time_of_day = .5
	weather.set_process(false)
	weather._update_lighting()
	player.set_physics_process(false)
	player.global_position = home._outside_approach() + Vector2(24, 40)
	player.reset_physics_interpolation()
	var view := Camera2D.new()
	world.add_child(view)
	view.position = home.global_position + Vector2(25,10)
	view.zoom = Vector2.ONE * 2.8
	view.make_current()
	for layer in world.find_children("*", "CanvasLayer", true, false): layer.hide()
	await screenshot("01-cottage-exterior.png")
	# Use the same real entrance handler and player for the interior shot.
	player.global_position = home._outside_approach()
	for i in 3: await physics_frame
	assert(home.entrance.request_interaction(player), "Real player can enter cottage")
	await create_timer(.6).timeout
	assert(room.contains_point(player.global_position), "Gameplay manager recognizes the cottage interior")
	player.global_position = room.to_global(room.project_floor(Vector2(-.65,.6)))
	player.reset_physics_interpolation()
	view.global_position = room.global_position
	view.zoom = Vector2.ONE * 1.75
	home.reveal_secret()
	await screenshot("02-cottage-interior-day.png")
	# The room is observed before intrusion so the sleep pose can be reviewed.
	world.set_process(false)
	player.global_position = room.spawn_point.global_position
	player.reset_physics_interpolation()
	weather.time_of_day = .02
	weather.set_interior_mode(true)
	home.set_process(false)
	keeper.reparent(room)
	home._go_to_bed()
	room.art.set_night(true)
	room.set_npc_rendering_active(true)
	keeper.viewport_3d.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	room.show_message("00:28 — ANSELMO DORME. A PLACA AVISA: NÃO ENTRE DE MADRUGADA.")
	await screenshot("03-cottage-sleeping.png")
	player.global_position = room.spawn_point.global_position
	player.reset_physics_interpolation()
	home.disturb_keeper()
	await create_timer(1.1).timeout
	home._process(2.0)
	await screenshot("04-cottage-intrusion.png")
	print("CEMETERY_KEEPER_CAPTURE PASS")
	quit()
