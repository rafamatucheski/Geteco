extends SceneTree
func _initialize() -> void: run.call_deferred()
func run() -> void:
	seed(123)
	var world := Node2D.new()
	root.add_child(world)
	current_scene = world
	root.get_node("WantedManager").set_process(false)
	for pier in preload("res://world/harbor/HarborSouthPortLayout.gd").PIERS:
		for rect in [Rect2(pier.position,Vector2(pier.size.x,5)),Rect2(pier.position+Vector2(0,95),Vector2(pier.size.x,5)),Rect2(pier.end-Vector2(5,100),Vector2(5,100))]:
			var body := StaticBody2D.new()
			var collision := CollisionShape2D.new()
			var shape := RectangleShape2D.new()
			shape.size = rect.size
			collision.shape = shape
			body.position = rect.get_center()
			body.add_child(collision)
			world.add_child(body)
	var routine = load("res://world/harbor/HarborLaunchRoutine.gd").new()
	world.add_child(routine)
	var camera := Camera2D.new()
	world.add_child(camera)
	camera.position = Vector2(6250,3980)
	camera.make_current()
	var departed := [false,false]
	var returned := [false,false]
	Engine.time_scale = 30
	for frame in 16000:
		await physics_frame
		for i in 2:
			var boat: Dictionary = routine.boats[i]
			# Accelerated visual checks must not overshoot the base actor's yaw lerp.
			boat.worker.model_root.rotation.y = -atan2(boat.worker.walk_dir.y,boat.worker.walk_dir.x)-PI*.5
			if boat.phase == "departing":
				if not departed[i] and DisplayServer.get_name() != "headless":
					await RenderingServer.frame_post_draw
					root.get_texture().get_image().save_png("D:/geteco/artifacts/launch-loaded-%d.png" % i)
				assert(boat.load == 30)
				assert(boat.worker.deliveries >= 30)
				departed[i] = true
			if departed[i] and boat.phase == "loading":
				assert(boat.load < 30)
				returned[i] = true
		if returned[0] and returned[1]:
			print("HARBOR_LAUNCH_ROUTINE PASS: two boats, 30 actual deliveries each, return empty")
			world.queue_free()
			await process_frame
			quit(0)
			return
	for boat in routine.boats: print("INCOMPLETE ",boat.phase," load=",boat.load," worker=",boat.worker.phase," position=",boat.worker.position)
	quit(1)
