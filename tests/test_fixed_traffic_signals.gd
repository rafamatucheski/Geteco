extends SceneTree

var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	print(("PASS " if ok else "FAIL ") + message)
	if not ok: failures.append(message)

func _run() -> void:
	create_timer(30).timeout.connect(func(): quit(2))
	var stage := Node2D.new()
	root.add_child(stage)
	current_scene = stage
	var junction = load("res://geodata/roads/traffic/JunctionSignalVisual2D.gd").new()
	stage.add_child(junction)
	junction.position = Vector2(400, 300)
	junction.configure(&"fixed_signal_test", 48, [
		{"road_index": 0, "entry_tangent": Vector2.RIGHT, "road_width": 100},
		{"road_index": 1, "entry_tangent": Vector2.UP, "road_width": 100}])
	junction.set_road_states({0: 2, 1: 0})
	await physics_frame
	check(junction.signal_posts.size() == 2, "one permanent post per canonical approach")
	for post in junction.signal_posts:
		post.ensure_presentation()
		# Wait for the real camera matrices, not the viewport's initial state.
		for frame in 3: await process_frame
		check(post.collision_layer == 1 and post.collision_mask == 0, "post is a static world obstacle")
		check(post.sprite.texture is ViewportTexture, "signal display comes from a 3D model")
		var query := PhysicsRayQueryParameters2D.create(post.global_position - Vector2(20, 0), post.global_position + Vector2(20, 0), 1)
		var hit: Dictionary = post.get_world_2d().direct_space_state.intersect_ray(query)
		check(not hit.is_empty() and hit.collider == post, "solid foundation matches visual ground point")
		var viewport: SubViewport = post.render_view
		var pixel := viewport.get_camera_3d().unproject_position(Vector3.ZERO)
		var rendered_ground: Vector2 = post.sprite.to_global(pixel - Vector2(viewport.size) * 0.5)
		if DisplayServer.get_name() != "headless":
			check(rendered_ground.distance_to(post.global_position) < 0.01, "rendered base is anchored exactly to collision")
	var post = junction.signal_posts[0]
	var original_position: Vector2 = post.global_position
	var original_transform: Transform2D = post.transform
	var initial_texture = post.sprite.texture
	junction.set_road_states({0: 1, 1: 2})
	post.ensure_presentation()
	check(post.signal_state == 1 and post.sprite.texture != initial_texture, "road controller switches displayed aspect")
	junction.set_road_states({0: 2, 1: 0})
	post.ensure_presentation()
	check(post.sprite.texture == initial_texture, "unchanged orientation/aspect reuses shared 3D render")
	# Real production vehicle collision must damage the car and break the signal.
	var car = load("res://cars/traffic/TrafficVehicle.tscn").instantiate()
	stage.add_child(car)
	car.apply_archetype("sedan_classic")
	car.configure_as_parked()
	car.is_driven_by_player = true
	car.global_position = original_position - Vector2(90, 0)
	car.rotation = 0
	car.velocity = Vector2(430, 0)
	car.set_meta("vehicle_safe_position", car.global_position)
	car.reset_physics_interpolation()
	var health_before: int = car.health
	var deadline := Time.get_ticks_msec() + 5000
	while not post.broken and Time.get_ticks_msec() < deadline:
		await physics_frame
	check(car.health < health_before, "driving into signal damages car through production collision logic")
	check(car.body_model.impact_count > 0, "collision dents the actual vehicle model")
	check(post.broken and post.collision_layer == 0, "vehicle contact breaks signal and releases collision")
	await create_timer(0.7).timeout
	check(post.z_index == 7 and not post.z_as_relative, "fallen signal rests below vehicle bodies")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("D:/geteco/artifacts/post-signal-fallen.png")
	var fallen_texture = post.sprite.texture
	junction.set_road_states({0: 0, 1: 2})
	post.ensure_presentation()
	check(post.sprite.texture == fallen_texture, "phase changes cannot relight a broken signal")
	check(not junction.signal_posts[1].broken, "shared presentation does not break neighboring signals")
	car.queue_free()
	await process_frame
	post.restore_world_prop()
	await physics_frame
	await process_frame
	check(not post.broken and post.collision_layer == 1 and not post.get_node("Foundation").disabled, "renewal restores physical signal")
	check(post.transform == original_transform, "repair preserves original foundation")
	post.receive_vehicle_impact(34, Vector2.RIGHT)
	check(not post.broken, "contact below break threshold preserves signal")
	post.receive_vehicle_impact(35, Vector2.RIGHT)
	check(post.broken, "signal yields at 35 pixels per second")
	post.restore_world_prop()
	junction.configure(&"fixed_signal_test", 48, [{"road_index": 0, "entry_tangent": Vector2.RIGHT, "road_width": 100}])
	await process_frame
	check(get_nodes_in_group("fixed_traffic_signal").size() == 1, "junction rebuild removes stale physical poles")
	stage.queue_free()
	await process_frame
	check(get_nodes_in_group("fixed_traffic_signal").is_empty(), "scene teardown removes all pole collisions")
	print("FIXED_TRAFFIC_SIGNALS failures=", failures)
	quit(0 if failures.is_empty() else 1)
