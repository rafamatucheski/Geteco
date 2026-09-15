extends SceneTree

func _initialize() -> void: run.call_deferred()

func run() -> void:
	root.size = Vector2i(1440, 1000)
	var paths := ["res://prototypes/living_cast/models/UnionSedanModel.gd", "res://prototypes/living_cast/CoupeDamageModel.gd"]
	var views: Array[SubViewport] = []
	for row in 2:
		for column in 2:
			var viewport := SubViewport.new()
			viewport.size = Vector2i(720,500)
			viewport.own_world_3d = true
			root.add_child(viewport)
			views.append(viewport)
			var environment := WorldEnvironment.new()
			environment.environment = Environment.new()
			environment.environment.background_mode = Environment.BG_COLOR
			environment.environment.background_color = Color("202932")
			environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
			environment.environment.ambient_light_color = Color.WHITE
			environment.environment.ambient_light_energy = 0.65
			viewport.add_child(environment)
			var light := DirectionalLight3D.new()
			light.rotation_degrees = Vector3(-45,-40,0)
			light.light_energy = 1.4
			viewport.add_child(light)
			var model: Node3D = load(paths[row]).new()
			viewport.add_child(model)
			var rig := preload("res://prototypes/living_cast/VehicleWheelRig.gd").new()
			rig.mount(model)
			rig.update(0.016, 0.0, 0.0, -0.58 if column == 0 else 0.58)
			var camera := Camera3D.new()
			camera.projection = Camera3D.PROJECTION_ORTHOGONAL
			camera.size = 4.6
			camera.position = Vector3(4,2.3,-5)
			viewport.add_child(camera)
			camera.look_at(Vector3(0,0.6,0))
			var display := TextureRect.new()
			display.texture = viewport.get_texture()
			display.position = Vector2(column*720,row*500)
			root.add_child(display)
	for i in 8: await process_frame
	await RenderingServer.frame_post_draw
	var output := Image.create(1440,1000,false,Image.FORMAT_RGBA8)
	for i in views.size():
		var shot := views[i].get_texture().get_image()
		shot.convert(Image.FORMAT_RGBA8)
		output.blit_rect(shot,Rect2i(0,0,720,500),Vector2i((i%2)*720,(i/2)*500))
	output.save_png("D:/geteco/artifacts/wheel-clearance.png")
	quit()
