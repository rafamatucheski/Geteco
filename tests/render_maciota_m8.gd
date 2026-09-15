extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	root.size = Vector2i(1280, 800)
	var scene := Node3D.new()
	root.add_child(scene)
	current_scene = scene
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("0d1116")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color("bdc9d4")
	env.environment.ambient_light_energy = .72
	scene.add_child(env)
	var model := preload("res://world/harbor/campaign/MaciotaM8SedanModel.gd").new()
	scene.add_child(model)
	var floor_mesh := MeshInstance3D.new()
	var floor_plane := PlaneMesh.new()
	floor_plane.size = Vector2(200, 200)
	floor_mesh.mesh = floor_plane
	floor_mesh.material_override = model.material("20262b", .25, .52)
	scene.add_child(floor_mesh)
	for config in [[Vector3(-50, -40, 0), Color("fff0d6"), 2.2], [Vector3(-30, 140, 0), Color("b1d3ff"), 1.6]]:
		var light := DirectionalLight3D.new()
		light.rotation_degrees = config[0]
		light.light_color = config[1]
		light.light_energy = config[2]
		light.shadow_enabled = true
		scene.add_child(light)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 5.8
	camera.position = Vector3(-5.6, 3.1, -6.4)
	scene.add_child(camera)
	camera.look_at(Vector3(0, .62, 0))
	for i in 10:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("D:/geteco/artifacts/maciota-m8-front.png")
	camera.position = Vector3(5.2, 2.8, 6.2)
	camera.look_at(Vector3(0, .62, 0))
	for i in 5:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("D:/geteco/artifacts/maciota-m8-rear.png")
	camera.size = 3.3
	camera.position = Vector3(-7, 1.35, 0)
	camera.look_at(Vector3(0, .66, 0))
	for i in 5:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("D:/geteco/artifacts/maciota-m8-side-fit.png")
	model.steer(.4)
	model.roll(1.2)
	camera.size = 2.0
	camera.position = Vector3(-5.6, 2.4, -6.4)
	camera.look_at(Vector3(-.5, .7, -.8))
	for i in 5:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("D:/geteco/artifacts/maciota-m8-steered-fit.png")
	assert(model.doors.size() == 4 and model.wheels.size() == 4 and model.occupants.size() == 2)
	model.door(0, true)
	model.roll(.5)
	await create_timer(.35).timeout
	assert(model.doors[0].rotation.y < -.40)
	quit()
