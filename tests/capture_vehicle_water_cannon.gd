extends SceneTree
## Real Harbor scene, actual bay truck and normal boarding; rendered mouse-input QA.
func _init() -> void:
	call_deferred("_run")

func frames(count: int) -> void:
	for i in count: await physics_frame

func _run() -> void:
	root.size = Vector2i(1280, 720)
	var scene = load("res://world/harbor/HarborPreview.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await frames(30)
	var player = scene.get_node("Player")
	var station = scene.get_node("Interiors").fire_station_interior
	for truck_in_bay in station.bay_trucks:
		assert(truck_in_bay.has_node("WaterCannon"), "Every fire station bay must have a cannon")
	var truck = station.bay_trucks[0]
	truck.reparent(scene)
	truck.process_mode = Node.PROCESS_MODE_INHERIT
	truck.show()
	truck.global_position = Vector2(5840, -1100)
	truck.rotation = 0
	player.global_position = truck.global_position + Vector2(0, 50)
	truck.enter_vehicle(player)
	await frames(170)
	assert(truck.is_driven_by_player and not truck.has_meta("vehicle_boarding"), "Normal boarding finishes")
	var camera := Camera2D.new()
	scene.add_child(camera)
	camera.position = truck.global_position + Vector2(120, -25)
	camera.zoom = Vector2.ONE * 1.7
	camera.make_current()
	await frames(15)
	var car = load("res://world/shared/traffic/TrafficVehicle.tscn").instantiate()
	scene.add_child(car)
	car.apply_archetype("sedan_classic", Color("ce9d48"))
	car.configure_as_parked()
	car.global_position = truck.global_position + Vector2(265, -15)
	car.health = 70
	car.bloody_tires_timer = 4.0
	var cursor: Vector2 = truck.get_canvas_transform() * car.global_position
	root.warp_mouse(cursor)
	var motion := InputEventMouseMotion.new()
	motion.position = cursor
	motion.global_position = cursor
	motion.relative = Vector2(20, 0)
	Input.parse_input_event(motion)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.position = cursor
	click.pressed = true
	Input.parse_input_event(click)
	await frames(35)
	var cannon = truck.get_node("WaterCannon")
	print("MOUSE_CANNON firing=%s target=%s health=%s hovered=%s can=%s paused=%s action=%s disabled=%s dialogue=%s visible=%s processing=%s bindings=%s" % [cannon.firing, cannon.hit_target, car.health, root.gui_get_hovered_control(), cannon.can_operate(), paused, Input.is_action_pressed("fire"), player.is_control_disabled, player.is_in_dialogue, truck.is_visible_in_tree(), truck.can_process(), InputMap.action_get_events("fire")])
	if not cannon.firing or cannon.hit_target != car:
		quit(1)
		return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("D:/geteco/artifacts/water-cannon-harbor.png")
	# Change mouse direction while holding fire: turret and stream must follow.
	var old_angle: float = truck.body_model.water_turret.rotation.y
	cursor += Vector2(-240, -170)
	root.warp_mouse(cursor)
	motion.position = cursor
	motion.global_position = cursor
	Input.parse_input_event(motion)
	await frames(12)
	assert(absf(angle_difference(old_angle, truck.body_model.water_turret.rotation.y)) > 0.2, "Mouse motion rotates the 3D turret")
	click.pressed = false
	Input.parse_input_event(click)
	await frames(3)
	assert(not cannon.firing, "Real mouse release stops the stream")
	print("HARBOR_WATER_CANNON_MOUSE PASS")
	quit(0)
