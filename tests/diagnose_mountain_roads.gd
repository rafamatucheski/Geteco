extends SceneTree

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	seed(9102026)
	change_scene_to_file("res://world/mountain_pass/MountainPass.tscn")
	while current_scene == null: await process_frame
	while not current_scene.region_ready: await process_frame
	var scene := current_scene
	var traffic: Node = scene.get_node("MountainTraffic")
	var path: Path2D = traffic.lane
	await physics_frame
	var hits := {}
	for car in traffic.vehicles:
		for offset in range(0, int(path.curve.get_baked_length()), 24):
			var pose := path.curve.sample_baked_with_rotation(offset, true)
			var query := PhysicsShapeQueryParameters2D.new()
			query.shape = car.collision.shape
			query.transform = path.global_transform * pose
			query.collision_mask = 1
			for hit in car.get_world_2d().direct_space_state.intersect_shape(query):
				if not hit.collider is StaticBody2D: continue
				var key: String = car.vehicle_id + ":" + str(hit.collider.get_path())
				if not hits.has(key): hits[key] = {"point":pose.origin,"offset":offset,"count":0}
				hits[key].count += 1
	print("LANE_SOLID_CONFLICTS ",hits)
	print("FLEET ",traffic.vehicles.map(func(v):return [v.vehicle_id,v.global_position]))
	if DisplayServer.get_name() != "headless":
		root.size = Vector2i(1280,720)
		root.content_scale_size = root.size
		var player: Node2D = scene.player_instance
		player.set_physics_process(false)
		scene.set_process(false)
		var cam := Camera2D.new()
		cam.zoom = Vector2.ONE * 1.5
		scene.add_child(cam)
		cam.make_current()
		DirAccess.make_dir_recursive_absolute("res://docs/measurements/mountain-0910")
		for shot in [["arrival",Vector2(6010,650)],["chalets",Vector2(8350,730)],["snow",Vector2(6600,-1900)]]:
			player.position = shot[1]+Vector2(0,90)
			cam.position = shot[1]
			cam.reset_physics_interpolation()
			for i in 25: await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://docs/measurements/mountain-0910/"+shot[0]+".png")
	scene.queue_free()
	await process_frame
	quit(0 if hits.is_empty() else 1)
