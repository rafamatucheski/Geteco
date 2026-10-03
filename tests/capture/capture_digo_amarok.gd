extends SceneTree
const CAR := preload("res://gameplay/digo/DigoAmarok.gd")
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("bac8d0")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("e8f1fa")
	env.ambient_light_energy = .65
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.environment = env
	world.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-38,-35,0)
	light.light_energy = 1.6
	light.shadow_enabled = true
	world.add_child(light)
	var ground := MeshInstance3D.new()
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(200,200)
	ground.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("626b60")
	mat.roughness = 1
	ground.material_override = mat
	world.add_child(ground)
	var car := CAR.new()
	world.add_child(car)
	car.set_physics_process(false)
	var camera := Camera3D.new()
	camera.fov = 36
	world.add_child(camera)
	camera.position = Vector3(-5.5,3.0,-7.5)
	camera.look_at(Vector3(0,.95,0))
	root.size = Vector2i(1280,800)
	await process_frame
	await process_frame
	await create_timer(1.0).timeout
	DirAccess.make_dir_recursive_absolute("res://artifacts/digo")
	root.get_texture().get_image().save_png("res://artifacts/digo/amarok-front.png")
	camera.position = Vector3(5.0,3.3,7.3)
	camera.look_at(Vector3(0,.95,0))
	await create_timer(.3).timeout
	root.get_texture().get_image().save_png("res://artifacts/digo/amarok-rear.png")
	print("DIGO_AMAROK_CAPTURE artifacts/digo/amarok-front.png")
	world.free()
	quit()
