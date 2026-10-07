extends SceneTree
## Bake the actual rival models once; the board uses static textures at runtime.
func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	if DisplayServer.get_name()=="headless": quit(2); return
	root.size=Vector2i(384,384)
	root.content_scale_size=Vector2i(384,384)
	root.content_scale_mode=Window.CONTENT_SCALE_MODE_DISABLED
	root.get_node("BuildWatermark").hide()
	var scene := Node3D.new()
	root.add_child(scene)
	var environment := WorldEnvironment.new()
	environment.environment=Environment.new()
	environment.environment.background_mode=Environment.BG_COLOR
	environment.environment.background_color=Color("354847")
	environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color=Color("e6d8c0")
	environment.environment.ambient_light_energy=.65
	scene.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees=Vector3(-25,-35,0)
	light.light_energy=1.6
	scene.add_child(light)
	var camera := Camera3D.new()
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.size=.88
	camera.position=Vector3(0,1.53,3)
	scene.add_child(camera)
	camera.look_at(Vector3(0,1.48,0))
	for id in ["digo","livia","raul","jessica","nadir"]:
		var model: Node3D
		if id=="digo": model=preload("res://gameplay/digo/DigoMeshyModel.gd").new()
		elif id=="jessica": model=preload("res://gameplay/jessica/JessicaModel.gd").new()
		else:
			model=preload("res://runtime/desert/DesertCharacter.gd").new()
			model.identity_id=id
		scene.add_child(model)
		model.set_physics_process(false)
		for i in 5: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://assets/desert_drag/portraits/"+id+".png")
		model.free()
	scene.free()
	quit()
