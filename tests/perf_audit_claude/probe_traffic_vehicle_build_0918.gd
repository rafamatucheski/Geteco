extends SceneTree
## Microbenchmark isolado: onde vai o tempo de _setup_3d_model() do TrafficVehicle?
## Não altera arquivos de produção. Mede substeps via os mesmos caminhos públicos
## (apply_archetype/ensure_presentation), cronometrando por fora com Time.get_ticks_usec().
## Uso: Godot_console.exe --path . --script res://tests/perf_audit_claude/probe_traffic_vehicle_build_0918.gd

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	var world := Node2D.new()
	root.add_child(world)
	current_scene = world

	var archetypes := ["union_sedan", "summit_suv", "courier_van", "route_city", "bike_urban"]
	print("--- primeira construcao por arquétipo (cache frio para este model_class) ---")
	for id in archetypes:
		_time_one(world, id, "first")
	print("--- segunda construcao do MESMO arquétipo (cache quente, mesma malha) ---")
	for id in archetypes:
		_time_one(world, id, "repeat_a")
		_time_one(world, id, "repeat_b")
	print("--- SubViewport isolado (sem modelo nenhum, só o custo do viewport+own_world_3d) ---")
	for i in 5:
		var t0 := Time.get_ticks_usec()
		var vp := SubViewport.new()
		vp.size = Vector2i(192, 192)
		vp.transparent_bg = true
		vp.own_world_3d = true
		vp.render_target_update_mode = SubViewport.UPDATE_ONCE
		world.add_child(vp)
		var t1 := Time.get_ticks_usec()
		var cam := Camera3D.new()
		vp.add_child(cam)
		var env := WorldEnvironment.new()
		env.environment = Environment.new()
		vp.add_child(env)
		var sun := DirectionalLight3D.new()
		vp.add_child(sun)
		var t2 := Time.get_ticks_usec()
		print("  viewport_alone iter=%d subviewport_new_us=%d cam_env_light_us=%d" % [i, t1 - t0, t2 - t1])
		vp.queue_free()
	quit(0)

func _time_one(world: Node2D, archetype_id: String, label: String) -> void:
	var spec := VehicleCatalog.get_vehicle_spec(archetype_id)
	var vehicle = (load("res://cars/traffic/TrafficVehicle.tscn") as PackedScene).instantiate()
	vehicle.defer_presentation = false # medir _setup_3d_model direto, sem passar pela fila
	vehicle.crop = VehicleCatalog.VEHICLE_CROPS[0]
	vehicle.target_length = float(spec.get("target_length", 76.0))
	world.add_child(vehicle)
	var t0 := Time.get_ticks_usec()
	vehicle.apply_archetype(archetype_id, Color.WHITE)
	var total_us := Time.get_ticks_usec() - t0
	print("  %s archetype=%s total_us=%d total_ms=%.2f" % [label, archetype_id, total_us, total_us / 1000.0])
	if label == "first":
		vehicle.queue_free()
	else:
		vehicle.queue_free()
