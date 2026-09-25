extends SceneTree
## Vista lateral da queda e repouso, com piso visível; usar renderização real.
const VEHICLE := preload("res://scripts/Vehicle.gd")
const OUTPUT := "res://evidence/wreck-collision-0924/"

func _initialize() -> void: run.call_deferred()

func run() -> void:
	if DisplayServer.get_name() == "headless": quit(2); return
	var world := Node3D.new()
	root.add_child(world)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.28, 0.33, 0.4)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.6, 0.65, 0.7)
	world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -25, 0)
	sun.shadow_enabled = true
	world.add_child(sun)
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = WorldBoundaryShape3D.new()
	floor_body.add_child(shape)
	var ground := MeshInstance3D.new()
	ground.mesh = PlaneMesh.new()
	ground.mesh.size = Vector2(60, 60)
	var asphalt := StandardMaterial3D.new()
	asphalt.albedo_color = Color(0.32, 0.32, 0.34)
	asphalt.roughness = 0.9
	ground.material_override = asphalt
	floor_body.add_child(ground)
	world.add_child(floor_body)
	var cars: Array[CharacterBody3D] = []
	for index in 2:
		var car := VEHICLE.new()
		car.archetype = ["sport_coupe", "american_dump_truck"][index]
		car.position = Vector3(-4 if index == 0 else 4, 0.12, 0)
		world.add_child(car)
		car.damage_look._rng.seed = 127
		cars.append(car)
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 17
	camera.look_at_from_position(Vector3(14, 5, 13), Vector3(0, 0.6, 0))
	for frame in 60: await physics_frame
	for car in cars: car.receive_damage(car.max_health * 2)
	for frame in 210:
		await physics_frame
		if frame in [10, 25, 40, 70, 200]:
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(OUTPUT + "wreck-%03d.png" % frame)
	print("WRECK_CAPTURE complete")
	world.queue_free()
	await process_frame
	quit(0)
