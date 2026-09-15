extends SceneTree
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	root.size = Vector2i(640, 480)
	var world := Node2D.new()
	root.add_child(world)
	current_scene = world
	var road := Polygon2D.new()
	road.polygon = PackedVector2Array([Vector2(100,-800),Vector2(800,-800),Vector2(800,0),Vector2(100,0)])
	road.color = Color("303840")
	road.z_index = 1
	world.add_child(road)
	var view := preload("res://world/harbor/terminal/HarborTerminalView.gd").new()
	world.add_child(view)
	var operations := preload("res://world/harbor/terminal/HarborTerminalOperations.gd").new()
	operations.architecture = view
	world.add_child(operations)
	operations.set_physics_process(false)
	for service in operations.fleet: service.set_physics_process(false)
	var service = operations.fleet[0]
	service.coach.position = Vector2(478, -400)
	service.heading = Vector2.UP
	service._sync_native(0.0)
	var camera := Camera2D.new()
	camera.position = service.coach.position
	world.add_child(camera)
	camera.make_current()
	for frame in 20: await process_frame
	await RenderingServer.frame_post_draw
	var rendered: Image = service._external_view.get_texture().get_image()
	root.get_texture().get_image().save_png("D:/geteco/artifacts/life-refinement-0911/terminal-exterior-composite-regression.png")
	rendered.save_png("D:/geteco/artifacts/life-refinement-0911/terminal-exterior-render-regression.png")
	var opaque := 0
	for y in rendered.get_height():
		for x in rendered.get_width():
			opaque += int(rendered.get_pixel(x, y).a > 0.5)
	print("EXTERIOR_COACH_RENDER opaque_pixels=", opaque, " shared_world=", service._external_view.find_world_3d() == view.viewport_3d.find_world_3d())
	# Check the first handoff while the long nose straddles the street layer.
	road.polygon = PackedVector2Array([Vector2(-400,130),Vector2(800,130),Vector2(800,210),Vector2(-400,210)])
	service.coach.position = Vector2(250, 91)
	service.heading = Vector2.DOWN
	service._sync_native(0.0)
	camera.position = service.coach.position
	for frame in 20: await process_frame
	await RenderingServer.frame_post_draw
	var handoff: Image = service._external_view.get_texture().get_image()
	var handoff_opaque := 0
	for y in handoff.get_height():
		for x in handoff.get_width(): handoff_opaque += int(handoff.get_pixel(x, y).a > 0.5)
	root.get_texture().get_image().save_png("D:/geteco/artifacts/life-refinement-0911/terminal-street-handoff-regression.png")
	print("COACH_STREET_HANDOFF exterior=", service._external, " opaque_pixels=", handoff_opaque)
	var passed: bool = opaque > 1200 and handoff_opaque > 1200 and service._external
	world.queue_free()
	await process_frame
	quit(0 if passed else 1)
