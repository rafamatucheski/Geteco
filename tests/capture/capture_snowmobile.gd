extends SceneTree
## Snowmobile (bike_snow) como Vehicle de verdade, ao lado da moto urbana de onde ele vem, em quatro
## ângulos: confere esqui/esteira no chão, peças da moto que sobram e a pintura. Precisa de janela.
## Uso: "$GODOT" --path . --script res://tests/capture/capture_snowmobile.gd [-- cor_html]
## Saída em res://evidence/snowmobile/.
const VEHICLE := preload("res://scripts/Vehicle.gd")
const OUTPUT := "res://evidence/snowmobile/"

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	if DisplayServer.get_name() == "headless": quit(2); return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	root.size = Vector2i(1280, 720)
	var world := Node3D.new()
	root.add_child(world)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(.55, .6, .66)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(.7, .72, .78)
	environment.environment.ambient_light_energy = .7
	world.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 35, 0)
	sun.shadow_enabled = true
	world.add_child(sun)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(60, 60)
	ground.mesh = plane
	var snow := StandardMaterial3D.new()
	snow.albedo_color = Color(.86, .88, .9)
	ground.material_override = snow
	world.add_child(ground)
	var body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	collision.shape = WorldBoundaryShape3D.new()
	body.add_child(collision)
	world.add_child(body)
	var paint := Color.html(OS.get_cmdline_user_args()[0]) if not OS.get_cmdline_user_args().is_empty() else Color.TRANSPARENT
	var cars: Array = []
	for pair in [["bike_snow", -1.4], ["bike_urban", 1.4]]:
		var car := VEHICLE.new()
		car.archetype = pair[0]
		if paint.a > 0.0: car.paint_color = paint
		# Com piloto à mostra (trânsito): confere banco e manoplas.
		car.traffic = true
		world.add_child(car)
		car.place(Vector3(pair[1], .12, 0), 0.0)
		cars.append(car)
	for frame in 30: await physics_frame
	for car in cars:
		car.set_physics_process(false)
		print("SNOWMOBILE ", car.archetype, " banco=", car._motorcycle_seat, " manoplas=", car.motorcycle_handholds())
		var lowest := INF
		for mesh: MeshInstance3D in car.visual.find_children("*", "MeshInstance3D", true, false):
			if not mesh.is_visible_in_tree() or mesh.mesh == null: continue
			var bounds: AABB = mesh.global_transform * mesh.get_aabb()
			lowest = minf(lowest, bounds.position.y)
		print("SNOWMOBILE ", car.archetype, " y=%.3f visual_y=%.3f menor_ponto=%.3f pintura=%d cor=%s" % [car.global_position.y, car.visual.position.y, lowest, car._paint.materials.size(), car.paint_color.to_html(false)])
	var camera := Camera3D.new()
	camera.fov = 35
	world.add_child(camera)
	for view in [["frente", Vector3(0, 1.6, -7)], ["lado", Vector3(-7, 1.2, 0)], ["tras", Vector3(1.5, 2.0, 7)], ["alto", Vector3(4, 6, -4)]]:
		camera.look_at_from_position(view[1], Vector3(0, .6, 0))
		for frame in 4: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path(OUTPUT + view[0] + ".png"))
	print("SNOWMOBILE_DONE ", ProjectSettings.globalize_path(OUTPUT))
	quit(0)
