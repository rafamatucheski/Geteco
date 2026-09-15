extends SceneTree
func _initialize() -> void: run.call_deferred()
func run() -> void:
	root.size = Vector2i(1440,960)
	var world := Node3D.new()
	root.add_child(world)
	for item in [["SportEstate",-2.0,"465c75"],["NordicEstate",2.0,"b69b66"]]:
		var model = load("res://prototypes/living_cast/models/"+item[0]+"Model.gd").new()
		model.position.x = item[1]
		model.paint.albedo_color = Color(item[2])
		world.add_child(model)
	var floor_mesh := MeshInstance3D.new()
	floor_mesh.mesh = PlaneMesh.new()
	floor_mesh.mesh.size = Vector2(200,200)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("29323c")
	floor_mesh.material_override = material
	world.add_child(floor_mesh)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("29323c")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color("d8e1f1")
	env.environment.ambient_light_energy = 0.65
	world.add_child(env)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45,-35,0)
	light.light_energy = 1.3
	light.shadow_enabled = true
	world.add_child(light)
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 11.0
	for view in [["front",Vector3(8,6,-10)],["rear",Vector3(-8,6,10)],["side",Vector3(10,5,0)]]:
		camera.position = view[1]
		camera.look_at(Vector3(0,0.65,0))
		for i in 5: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("D:/geteco/artifacts/estate-"+view[0]+".png")
	world.queue_free()
	await process_frame
	quit()
