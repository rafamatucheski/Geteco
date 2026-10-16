extends SceneTree
## Captura de perto do vaso da calçada, dos sacos de lixo e da jardineira das
## casas, com a versão em cone ao lado (reconstruída aqui) para comparar.
## Saída: evidence/street-greenery/<nome>.png (fora do Git).

const KIT := preload("res://world/city_look/CityPropKit.gd")


func _initialize() -> void:
	var root := Node3D.new()
	get_root().add_child(root)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("8fa6b8")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("b9c4cc")
	environment.ambient_light_energy = 0.6
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	root.add_child(world_environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, -38, 0)
	sun.shadow_enabled = true
	root.add_child(sun)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(20, 20)
	ground.mesh = plane
	var asphalt := StandardMaterial3D.new()
	asphalt.albedo_color = Color("4b4f55")
	ground.material_override = asphalt
	root.add_child(ground)

	_place(root, _old_mesh("planter"), Vector3(-1.6, 0, -1.2))
	_place(root, KIT.mesh("planter"), Vector3(0, 0, -1.2))
	_place(root, _old_mesh("trash_bags"), Vector3(-1.6, 0, .6))
	_place(root, KIT.mesh("trash_bags"), Vector3(0, 0, .6))
	# Jardineira das casas: caixa 1,65 × 0,32 × 0,52 com topo em 0,5 m.
	var box := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = Vector3(1.65, .32, .52)
	box.mesh = box_mesh
	var stone := StandardMaterial3D.new()
	stone.albedo_color = Color("7c7060")
	box.material_override = stone
	box.position = Vector3(2.0, .34, 0)
	root.add_child(box)
	_place(root, KIT.mesh("hedge"), Vector3(2.0, .48, 0))

	var camera := Camera3D.new()
	camera.fov = 40
	root.add_child(camera)
	camera.look_at_from_position(Vector3(.2, 3.4, 4.6), Vector3(.2, .3, -.2))
	for _frame in 8: await process_frame
	var out := ProjectSettings.globalize_path("res://evidence/street-greenery")
	DirAccess.make_dir_recursive_absolute(out)
	get_root().get_texture().get_image().save_png(out.path_join("closeup.png"))
	camera.look_at_from_position(Vector3(.2, 9, 11), Vector3(.2, 0, -.2))
	for _frame in 4: await process_frame
	get_root().get_texture().get_image().save_png(out.path_join("street_distance.png"))
	print("CAPTURA_OK ", out)
	quit(0)


func _place(root: Node3D, mesh: Mesh, at: Vector3) -> void:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = KIT.material()
	instance.position = at
	root.add_child(instance)


## Versão anterior (cones), só para a comparação lado a lado.
func _old_mesh(kind: String) -> ArrayMesh:
	var t := SurfaceTool.new()
	t.begin(Mesh.PRIMITIVE_TRIANGLES)
	t.set_smooth_group(-1)
	if kind == "planter":
		KIT.box(t, Vector3(0, .25, 0), Vector3(1.1, .5, 1.1), Color("9a948a"))
		KIT.box(t, Vector3(0, .52, 0), Vector3(.94, .06, .94), Color("4a3a2a"))
		KIT.cylinder(t, Vector3(0, .5, 0), .42, .5, Color("46703f"), 7, .12)
	else:
		KIT.cylinder(t, Vector3(0, 0, 0), .28, .5, Color("1d1f22"), 7, .12)
		KIT.cylinder(t, Vector3(.42, 0, .12), .24, .42, Color("26292c"), 7, .1)
		KIT.cylinder(t, Vector3(.18, 0, -.34), .22, .38, Color("3f4a2e"), 7, .1)
		KIT.box(t, Vector3(-.4, .16, .2), Vector3(.4, .32, .34), Color("9a7d55"), .4)
	t.generate_normals()
	return t.commit()
