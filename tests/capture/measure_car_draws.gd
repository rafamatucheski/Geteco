extends SceneTree
## Chamadas de desenho e primitivas por quadro para N cópias de um carro, do modelo de fábrica
## (`assets/fleet/<id>.scn` puro) e com os acabamentos do jogo (`FleetCatalog.create`).
## Contagem de renderização na mesma cena e câmera; NÃO é FPS.
## Uso: Godot --path . --script res://tests/capture/measure_car_draws.gd -- --id=aurora_executive --copies=20
func _initialize() -> void: run.call_deferred()

func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("precisa do jogo renderizado"); quit(2); return
	var id := "aurora_executive"
	var copies := 20
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--id="): id = arg.trim_prefix("--id=")
		if arg.begins_with("--copies="): copies = arg.trim_prefix("--copies=").to_int()
	var world := Node3D.new()
	root.add_child(world)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_color = Color("829da6")
	env.environment.background_mode = Environment.BG_COLOR
	world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, -30, 0)
	sun.shadow_enabled = true
	world.add_child(sun)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 60
	camera.far = 400
	world.add_child(camera)
	camera.position = Vector3(0, 25.3, 25.3)
	camera.look_at(Vector3.ZERO)
	camera.make_current()
	var report := {}
	for mode in ["fabrica", "jogo"]:
		var holder := Node3D.new()
		world.add_child(holder)
		for i in copies:
			var car: Node3D = (load("res://assets/fleet/%s.scn" % id) as PackedScene).instantiate() if mode == "fabrica" else preload("res://runtime/FleetCatalog.gd").create(id)
			car.position = Vector3(float(i % 5) * 5.0 - 10.0, 0, float(i / 5) * 9.0 - 14.0)
			holder.add_child(car)
		for i in 6: await process_frame
		report[mode] = {"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), "primitives": Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME), "meshes_por_carro": holder.get_child(0).find_children("*", "MeshInstance3D", true, false).size()}
		holder.queue_free()
		await process_frame
	report["copies"] = copies
	report["id"] = id
	report["resolution"] = str(root.size)
	print("CAR_DRAWS ", JSON.stringify(report))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://evidence/car-review"))
	var file := FileAccess.open("res://evidence/car-review/%s-draws.json" % id, FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	quit()
