extends SceneTree

func _initialize() -> void: run.call_deferred()

func run() -> void:
	root.size = Vector2i(1440,960)
	var ids := ["bike_sport", "bike_cruiser", "bike_urban"]
	var views: Array[SubViewport] = []
	for row in 2:
		for column in 3:
			var viewport := SubViewport.new()
			viewport.size = Vector2i(480,480)
			viewport.own_world_3d = true
			root.add_child(viewport)
			views.append(viewport)
			var environment := WorldEnvironment.new()
			environment.environment = Environment.new()
			environment.environment.background_mode = Environment.BG_COLOR
			environment.environment.background_color = Color("202932")
			environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
			environment.environment.ambient_light_color = Color.WHITE
			environment.environment.ambient_light_energy = 0.70
			viewport.add_child(environment)
			var light := DirectionalLight3D.new()
			light.rotation_degrees = Vector3(-45,-40,0)
			light.light_energy = 1.35
			light.shadow_enabled = true
			viewport.add_child(light)
			var spec := VehicleCatalog.get_vehicle_spec(ids[column])
			var model: Node3D = load(spec.model_class).new()
			viewport.add_child(model)
			model.paint.albedo_color = spec.colors[row]
			model.set_rider_state(row == 1, false)
			var rig := preload("res://prototypes/living_cast/VehicleWheelRig.gd").new()
			rig.mount(model)
			rig.update(1.0,5,0,.16 if row == 1 else 0.0)
			preload("res://cars/VehicleMeshBatcher.gd").batch_model(model)
			model.update_riding_pose(1.0,5,.08,row == 1)
			var floor_mesh := MeshInstance3D.new()
			floor_mesh.mesh = PlaneMesh.new()
			floor_mesh.mesh.size = Vector2(200,200)
			var floor_mat := StandardMaterial3D.new()
			floor_mat.albedo_color = Color("2b353d")
			floor_mesh.material_override = floor_mat
			viewport.add_child(floor_mesh)
			var camera := Camera3D.new()
			camera.projection = Camera3D.PROJECTION_ORTHOGONAL
			camera.size = 3.05
			camera.position = Vector3(4,2.9,-5)
			viewport.add_child(camera)
			camera.look_at(Vector3(0,.8,0))
			var label := Label.new()
			label.text = spec.label + (" • PILOTO" if row == 1 else "")
			label.position = Vector2(22,24)
			label.add_theme_font_size_override("font_size",19)
			viewport.add_child(label)
			var display := TextureRect.new()
			display.texture = viewport.get_texture()
			display.position = Vector2(column*480,row*480)
			root.add_child(display)
	for i in 8: await process_frame
	await RenderingServer.frame_post_draw
	var output := Image.create(1440,960,false,Image.FORMAT_RGBA8)
	for i in views.size():
		var shot := views[i].get_texture().get_image()
		shot.convert(Image.FORMAT_RGBA8)
		output.blit_rect(shot,Rect2i(0,0,480,480),Vector2i((i%3)*480,(i/3)*480))
	output.save_png("D:/geteco/artifacts/motorcycles-fleet.png")
	quit()
