extends SceneTree
## Caminhão plataforma com o contêiner na posição de PortCargoOperations.
func _initialize() -> void: run.call_deferred()
func run() -> void:
	root.size = Vector2i(900,560)
	var env := WorldEnvironment.new(); env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR; env.environment.background_color = Color(.55,.6,.66)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; env.environment.ambient_light_color = Color(.7,.72,.78)
	root.add_child(env)
	var sun := DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-50,35,0); sun.shadow_enabled = true; root.add_child(sun)
	var ground := MeshInstance3D.new(); var plane := PlaneMesh.new(); plane.size = Vector2(40,40); ground.mesh = plane; root.add_child(ground)
	var truck: Node3D = preload("res://runtime/FleetCatalog.gd").create("cargo_flatbed_truck"); root.add_child(truck)
	var ops := preload("res://gameplay/urban_v1/PortCargoOperations.gd")
	var box := preload("res://world/regions/ShippingContainer3D.gd").create(Color("447f91"))
	var holder := Node3D.new(); holder.position = Vector3(0, ops.TRUCK_BED_TOP, ops.TRUCK_BED_CENTER_Z); holder.rotation.y = PI*.5
	holder.add_child(box); truck.add_child(holder)
	var cam := Camera3D.new(); cam.fov = 40; root.add_child(cam)
	for view in [["a",Vector3(-9,6,-8)],["b",Vector3(9,7,9)],["jogo",Vector3(-6,16,9)]]:
		cam.position = view[1]; cam.look_at(Vector3(0,1.4,.5)); cam.make_current()
		for i in 4: await process_frame
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://evidence/fleet-models/container_%s.png" % view[0]))
	quit(0)
