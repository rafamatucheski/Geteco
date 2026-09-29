extends SceneTree
## Compara um carro de IA preparado (assets/fleet/incoming/mirage_test.scn) com modelos da
## frota na câmera de jogo, e conta peças, triângulos e chamadas de desenho por quadro.
## Só revisão visual + contagem de renderização; NÃO é benchmark de FPS.
## Uso: Godot --path . --script res://tests/capture/capture_mirage_compare.gd -- --no-save
const MIRAGE := "res://assets/fleet/incoming/mirage_test.scn"
const OTHERS := ["sport_coupe", "metro_hatch", "aurora_executive"]
var camera: Camera3D
var root3d: Node3D

func _initialize() -> void: run.call_deferred()

func shot(name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://evidence/mirage-test/%s.png" % name)
	print("MIRAGE_CAPTURE ", name)

func frame(focus: Vector3, size: float, offset := Vector3(0, 25.3, 25.3)) -> void:
	camera.size = size
	camera.global_position = focus + offset
	camera.look_at(focus)
	camera.make_current()
	for i in 6: await process_frame

func stats(model: Node3D) -> Dictionary:
	var parts := 0
	var tris := 0
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = node.mesh
		if mesh == null: continue
		parts += mesh.get_surface_count()
		for s in mesh.get_surface_count():
			var arrays := mesh.surface_get_arrays(s)
			var idx: Variant = arrays[Mesh.ARRAY_INDEX]
			tris += (idx.size() if idx != null and idx.size() > 0 else (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3
	return {"parts": parts, "tris": tris}

func make(id: String, paint := Color.WHITE) -> Node3D:
	var model: Node3D
	if id == "mirage":
		model = (load(MIRAGE) as PackedScene).instantiate()
		for part in model.get_children():
			var m := (part as MeshInstance3D).mesh.surface_get_material(0)
			if m is StandardMaterial3D and m.resource_name == "paint":
				var copy := m.duplicate() as StandardMaterial3D
				copy.albedo_color = paint
				(part as MeshInstance3D).material_override = copy
	else:
		model = preload("res://runtime/FleetCatalog.gd").create(id)
	return model

func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("precisa do jogo renderizado"); quit(2); return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://evidence/mirage-test"))
	root3d = Node3D.new()
	root.add_child(root3d)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("6f8a99")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color("b6c9df")
	env.environment.ambient_light_energy = .6
	root3d.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -35, 0)
	sun.light_energy = 1.3
	sun.shadow_enabled = true
	root3d.add_child(sun)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(400, 400)
	ground.mesh = plane
	var ground_material := StandardMaterial3D.new()
	ground_material.albedo_color = Color("5b5f5f")
	ground_material.roughness = 1
	ground.material_override = ground_material
	root3d.add_child(ground)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.far = 500
	root3d.add_child(camera)

	var lineup := [["sport_coupe", Color.WHITE], ["metro_hatch", Color.WHITE], ["aurora_executive", Color.WHITE], ["mirage", Color.WHITE], ["mirage", Color("c8412f")], ["mirage", Color("e0b53a")], ["mirage", Color("2f6fb5")]]
	var report := {}
	var x := -9.0
	var holder := Node3D.new()
	root3d.add_child(holder)
	for entry in lineup:
		var model := make(entry[0], entry[1])
		if model == null: continue
		model.position = Vector3(x, 0, 0)
		holder.add_child(model)
		var key := "%s%s" % [entry[0], "" if entry[1] == Color.WHITE else "_" + entry[1].to_html(false)]
		report[key] = stats(model)
		x += 3.6 if entry[0] == "mirage" else 4.2
	print("MIRAGE_STATS ", JSON.stringify(report))
	await frame(Vector3(0, 0.5, 0), 34)
	await shot("gameplay-size-34")
	await frame(Vector3(0, 0.5, 0), 22)
	await shot("gameplay-size-22")
	await frame(Vector3(-2.2, 0.6, 0), 9, Vector3(0, 8, 9))
	await shot("close-old-cars")
	await frame(Vector3(9.4, 0.6, 0), 12, Vector3(0, 10, 11))
	await shot("close-mirage-paints")
	await frame(Vector3(4.2, .6, 0), 4.8, Vector3(-6, 3.4, 5.5))
	await shot("close-mirage-3q")
	await frame(Vector3(4.2, .6, 0), 4.8, Vector3(5.5, 3.2, -6.5))
	await shot("close-mirage-front-3q")
	# Chamadas de desenho por quadro: 20 cópias de cada modelo na mesma área.
	var counts := {}
	for id in ["sport_coupe", "metro_hatch", "aurora_executive", "mirage"]:
		holder.queue_free()
		await process_frame
		holder = Node3D.new()
		root3d.add_child(holder)
		for i in 20:
			var car := make(id)
			car.position = Vector3(float(i % 5) * 5.0 - 10.0, 0, float(i / 5) * 9.0 - 14.0)
			holder.add_child(car)
		await frame(Vector3(0, 0, 0), 60)
		for i in 4: await process_frame
		counts[id] = {"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), "primitives": Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)}
	print("MIRAGE_DRAWS_20_CARS ", JSON.stringify(counts))
	var file := FileAccess.open("res://evidence/mirage-test/stats.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"models": report, "draws_20_cars": counts, "resolution": str(root.size), "gpu": RenderingServer.get_video_adapter_name()}, "\t"))
	file.close()
	print("MIRAGE_COMPLETE")
	quit()
