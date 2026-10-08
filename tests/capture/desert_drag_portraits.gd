extends SceneTree
## Bake the actual rival models once; the board uses static textures at runtime.
func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	if DisplayServer.get_name()=="headless": quit(2); return
	root.size=Vector2i(512,512)
	root.content_scale_size=Vector2i(512,512)
	root.content_scale_mode=Window.CONTENT_SCALE_MODE_DISABLED
	root.get_node("BuildWatermark").hide()
	var settings := root.get_node("V2Settings")
	settings.show_fps=false
	settings._update_fps_overlay()
	var scene := Node3D.new()
	root.add_child(scene)
	var environment := WorldEnvironment.new()
	environment.environment=Environment.new()
	environment.environment.background_mode=Environment.BG_COLOR
	environment.environment.background_color=Color("1c2732")
	environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color=Color("becbda")
	environment.environment.ambient_light_energy=.34
	scene.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees=Vector3(-25,-42,0)
	light.light_color=Color("f4e9db")
	light.light_energy=1.05
	scene.add_child(light)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees=Vector3(-15,115,0)
	fill.light_color=Color("a3c8e4")
	fill.light_energy=.55
	scene.add_child(fill)
	var camera := Camera3D.new()
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.size=.67
	camera.position=Vector3(.23,1.55,3)
	scene.add_child(camera)
	camera.look_at(Vector3(0,1.49,0))
	for id in ["digo","livia","raul","jessica","nadir"]:
		var model: Node3D
		if id=="digo": model=preload("res://gameplay/digo/DigoMeshyModel.gd").new()
		else:
			model=preload("res://runtime/desert/DesertCharacter.gd").new()
			model.identity_id=id
		scene.add_child(model)
		model.rotation.y=-.14
		model.set_physics_process(false)
		for i in 30: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://assets/desert_drag/portraits/"+id+".png")
		model.free()
	scene.free()
	quit()
