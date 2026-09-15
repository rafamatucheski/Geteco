extends SceneTree
var failures: Array[String] = []

func _initialize() -> void:
	run.call_deferred()

func check(condition: bool, label: String) -> void:
	print(("PASS " if condition else "FAIL ") + label)
	if not condition: failures.append(label)

func run() -> void:
	root.size = Vector2i(1440, 900)
	root.content_scale_size = root.size
	var world := Node2D.new()
	root.add_child(world)
	current_scene = world
	var ground := Polygon2D.new()
	ground.polygon = PackedVector2Array([Vector2(-1000,-1000),Vector2(1000,-1000),Vector2(1000,1000),Vector2(-1000,1000)])
	ground.color = Color("a5aaa0")
	world.add_child(ground)
	var hospital = preload("res://world/harbor/hospital/HarborHospital.gd").new()
	hospital.name = "Clinic"
	hospital.footprint = Vector2(260,230)
	hospital.building_kind = "hospital"
	hospital.business_name = "BAY MEDICAL"
	world.add_child(hospital)
	var camera := Camera2D.new()
	camera.position = Vector2(20, -25)
	camera.zoom = Vector2.ONE * 2.4
	world.add_child(camera)
	await physics_frame
	await physics_frame
	check(hospital.is_in_group("hospital_emergency_admission"), "Production hospital exposes admission route")
	var circle := CircleShape2D.new()
	circle.radius = 13.0
	var clear := true
	for i in 101:
		var point: Vector2 = hospital.get_stretcher_exit_position().lerp(hospital.get_admission_inside_position(), i/100.0)
		var query := PhysicsShapeQueryParameters2D.new()
		query.shape = circle
		query.transform = Transform2D(0, point)
		query.collision_mask = 1
		clear = clear and world.get_world_2d().direct_space_state.intersect_shape(query).is_empty()
	check(clear, "Full stretcher envelope clears recessed corridor to interior")
	clear = true
	circle.radius = 6.0
	for offset in [-25.0, 25.0]:
		for i in 101:
			var point: Vector2 = hospital.get_stretcher_exit_position().lerp(hospital.get_admission_inside_position(), i/100.0) + Vector2(offset, 0)
			var crew_query := PhysicsShapeQueryParameters2D.new()
			crew_query.shape = circle
			crew_query.transform = Transform2D(0, point)
			crew_query.collision_mask = 1
			clear = clear and world.get_world_2d().direct_space_state.intersect_shape(crew_query).is_empty()
	check(clear, "Both stretcher attendants fit through the admission corridor")
	clear = true
	circle.radius = 9.0
	for side in [-1.0, 1.0]:
		var staging := PhysicsShapeQueryParameters2D.new()
		staging.shape = circle
		staging.transform = Transform2D(0, hospital.get_ambulance_stop_position() + Vector2(-78, side*19))
		staging.collision_mask = 1
		clear = clear and world.get_world_2d().direct_space_state.intersect_shape(staging).is_empty()
	check(clear, "Navigation clearance also reaches both rear-door staging points")
	clear = true
	for side in [-1.0, 1.0]:
		for i in 101:
			var around_rear := PhysicsShapeQueryParameters2D.new()
			around_rear.shape = circle
			around_rear.transform = Transform2D(0, hospital.to_global(Vector2(120, 40+side*i*.48)))
			around_rear.collision_mask = 1
			clear = clear and world.get_world_2d().direct_space_state.intersect_shape(around_rear).is_empty()
	check(clear, "Crew can turn around both rear corners in the recessed service walkway")
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(100,46)
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = rectangle
	query.transform = Transform2D(hospital.get_ambulance_stop_rotation(),hospital.get_ambulance_stop_position())
	query.collision_mask = 1
	check(world.get_world_2d().direct_space_state.intersect_shape(query).is_empty(), "Ambulance parking envelope clears hospital facade")
	check(hospital.get_node_or_null("Entrance") != null, "Public hospital entrance remains playable")
	hospital.set_emergency_door_open(true)
	for i in 65: await physics_frame
	check(hospital.emergency_door_amount > .99, "Glass doors open continuously before admission")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("D:/geteco/artifacts/life-refinement-0911/hospital-emergency-open.png")
	hospital.set_emergency_door_open(false)
	for i in 65: await physics_frame
	check(hospital.emergency_door_amount < .01, "Glass doors close after admission")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("D:/geteco/artifacts/life-refinement-0911/hospital-emergency-closed.png")
	print("HOSPITAL_EMERGENCY_ADMISSION failures=", failures)
	world.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
