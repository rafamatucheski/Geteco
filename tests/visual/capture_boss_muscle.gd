extends SceneTree

func _init() -> void:
	call_deferred("run")
func run() -> void:
	root.size = Vector2i(1440,900)
	var world := Node3D.new()
	root.add_child(world)
	current_scene = world
	var model := preload("res://prototypes/living_cast/BossMuscleModel.gd").new()
	world.add_child(model)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("20272c")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("b7c2d0")
	environment.environment.ambient_light_energy = 0.65
	world.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48,-28,0)
	sun.light_energy = 1.5
	sun.shadow_enabled = true
	world.add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-25,130,0)
	fill.light_energy = 0.6
	world.add_child(fill)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(200,200)
	floor_mesh.mesh = plane
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("343c42")
	material.roughness = 0.9
	floor_mesh.material_override = material
	world.add_child(floor_mesh)
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.position = Vector3(5,3.5,-6)
	camera.look_at(Vector3(0,0.55,0))
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 6.6
	for i in 12: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("D:/geteco/boss-muscle-reference.png")
	print("BOSS_MUSCLE_CAPTURE D:/geteco/boss-muscle-reference.png")
	quit()
