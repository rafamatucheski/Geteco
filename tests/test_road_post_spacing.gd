extends SceneTree
var failures: Array[String] = []

func _initialize() -> void: _run.call_deferred()

func _audit(world: Node2D, label: String) -> void:
	var posts: Array[Node] = []
	for post in get_nodes_in_group("fragile_road_post"):
		if world.is_ancestor_of(post): posts.append(post)
	var pairs := 0
	var query := PhysicsShapeQueryParameters2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 5.5
	query.shape = circle
	query.collision_mask = 1
	for i in posts.size():
		query.transform = Transform2D(0, posts[i].global_position)
		query.exclude = [posts[i].get_rid()]
		for hit in world.get_world_2d().direct_space_state.intersect_shape(query, 64):
			if hit.collider is StaticBody2D:
				failures.append("%s foundation %s intersects %s" % [label, posts[i].get_path(), hit.collider.get_path()])
		for j in range(i + 1, posts.size()):
			var distance: float = posts[i].global_position.distance_to(posts[j].global_position)
			if distance < 40.0 - 0.01:
				failures.append("%s %s overlaps %s distance %.2f at %s / %s" % [label, posts[i].get_path(), posts[j].get_path(), distance, posts[i].global_position, posts[j].global_position])
			pairs += 1
	print("POST_AUDIT %s posts=%d pairs=%d failures=%d" % [label, posts.size(), pairs, failures.size()])

func _run() -> void:
	create_timer(240).timeout.connect(func(): quit(2))
	root.get_node("SaveManager")._save_dir = "D:/geteco/artifacts/post-spacing/test-saves/"
	root.get_node("SaveManager").clear_pending_save()
	var world = load("res://world/harbor/HarborGame.tscn").instantiate()
	root.add_child(world)
	current_scene = world
	while not world.gameplay_ready or not world.world_build_ready: await process_frame
	while not world.get_node("RoadLighting").ready_for_audit: await process_frame
	_audit(world, "harbor")
	var stream = world.get_node("ContinuousWorld")
	await stream.ensure_mountain()
	while not stream.ready_for_crossing: await process_frame
	while not stream.mountain.get_node("RoadLighting").ready_for_audit: await process_frame
	_audit(world, "harbor+mountain")
	for failure in failures: print("FAIL ", failure)
	quit(0 if failures.is_empty() else 1)
