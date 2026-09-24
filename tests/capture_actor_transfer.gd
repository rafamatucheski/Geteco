extends SceneTree
var output := OS.get_temp_dir().path_join("geteco-transfer-before")
func _initialize() -> void: run.call_deferred()
func shot(label: String) -> void:
	for i in 4: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output + "-" + label + ".png")
func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("output="): output = arg.trim_prefix("output=")
	root.size = Vector2i(960, 640)
	root.content_scale_size = root.size
	var stage := Node2D.new()
	root.add_child(stage)
	current_scene = stage
	var player = load("res://characters/Player.gd").new()
	var camera := Camera2D.new()
	camera.name = "Camera"
	player.add_child(camera)
	stage.add_child(player)
	player.set_physics_process(false)
	player.set_process(false)
	player.equip_weapon("fists")
	for i in 90:
		player.meshy_rig.prepare_pose(1.0 / 60, false, false)
		player.combat_pose.update(player, 1.0 / 60, false, false, 0)
		player.meshy_rig.update_pose(1.0 / 60, false, false)
	camera.zoom = Vector2.ONE * 5.0
	var station = load("res://world/harbor/urban_transit/UrbanTubeStop.gd").new()
	station.position = Vector2(500, 350)
	stage.add_child(station)
	station.set_process(false)
	player.position = station.ramp_approach() + Vector2(8, 0)
	player.reset_physics_interpolation()
	await shot("street")
	station._actor_entered(player)
	await shot("station")
	station._actor_exited(player)
	station.queue_free()
	await process_frame
	var car = load("res://world/harbor/campaign/MaciotaTourCar.gd").new()
	car.position = player.position - Vector2(28, 0)
	stage.add_child(car)
	car.set_physics_process(false)
	await shot("car-street")
	var view := preload("res://world/harbor/campaign/TourActorPresentation.gd").new()
	stage.add_child(view)
	view.configure(player, car, 1.0)
	await shot("car-shared")
	print("ACTOR_TRANSFER_CAPTURE ", output)
	view.restore()
	stage.queue_free()
	await process_frame
	quit()
