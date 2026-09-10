extends SceneTree

const OUTPUT := "res://docs/measurements/hidden-collectibles-0910/"
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	print(("PASS " if ok else "FAIL ") + message)
	if not ok: failures.append(message)

func _run() -> void:
	root.size = Vector2i(960, 640)
	root.get_node("CampaignState").set_campaign_flag(&"harbor_arrival_seen", true)
	root.get_node("CampaignState").set_campaign_flag(&"harbor_call_complete", true)
	var world = load("res://world/harbor/HarborGame.tscn").instantiate()
	root.add_child(world)
	current_scene = world
	while not world.gameplay_ready: await process_frame
	for layer in world.find_children("", "CanvasLayer", true, false): layer.hide()
	world.get_node("Player").set_physics_process(false)
	var camera := Camera2D.new()
	camera.zoom = Vector2(2, 2)
	world.add_child(camera)
	camera.make_current()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	await physics_frame
	var count := 0
	for item in world.get_children():
		if not item is Collectible: continue
		count += 1
		var id: String = item.collectible_id
		var query := PhysicsShapeQueryParameters2D.new()
		var circle := CircleShape2D.new()
		circle.radius = 8.0
		query.shape = circle
		query.transform.origin = item.global_position
		query.collision_mask = 1
		var obstacles: Array = world.get_world_2d().direct_space_state.intersect_shape(query)
		check(obstacles.is_empty(), id + ": espaço livre para alcançar a maleta")
		for hit in obstacles: print("OBSTACLE ", hit.collider.get_path())
		var off_road := true
		var network = world.get_node("RoadNetwork")
		for road in network._roads:
			if network._distance_to_polyline(item.global_position, road.points) < float(road.width) * 0.5 + 16.0:
				off_road = false
		check(off_road, id + ": fora das vias e suas margens")
		var original_pose: Transform3D = item.model_3d.transform
		var original_offset: Vector2 = item.sprite_3d.position
		camera.global_position = item.global_position
		for i in 12: await process_frame
		check(item.model_3d.transform.is_equal_approx(original_pose) and item.sprite_3d.position.is_equal_approx(original_offset), id + ": apoiada no chão sem giro ou flutuação")
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(OUTPUT + id + ".png")
	check(count == 6, "Seis achados preservados")
	print("HIDDEN_COLLECTIBLES: ", failures)
	quit(0 if failures.is_empty() else 1)
