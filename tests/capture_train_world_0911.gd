extends SceneTree
## Captura a ferrovia na cena real, incluindo o jogador sob o viaduto.
const OUTPUT := "D:/geteco/artifacts/collision-fix-0911/train-world"

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	create_timer(100.0).timeout.connect(func(): quit(2))
	root.size = Vector2i(1280, 720)
	root.content_scale_size = root.size
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	root.get_node("CampaignState").set_campaign_flag(&"harbor_delivery_complete", true)
	change_scene_to_file("res://world/harbor/HarborGame.tscn")
	while current_scene == null or not current_scene.gameplay_ready: await process_frame
	var world := current_scene
	var rail = world.find_child("RailLine", true, false)
	if rail == null:
		for node in world.find_children("*", "Node2D", true, false):
			if node.get_script() == load("res://world/harbor/HarborRailLine.gd"):
				rail = node
				break
	if rail == null:
		push_error("Ferrovia não encontrada na cena real")
		quit(1)
		return
	var train = rail.get_node("AmbientTrain")
	world.process_mode = Node.PROCESS_MODE_DISABLED
	# A simulação para, mas os SubViewports precisam renderizar as novas poses.
	train.locomotive.viewport.process_mode = Node.PROCESS_MODE_ALWAYS
	for wagon in train._freight_visuals:
		wagon.viewport.process_mode = Node.PROCESS_MODE_ALWAYS
	var player := get_first_node_in_group("player") as Node2D
	var camera := Camera2D.new()
	camera.process_mode = Node.PROCESS_MODE_ALWAYS
	world.add_child(camera)
	camera.zoom = Vector2.ONE * 1.8
	camera.make_current()
	var curve: Curve2D = rail.get_route_curve()
	for shot in [
		["train-overview", Vector2(1600, 892), Vector2(1490, 1010), 1.8],
		["train-underpass-person", Vector2(1420, 892), Vector2(1300, 892), 2.5],
		["train-curve", Vector2(3114, 1220), Vector2(3000, 1110), 2.0],
		["train-tunnel", Vector2(3114, 3320), Vector2(3030, 3200), 1.8],
	]:
		train._progress = curve.get_closest_offset(shot[1])
		train._update_pose()
		player.global_position = rail.to_global(shot[2])
		player.visible = true
		rail._process(1.0)
		camera.global_position = train.global_position - Vector2(145, 0) if shot[0] != "train-curve" and shot[0] != "train-tunnel" else train.global_position - Vector2(0, 110)
		camera.zoom = Vector2.ONE * float(shot[3])
		camera.force_update_scroll()
		for i in 8:
			await physics_frame
			train._update_pose()
		print("TRAIN_POSE ", shot[0], " heading=", train.global_rotation, " model=", train.locomotive.model.rotation.y)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(OUTPUT + "/" + shot[0] + ".png")
		print("TRAIN_CAPTURE ", shot[0])
	var cars := get_nodes_in_group("vehicle").filter(func(node: Node) -> bool: return node.get("is_driven_by_player") != null)
	if not cars.is_empty():
		var car := cars[0] as Node2D
		car.set("is_driven_by_player", true)
		car.global_position = rail.to_global(Vector2(1300, 892))
		car.global_rotation = PI * 0.5
		car.visible = true
		if car.has_method("ensure_presentation"): car.ensure_presentation()
		player.hide()
		car.set("is_driven_by_player", true)
		car.reset_physics_interpolation()
		train._progress = curve.get_closest_offset(Vector2(1420, 892))
		camera.global_position = rail.to_global(Vector2(1310, 892))
		camera.zoom = Vector2.ONE * 2.3
		camera.force_update_scroll()
		rail._process(1.0)
		print("TRAIN_CAR_REVEAL amount=", rail._reveal_amount, " point=", rail._reveal_position, " car=", car.global_position, " driven=", car.get("is_driven_by_player"))
		for i in 8:
			await physics_frame
			train._update_pose()
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(OUTPUT + "/train-underpass-car.png")
		print("TRAIN_CAPTURE train-underpass-car")
	print("TRAIN_CAPTURE_DONE")
	world.queue_free()
	await process_frame
	quit()
