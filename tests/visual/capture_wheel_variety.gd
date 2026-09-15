extends SceneTree

const MODELS := ["MetroHatch", "UnionSedan", "OrbitaMicro", "SportEstate", "SummitSUV", "AuroraExecutive", "Boxrunner", "VerticeMidEngine"]

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	root.size = Vector2i(1440, 820)
	root.content_scale_size = root.size
	var canvas := CanvasLayer.new()
	root.add_child(canvas)
	var bg := ColorRect.new()
	bg.color = Color("18212b")
	bg.size = Vector2(1440, 820)
	canvas.add_child(bg)
	for i in MODELS.size():
		var viewport := SubViewport.new()
		viewport.size = Vector2i(350, 340)
		viewport.own_world_3d = true
		root.add_child(viewport)
		var world := Node3D.new()
		viewport.add_child(world)
		var model: Node3D = load("res://prototypes/living_cast/models/" + MODELS[i] + "Model.gd").new()
		world.add_child(model)
		var center := Vector3.ZERO
		for part in model.get_children():
			if part.has_meta("wheel_center"):
				var candidate: Vector3 = part.get_meta("wheel_center")
				if candidate.x > 0 and candidate.z < 0:
					center = candidate
		var rig := preload("res://prototypes/living_cast/VehicleWheelRig.gd").new()
		rig.mount(model)
		preload("res://cars/VehicleMeshBatcher.gd").batch_model(model)
		var camera := Camera3D.new()
		world.add_child(camera)
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera.size = 1.05
		camera.position = center + Vector3(2.0, 0.28, -0.28)
		camera.look_at(center)
		camera.current = true
		var light := DirectionalLight3D.new()
		light.rotation_degrees = Vector3(-35, -65, 0)
		light.light_energy = 1.8
		world.add_child(light)
		var env := WorldEnvironment.new()
		env.environment = Environment.new()
		env.environment.background_mode = Environment.BG_COLOR
		env.environment.background_color = Color("293542")
		env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.environment.ambient_light_color = Color.WHITE
		env.environment.ambient_light_energy = 0.8
		world.add_child(env)
		var image_rect := TextureRect.new()
		image_rect.texture = viewport.get_texture()
		image_rect.position = Vector2((i % 4) * 360 + 5, (i / 4) * 410 + 12)
		canvas.add_child(image_rect)
		var label := Label.new()
		label.text = MODELS[i]
		label.position = image_rect.position + Vector2(10, 350)
		label.add_theme_font_size_override("font_size", 23)
		canvas.add_child(label)
	for frame in 12:
		await process_frame
	await RenderingServer.frame_post_draw
	var path := "D:/geteco/artifacts/wheel-variety/rodas.png"
	root.get_texture().get_image().save_png(path)
	print("WHEEL_VARIETY_CAPTURE ", path)
	quit()
