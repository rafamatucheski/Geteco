extends SceneTree

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	root.size = Vector2i(1024, 512)
	var scene := Node2D.new()
	root.add_child(scene)
	current_scene = scene
	var ground := Polygon2D.new()
	ground.polygon = PackedVector2Array([Vector2(-400,-200),Vector2(400,-200),Vector2(400,200),Vector2(-400,200)])
	ground.color = Color("343e48")
	scene.add_child(ground)
	var camera := Camera2D.new()
	camera.zoom = Vector2(2.7, 2.7)
	scene.add_child(camera)
	camera.make_current()
	var wanted := root.get_node("WantedManager")
	wanted.reset_crime()
	wanted.set_process(false)
	await physics_frame
	await physics_frame
	var pool := root.get_node("EmergencyPool")
	for i in 3:
		var vehicle: Node2D = pool.get_vehicle("police")
		vehicle.configure_police_response(1 if i < 2 else 4, i + 1, i == 2)
		vehicle.position = Vector2((i - 1) * 125, 0)
		vehicle.rotation = -.3
		vehicle.set_physics_process(false)
		vehicle.lights.visible = true
	for i in 40: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("D:/geteco/artifacts/living-response-0912/police-fleet.png")
	print("POLICE_FLEET_CAPTURE PASS")
	quit()
