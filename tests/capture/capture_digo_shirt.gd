extends SceneTree
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("778c99")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_energy = .8
	world.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-30,-30,0)
	world.add_child(light)
	var digo := preload("res://gameplay/digo/DigoActor.gd").new()
	world.add_child(digo)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 1.5
	world.add_child(camera)
	camera.position = Vector3(.35,1.5,3)
	camera.look_at(Vector3(0,1.15,0))
	await create_timer(.5).timeout
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://evidence/digo")
	root.get_texture().get_image().save_png("res://evidence/digo/shirt.png")
	print("DIGO_SHIRT_CAPTURE_OK")
	world.free()
	quit()
