extends SceneTree
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	root.size = Vector2i(1280,720)
	var world := Node3D.new()
	root.add_child(world)
	var floor_mesh := MeshInstance3D.new()
	floor_mesh.mesh = BoxMesh.new()
	floor_mesh.mesh.size = Vector3(26,0.1,16)
	floor_mesh.position.y = -0.15
	floor_mesh.material_override = StandardMaterial3D.new()
	floor_mesh.material_override.albedo_color = Color("647780")
	world.add_child(floor_mesh)
	var models := ["SummitSUVModel","ArcticJeepModel","RanchSingleModel"]
	for i in models.size():
		var model: Node3D = load("res://prototypes/living_cast/models/"+models[i]+".gd").new()
		model.position = Vector3((i-1)*5,0,0)
		model.rotation.y = PI
		world.add_child(model)
		model.paint.albedo_color = [Color("376d80"),Color("e3e4d4"),Color("994c39")][i]
		var human := preload("res://district/mountain_pass/WinterResidentModel.gd").new()
		human.position = Vector3((i-1)*5-1.65,0,2.0)
		world.add_child(human)
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.position = Vector3(9,10,18)
	camera.look_at(Vector3(0,0.8,0))
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 18
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55,-35,0)
	sun.light_energy = 1.4
	sun.shadow_enabled = true
	world.add_child(sun)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("a3bbcf")
	environment.environment.ambient_light_energy = 0.7
	world.add_child(environment)
	for i in 15: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("D:/geteco/winter-fleet.png")
	world.queue_free()
	for i in 3: await process_frame
	quit()
