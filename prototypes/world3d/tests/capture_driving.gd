extends SceneTree
var world

func _initialize() -> void:
	call_deferred("run")

func capture(label: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://evidence/"+label+".png")

func run() -> void:
	world = load("res://Main.tscn").instantiate()
	root.add_child(world)
	world.camera.heading = -PI/8
	world.camera.target_size = 23
	await create_timer(1.0).timeout
	world.player.controlled_automatically = true
	world.player.speed = 3.5
	for destination in [Vector3(-7,0,9),Vector3(-5.85,0,9.15)]:
		for frame in 240:
			var direction: Vector3 = destination-world.player.position
			direction.y = 0
			if direction.length() < 0.12: break
			world.player.automatic_direction = direction.normalized()
			await physics_frame
	world.player.automatic_direction = Vector3.ZERO
	await create_timer(0.3).timeout
	await capture("systems-enter")
	if not world.driving.interact():
		push_error("Walking approach could not enter car")
		quit(1)
		return
	var car = world.driving.car
	car.external_input = true
	car.throttle_input = 1
	car.brake_input = false
	await create_timer(1.0).timeout
	await capture("systems-driving")
	car.throttle_input = 0
	car.brake_input = true
	await create_timer(1.0).timeout
	if not world.driving.leave():
		push_error("Rendered stopped exit failed")
		quit(1)
		return
	await create_timer(0.5).timeout
	await capture("systems-exit")
	world.player.teleport(Vector3(0,0.04,0))
	world.camera.target_size = 48
	await create_timer(1.0).timeout
	await capture("systems-overview")
	print("RENDERED_DRIVING_PASS walking approach, boarding, acceleration, braking, exit")
	world.queue_free()
	await process_frame
	quit()
