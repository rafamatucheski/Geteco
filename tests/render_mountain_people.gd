extends SceneTree

func _initialize() -> void: run.call_deferred()

func run() -> void:
	root.size = Vector2i(1440,1440)
	root.content_scale_size = root.size
	var scene := Node2D.new()
	root.add_child(scene)
	current_scene = scene
	for row in 3:
		for column in 3:
			var view := SubViewport.new()
			view.size = Vector2i(480,480)
			view.own_world_3d = true
			scene.add_child(view)
			var lighting := WorldEnvironment.new()
			lighting.environment = Environment.new()
			lighting.environment.background_mode = Environment.BG_COLOR
			lighting.environment.background_color = Color("54616a")
			lighting.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
			lighting.environment.ambient_light_energy = .55
			view.add_child(lighting)
			var sun := DirectionalLight3D.new()
			sun.rotation_degrees = Vector3(-40,-30,0)
			view.add_child(sun)
			var camera := Camera3D.new()
			view.add_child(camera)
			camera.projection = Camera3D.PROJECTION_ORTHOGONAL
			camera.size = 2.6
			camera.position = [Vector3(0,1.1,5),Vector3(5,1.1,0),Vector3(0,1.1,-5)][row]
			camera.look_at(Vector3(0,.9,0))
			if column == 0:
				var host := preload("res://scripts/player/DantePreviewRig.gd").new()
				scene.add_child(host)
				host.model_root = Node3D.new()
				view.add_child(host.model_root)
				host.build("dante_classic")
				host.model_root.scale = Vector3.ONE * 1.8/1.45
				host.model_root.rotation.y = PI
			else:
				var model: Node3D = preload("res://world/mountain_pass/MountainSkierModel.gd").new() if column == 2 else preload("res://world/mountain_pass/WinterResidentModel.gd").new()
				model.appearance_variant = 0
				model.coat_color = Color("a94735") if column == 2 else Color("426b70")
				model.role = "visitor"
				view.add_child(model)
				model.set_process(false)
				if column == 2: model.speed_factor = .7
				model._process(.1)
			var sprite := Sprite2D.new()
			sprite.texture = view.get_texture()
			sprite.position = Vector2(column*480+240,row*480+240)
			scene.add_child(sprite)
	for i in 10: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("D:/geteco/artifacts/mountain-rebuild-0913/people.png")
	scene.queue_free()
	await process_frame
	quit()
