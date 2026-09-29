extends SceneTree
## No jogo de verdade (Main): Dante com mala de mão e pistola no porto, parado, andando, correndo,
## mirando e atirando, vistos pela câmera do jogo. Guarda em evidence/claude-mala-20260929/<rótulo>/.
var world

func _initialize() -> void: run.call_deferred()

func shot(out: String, label: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	# recorte em volta do personagem (câmera segue o Dante, que fica no centro)
	image.save_png(out + "/" + label + ".png")

func run() -> void:
	if DisplayServer.get_name() == "headless": quit(2); return
	var label := "jogo"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--label="): label = arg.split("=")[1]
	var out := ProjectSettings.globalize_path("res://evidence/claude-mala-20260929/" + label)
	DirAccess.make_dir_recursive_absolute(out)
	root.size = Vector2i(1280, 720)
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	root.add_child(world)
	for i in 2400:
		await process_frame
		if world.session != null and world.session.ready_for_play: break
	var session = world.session
	session.weather.time_of_day = .40
	session.weather.weather_state = 0
	session.weather._update()
	session.weather.set_process(false)
	session.urban_operations.security.authorized_visit = true
	var state = session.state
	state.economy.enable_grid_inventory()
	state.grant_weapon("pistol")
	state.economy.grid_equip_bag("handbag")
	state.equip_weapon("pistol")
	var point := Vector3(212, .1, 226)
	world.player.teleport(point)
	world.production.region.set_focus(point)
	for i in 240: await process_frame
	await shot(out, "01-parado")
	Input.action_press("move_left")
	for i in 60: await process_frame
	await shot(out, "02-andando-a")
	for i in 7: await process_frame
	await shot(out, "02-andando-b")
	Input.action_press("sprint")
	for i in 50: await process_frame
	await shot(out, "03-correndo-a")
	for i in 6: await process_frame
	await shot(out, "03-correndo-b")
	Input.action_release("sprint")
	Input.action_release("move_left")
	for i in 40: await process_frame
	await shot(out, "04-parou")
	Input.action_press("aim")
	for i in 40: await process_frame
	await shot(out, "05-mirando")
	var pf: Dictionary = world.gameplay._pose_frame
	print("DEBUG grid_handbag=", state.economy.grid_handbag(), " aiming=", world.gameplay.aiming, " weapon=", world.gameplay.equipped(), " left_solve=", pf.get("left_solve"), " left_grip=", pf.get("left_grip"), " support_locked=", pf.get("support_locked"), " left_weight=", pf.get("left_weight"), " combat_clip=", world.player.combat_clip)
	Input.action_press("fire")
	for i in 3: await process_frame
	await shot(out, "06-atirando-a")
	Input.action_release("fire")
	for i in 4: await process_frame
	await shot(out, "06-atirando-b")
	Input.action_press("move_up")
	for i in 40: await process_frame
	await shot(out, "07-mirando-andando")
	Input.action_release("move_up")
	Input.action_release("aim")
	print("CAPTURE_GAME_BAG done ", out, " stars=", world.gameplay.stars)
	world.free()
	await process_frame
	quit()
