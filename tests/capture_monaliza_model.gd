extends SceneTree
func _initialize() -> void: run.call_deferred()
func run() -> void:
	root.size = Vector2i(1280,800)
	var world := Node3D.new()
	root.add_child(world)
	var car := preload("res://district/harbor_preview/monaliza/MonalizaModel.gd").new()
	world.add_child(car)
	var floor_mesh := MeshInstance3D.new()
	floor_mesh.mesh = PlaneMesh.new()
	floor_mesh.mesh.size = Vector2(200,200)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("182332")
	floor_mesh.material_override = material
	world.add_child(floor_mesh)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("182332")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color("c8d4e6")
	env.environment.ambient_light_energy = 0.7
	world.add_child(env)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50,-30,0)
	light.light_energy = 1.3
	light.shadow_enabled = true
	world.add_child(light)
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 6.7
	camera.position = Vector3(5.7,3.6,-6.5)
	camera.look_at(Vector3(0,0.55,0))
	for i in 5: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("D:/geteco/monaliza-front-review.png")
	car.trunk_pivot.rotation.x = -1.1
	camera.position = Vector3(-5.7,4.1,6.5)
	camera.look_at(Vector3(0,0.65,0))
	for i in 3: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("D:/geteco/monaliza-trunk-review.png")
	world.queue_free()
	await process_frame
	quit()
