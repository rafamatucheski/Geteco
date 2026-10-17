extends SceneTree
## Inspeção do modelo em escala real; não substitui cena integrada nem benchmark.
const MODEL := preload("res://gameplay/desert_heist/DesertCargoTruckVisual.gd")

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("A captura do caminhão exige renderização real.")
		quit(2)
		return
	var output := ProjectSettings.globalize_path("res://evidence/desert-heist-20261016")
	DirAccess.make_dir_recursive_absolute(output)
	root.size = Vector2i(1600,900)
	var stage := Node3D.new()
	root.add_child(stage)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("a7b4ba")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("b9c4cc")
	environment.environment.ambient_light_energy = .65
	stage.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45,-35,0)
	sun.shadow_enabled = true
	stage.add_child(sun)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(100,100)
	floor_mesh.mesh = plane
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("a48d6a")
	floor_mesh.material_override = material
	stage.add_child(floor_mesh)
	MODEL.prewarm()
	var truck: Node3D = MODEL.create()
	stage.add_child(truck)
	var human: Node3D = preload("res://assets/CivilianModel.gd").new()
	human.position = Vector3(-2.0,0,-2.9)
	stage.add_child(human)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 12.5
	stage.add_child(camera)
	camera.current = true
	var views := [
		["front",Vector3(-11,7,-13),Vector3(0,1.5,-.6),false],
		["rear_closed",Vector3(10,6,13),Vector3(0,1.8,.9),false],
		["rear_open",Vector3(-7,5.5,13),Vector3(0,1.8,1.9),true],
		["cargo_close",Vector3(-3,3.5,12),Vector3(0,2.0,4.0),true]]
	for view in views:
		MODEL.set_cargo_open(truck,view[3],true)
		camera.size = 7.0 if view[0] == "cargo_close" else 12.5
		camera.look_at_from_position(view[1],view[2])
		for frame in 12: await process_frame
		await RenderingServer.frame_post_draw
		var path := "%s/truck_%s.png" % [output,view[0]]
		root.get_texture().get_image().save_png(path)
		print("Captura: ",path)
	quit(0)
