extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
	root.size = Vector2i(1280,800)
	var scene := Node3D.new()
	root.add_child(scene)
	current_scene = scene
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("111a22")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color("bacde0")
	env.environment.ambient_light_energy = .65
	scene.add_child(env)
	var model := preload("res://world/harbor/campaign/Maciota350ZModel.gd").new()
	scene.add_child(model)
	var floor_mesh := MeshInstance3D.new()
	var floor_plane := PlaneMesh.new()
	floor_plane.size = Vector2(200,200)
	floor_mesh.mesh = floor_plane
	floor_mesh.material_override = model.material("263440",.2,.55)
	scene.add_child(floor_mesh)
	for config in [[Vector3(-50,-40,0),Color("fff0d6"),2.0],[Vector3(-30,140,0),Color("b1d3ff"),1.5]]:
		var light := DirectionalLight3D.new()
		light.rotation_degrees = config[0]
		light.light_color = config[1]
		light.light_energy = config[2]
		light.shadow_enabled = true
		scene.add_child(light)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 6.9
	camera.position = Vector3(-5,3.3,-6)
	scene.add_child(camera)
	camera.look_at(Vector3(0,.55,0))
	for i in 8: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("D:/geteco/artifacts/maciota-350z.png")
	camera.position = Vector3(-5,2.8,6)
	camera.look_at(Vector3(0,.55,0))
	for i in 4: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("D:/geteco/artifacts/maciota-350z-rear.png")
	assert(model.doors.size() == 2 and model.wheels.size() == 4 and model.occupants.size() == 2)
	model.door(0,true)
	model.roll(.5)
	await create_timer(.4).timeout
	assert(absf(model.doors[0].rotation.y + .9) < .01)
	quit()
