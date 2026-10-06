extends SceneTree
## Isolated art inspection only; does not certify integrated game performance.
const CARS := preload("res://gameplay/desert_cars/DesertCarCatalog.gd")
var output := "res://evidence/desert-cars"

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	if DisplayServer.get_name()=="headless": quit(2); return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--evidence-dir="): output=arg.trim_prefix("--evidence-dir=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	root.size=Vector2i(1440,900)
	var scene := Node3D.new()
	root.add_child(scene)
	var environment := WorldEnvironment.new()
	environment.environment=Environment.new()
	environment.environment.background_mode=Environment.BG_COLOR
	environment.environment.background_color=Color("82755f")
	environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color=Color("c1c9d0")
	environment.environment.ambient_light_energy=.72
	scene.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees=Vector3(-45,-30,0)
	sun.light_color=Color("ffe3b1")
	sun.light_energy=1.2
	sun.shadow_enabled=true
	scene.add_child(sun)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size=Vector2(80,80)
	ground.mesh=plane
	var sand := StandardMaterial3D.new()
	sand.albedo_color=Color("a68c68")
	sand.roughness=.95
	ground.material_override=sand
	scene.add_child(ground)
	var models: Array[Node3D]=[]
	for i in CARS.IDS.size():
		var model := CARS.create_model(CARS.IDS[i])
		model.position=Vector3((i-2)*3.9,0,0)
		scene.add_child(model)
		models.append(model)
	var camera := Camera3D.new()
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.size=23
	camera.position=Vector3(11,11,-19)
	scene.add_child(camera)
	camera.look_at(Vector3(0,.6,0))
	camera.make_current()
	await create_timer(.7).timeout
	await _save("roster.png")
	for i in models.size():
		camera.size=7.2
		camera.position=models[i].position+Vector3(6,3.5,-7)
		camera.look_at(models[i].position+Vector3(0,.6,0))
		await process_frame
		await _save(CARS.IDS[i]+".png")
	print("DESERT_CARS_CAPTURE output=",output)
	scene.free()
	quit(0)

func _save(file: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(file))
