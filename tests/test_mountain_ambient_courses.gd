extends SceneTree
var failures := 0
func _initialize() -> void: run.call_deferred()
func run() -> void:
	root.get_node("SaveManager")._save_dir = "D:/geteco/artifacts/mountain-rebuild-0913/saves-ambient/"
	root.get_node("SaveManager")._save_directory_ready = false
	create_timer(45).timeout.connect(func(): quit(2))
	var world := preload("res://world/mountain_pass/MountainPass.tscn").instantiate()
	root.add_child(world)
	current_scene = world
	while not world.region_ready: await process_frame
	var observer: Node2D = world.player_instance
	observer.set_physics_process(false)
	observer.position = Vector2(7000,-3950)
	var camera := Camera2D.new()
	camera.zoom = Vector2.ONE*.2
	camera.set_meta("mountain_fixed_framing",true)
	observer.add_child(camera)
	camera.make_current()
	var skiers := get_nodes_in_group("mountain_skier")
	var impacts := {}
	var previous_fall := {}
	for skier in skiers: impacts[skier] = 0
	for frame in 1500:
		await physics_frame
		for skier in skiers:
			if skier.fallen_time>0: impacts[skier] += 1
			if skier.fallen_time>0 and not previous_fall.get(skier,false):
				print("IMPACT ",skier.name," ",skier.global_position," ",skier.get_slide_collision(0).get_collider().get_path() if skier.get_slide_collision_count()>0 else "unknown")
			previous_fall[skier] = skier.fallen_time>0
	for skier in skiers:
		var completed: bool = skier.target_index>=skier.course_points.size()
		print("COURSE ",skier.name," target=",skier.target_index,"/",skier.course_points.size()," impact_frames=",impacts[skier]," position=",skier.global_position)
		if not completed or impacts[skier]>0: failures += 1
	print("AMBIENT_COURSES failures=",failures)
	world.queue_free()
	await process_frame
	quit(1 if failures else 0)
