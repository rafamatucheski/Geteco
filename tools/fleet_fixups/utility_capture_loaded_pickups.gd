extends SceneTree
## Real Vehicle + VehicleUsage, photographed after the authored bed-floor fix.
## A still-life integration view; this is not a driving/performance benchmark.
const IDS := ["ranch_single", "ranch_pickup", "lumber_pickup_4x4", "atlas_crew_pickup", "sertao_trail_pickup"]
const USAGE := preload("res://runtime/VehicleUsage.gd")
const VEHICLE := preload("res://scripts/Vehicle.gd")

func _initialize() -> void: run.call_deferred()

func run() -> void:
	if DisplayServer.get_name() == "headless": quit(2); return
	root.size = Vector2i(1600,1000)
	Engine.max_fps = 60
	var folder := "res://evidence/fleet-redesign-20261011/utility/loaded-pickups"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var world := Node3D.new()
	root.add_child(world)
	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("86969e")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("c4d4de")
	env.ambient_light_energy = .65
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.environment = env
	world.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48,-30,0)
	sun.light_color = Color("ffe2b8")
	sun.light_energy = 1.6
	sun.shadow_enabled = true
	world.add_child(sun)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(200,200)
	ground.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("545c60")
	mat.roughness = .88
	ground.material_override = mat
	world.add_child(ground)
	var camera := Camera3D.new()
	camera.fov = 34
	camera.near = .05
	world.add_child(camera)
	camera.make_current()
	for id in IDS:
		for load_kind in [0,1]:
			var identity := ""
			for i in 500:
				var candidate := "street_%d" % i
				if USAGE.profile(id,candidate) == Vector2i(0,load_kind): identity=candidate; break
			if identity.is_empty(): push_error("No clean pickup identity: "+id); quit(1); return
			var car := VEHICLE.new()
			car.archetype = id
			car.vehicle_id = identity
			world.add_child(car)
			car.set_physics_process(false)
			camera.position = Vector3(5.3,4.2,6.5)
			camera.look_at(Vector3(0,.95,.4))
			for frame in 8: await process_frame
			await RenderingServer.frame_post_draw
			var label := "empty" if load_kind == 0 else "loaded"
			root.get_texture().get_image().save_png(folder+"/"+id+"-"+label+".png")
			print("PICKUP_PHOTO ",id," ",label)
			car.free()
			await process_frame
	world.free()
	quit()
