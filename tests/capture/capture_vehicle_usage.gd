extends SceneTree
const VEHICLE := preload("res://scripts/Vehicle.gd")
const USAGE := preload("res://runtime/VehicleUsage.gd")
func _initialize() -> void: run.call_deferred()
func run() -> void:
	if DisplayServer.get_name() == "headless": quit(2); return
	var world := Node3D.new()
	root.add_child(world)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("68777c")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("c4d4de")
	environment.environment.ambient_light_energy = .65
	world.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, -30, 0)
	sun.light_energy = 1.6
	sun.shadow_enabled = true
	world.add_child(sun)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 8
	world.add_child(camera)
	camera.make_current()
	var folder := "res://evidence/vehicle-usage-20261002"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	for id in ["ranch_pickup", "lumber_pickup_4x4", "atlas_crew_pickup", "sertao_trail_pickup", "sedan_classic"]:
		for kind in 4:
			if id == "sedan_classic" and kind == 3: continue
			var target := Vector2i(mini(kind, 2), kind if id in USAGE.BEDS else 0)
			var car := VEHICLE.new()
			car.archetype = id
			for i in 500:
				var identity := "street_%d" % i
				if USAGE.profile(id, identity) == target: car.vehicle_id = identity; break
			car.paint_color = Color("a5b6ac")
			world.add_child(car)
			car.set_physics_process(false)
			for view in ["rear", "side"]:
				camera.position = Vector3(6, 5, 7) if view == "rear" else Vector3(7, 2, -4)
				camera.look_at(Vector3(0, .7, 0))
				for frame in 4: await process_frame
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png(folder + "/%s-%d-%s.png" % [id, kind, view])
			car.free()
	world.free()
	quit()
