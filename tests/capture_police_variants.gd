extends SceneTree

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	var scene := Node2D.new()
	root.add_child(scene)
	current_scene = scene
	root.get_node("WantedManager").set_process(false)
	var atlas := Image.create(1980, 900, false, Image.FORMAT_RGBA8)
	atlas.fill(Color("28303a"))
	for index in 11:
		var actor: Node2D
		if index == 0:
			actor = load("res://Player.gd").new()
			var camera := Camera2D.new()
			camera.name = "Camera"
			actor.add_child(camera)
		else:
			actor = load("res://PoliceOfficer.tscn").instantiate()
			actor.appearance_model = index - 1
			actor.set_meta("quiet_patrol", true)
			actor.set_meta("response_tier_level", 1)
		scene.add_child(actor)
		actor.set_physics_process(false)
		var viewport: SubViewport = actor.viewport_3d
		viewport.size = Vector2i(180, 300)
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		viewport.msaa_3d = Viewport.MSAA_4X
		var cam := viewport.get_camera_3d()
		cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		cam.size = 1.75
		cam.position = Vector3(0, 1.05, 3.5)
		cam.look_at(Vector3(0, .72, 0))
		# Identical illumination for Dante and every production police model.
		for child in viewport.get_children():
			if child is DirectionalLight3D:
				child.rotation_degrees = Vector3(-60, 35, 0)
				child.light_energy = 1.35
		for row in 3:
			actor.model_root.rotation.y = [PI, PI * .5, 0.0][row]
			for frame in 3: await process_frame
			await RenderingServer.frame_post_draw
			atlas.blend_rect(viewport.get_texture().get_image(), Rect2i(0, 0, 180, 300), Vector2i(index * 180, row * 300))
		actor.queue_free()
		await process_frame
	var output := "D:/geteco/artifacts/police-alley-0913/variants.png"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("output="): output = arg.trim_prefix("output=")
	atlas.save_png(output)
	print("POLICE_VARIANTS_CAPTURE ", output)
	quit()
