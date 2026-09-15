extends SceneTree

class Fleet extends "res://world/harbor/urban_transit/UrbanTransit.gd":
	func _ready() -> void: pass

var failures: Array[String] = []
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	if not ok: failures.append(label)
	print(("PASS " if ok else "FAIL ") + label)

func run() -> void:
	create_timer(40,true,false,true).timeout.connect(func(): quit(2))
	var world := Node2D.new()
	root.add_child(world)
	current_scene = world
	var fleet := Fleet.new()
	world.add_child(fleet)
	var bus = preload("res://world/shared/traffic/TrafficVehicle.tscn").instantiate()
	bus.set_script(preload("res://world/harbor/urban_transit/UrbanBus.gd"))
	bus.system = fleet
	world.add_child(bus)
	bus.set_process(false)
	bus.set_physics_process(false)
	var template = load("res://world/harbor/HarborPreview.tscn").instantiate()
	var car = template.get_node("PlayerCar")
	template.remove_child(car)
	template.free()
	world.add_child(car)
	car.set_process(false)
	car.set_physics_process(false)
	car.camera.enabled = false
	var camera := Camera2D.new()
	world.add_child(camera)
	camera.zoom = Vector2.ONE * 3
	camera.make_current()
	root.size = Vector2i(900,800)
	root.content_scale_size = root.size
	await physics_frame
	await physics_frame
	for body in [bus] + bus.sections:
		for heading in [0.0, PI * .5]:
			body.rotation = heading
			for direction in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
				car.rotation = (-direction).angle()
				car.global_position = body.global_position + direction * 240
				await physics_frame
				var contacted := false
				# Exercise the production controller at its maximum supported speed.
				for frame in 32:
					await physics_frame
					car.velocity = -direction * 900
					preload("res://VehicleMotionSafety.gd").move(car)
					contacted = contacted or car.get_slide_collision_count() > 0
				check(contacted, "Swept car blocks against convoy: %s %s" % [heading,direction])
				check((car.global_position-body.global_position).dot(direction)>30, "Car remains on approach side")
			body.rotation = 0
	# Repeated steering against a long side must not insert a rotating corner.
	car.rotation = 0
	car.global_position = Vector2(0,-35.5)
	await physics_frame
	for i in 60:
		car.velocity = Vector2(130,0)
		car._apply_steering_motion(1.0,1.0/60.0)
		var query := PhysicsShapeQueryParameters2D.new()
		query.shape = car.get_node("Collision").shape
		query.transform = car.get_node("Collision").global_transform
		query.collision_mask = 2
		query.exclude = [car.get_rid()]
		check(car.get_world_2d().direct_space_state.intersect_shape(query,1).is_empty(), "Steering cannot penetrate bus: %d" % i)
	car.position = Vector2(600,600)
	car.rotation = 0
	await physics_frame
	car.velocity = Vector2(130,0)
	car._apply_steering_motion(1, .1)
	check(car.rotation > 0, "Steering still works in free space")
	# Repeat the visual contact with a real traffic pickup, like the report.
	car.queue_free()
	await process_frame
	car = preload("res://world/shared/traffic/TrafficVehicle.tscn").instantiate()
	world.add_child(car)
	car.apply_archetype("ranch_pickup",Color("702222"))
	car.set_process(false)
	car.set_physics_process(false)
	car._detached_from_lane = true
	for direction in [Vector2.UP, Vector2.DOWN]:
		bus.rotation = -PI*.5
		bus._update_3d_orientation(1)
		bus.sections[0].global_position = Vector2(0,134)
		bus.sections[0].rotation = bus.rotation
		bus.sections[0]._update_3d_orientation(1)
		car.rotation = (-direction).angle()
		var target: Node2D = bus if direction == Vector2.UP else bus.sections[0]
		car.global_position = target.global_position + direction * 200
		await physics_frame
		var contact := false
		for frame in 24:
			await physics_frame
			car.velocity = -direction * 600
			preload("res://VehicleMotionSafety.gd").move(car)
			contact = contact or car.get_slide_collision_count() > 0
		check(contact, "Traffic pickup physically contacts bus: " + str(direction))
		car.velocity = Vector2.ZERO
		car.reset_physics_interpolation()
		car.body_viewport.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		camera.position = target.global_position + direction * 40
		camera.reset_physics_interpolation()
		camera.force_update_scroll()
		await physics_frame
		await physics_frame
		car._update_3d_orientation(1)
		check(car.visual.z_index < bus.z_index if direction == Vector2.UP else car.visual.z_index > bus.z_index, "Pickup occludes correctly on approach side: " + str(direction))
		if DisplayServer.get_name() != "headless":
			for i in 6: await physics_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("D:/geteco/artifacts/dante-default-bus-0914/contact-%s.png" % ("north" if direction == Vector2.UP else "south"))
	car.position = Vector2(600,600)
	preload("res://world/harbor/urban_transit/UrbanVehicleDepth.gd").update(car,car.visual)
	check(car.visual.z_as_relative and car.visual.z_index == 0, "Leaving bus restores ordinary presentation depth")
	print("URBAN_BUS_PLAYER_CONTACT failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
