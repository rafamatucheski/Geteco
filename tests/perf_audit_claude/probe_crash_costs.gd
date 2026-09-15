extends SceneTree
## GETECO-PERF-01-CLAUDE — cronometra isoladamente os caminhos de colisão e
## efeitos que apareceram nos picos de gameplay do perf_audit_session.
## Não altera arquivos; muta só o mundo deste processo de diagnóstico.
## Uso: APPDATA isolado + --script res://tests/perf_audit_claude/probe_crash_costs.gd -- run=<nome>

var out := {}

func _initialize() -> void:
	_run.call_deferred()

func _us(callable: Callable) -> float:
	var t0 := Time.get_ticks_usec()
	callable.call()
	return float(Time.get_ticks_usec() - t0)

func _run() -> void:
	if DisplayServer.get_name() == "headless" or not OS.get_user_data_dir().replace("\\", "/").contains("perf_audit_claude"):
		push_error("PROBE requer renderização e user data isolado")
		quit(1)
		return
	var run_name := "probe_crash"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("run="): run_name = arg.trim_prefix("run=")
	var dir := ProjectSettings.globalize_path("res://tests/perf_audit_claude/results/%s" % run_name)
	DirAccess.make_dir_recursive_absolute(dir.path_join("saves"))
	var saves := root.get_node("SaveManager")
	saves.set("_save_dir", dir.path_join("saves") + "/")
	saves.set("_save_directory_ready", false)
	saves.clear_pending_save()
	root.size = Vector2i(1280, 720)
	seed(15092026)
	var campaign := root.get_node("CampaignState")
	campaign.reset_campaign()
	for flag in ["harbor_arrival_seen", "harbor_arrival_call_complete", "harbor_maciota_met", "harbor_delivery_complete"]:
		campaign.set_campaign_flag(StringName(flag), true)
	var world = load("res://world/harbor/HarborGame.tscn").instantiate()
	root.add_child(world)
	current_scene = world
	while not world.gameplay_ready or not world.world_build_ready:
		await process_frame
	for i in 60: await process_frame

	# 1. Deformação de malha em veículos de trânsito reais (CoupeDamageModel.apply_impact).
	var deform: Array = []
	for vehicle in get_nodes_in_group("modern_traffic"):
		if deform.size() >= 6: break
		if not vehicle.get("is_3d_vehicle"): continue
		var build_us := _us(func(): vehicle.ensure_presentation())
		var model = vehicle.get("body_model")
		if not is_instance_valid(model) or not model.has_method("apply_impact"): continue
		var vertices := 0
		var meshes := 0
		for node in model.originals:
			meshes += 1
			vertices += (model.originals[node] as Mesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size()
		var impacts: Array = []
		for k in 3:
			impacts.append(_us(func(): model.apply_impact(Vector3(1.2, 0.81, 0.0), Vector3(-1, 0, 0), 20.0)))
		var full_path_us := _us(func(): vehicle._apply_crash_deformation(Vector2.LEFT, 300.0, vehicle.global_position + Vector2(30, 0)))
		deform.append({"vehicle": String(vehicle.name), "archetype": vehicle.get("active_archetype_id"), "ensure_presentation_us": build_us, "deformed_meshes": meshes, "vertices": vertices, "apply_impact_us": impacts, "apply_crash_deformation_full_us": full_path_us})
	out["traffic_mesh_deformation"] = deform

	# 2. Queda de semáforo (FixedTrafficSignal.receive_vehicle_impact cria render próprio).
	var signals: Array = []
	for node in get_nodes_in_group("fragile_road_post"):
		if signals.size() >= 3: break
		if node.has_method("receive_vehicle_impact") and node.get_script() != null and String(node.get_script().resource_path).ends_with("FixedTrafficSignal.gd"):
			signals.append({"us": _us(func(): node.receive_vehicle_impact(400.0, Vector2.RIGHT))})
	out["fixed_signal_fall"] = signals

	# 3. Efeitos e áudio de batida disparados pelo PlayerCar.
	var car: Node2D = world.get_node("PlayerCar")
	var effects := preload("res://guns/combat/WeaponEffects.gd")
	out["spawn_crash_us"] = [_us(func(): effects.spawn_crash(world, car.global_position, Vector2.LEFT, 300.0)), _us(func(): effects.spawn_crash(world, car.global_position, Vector2.LEFT, 300.0))]
	var target: Node = get_nodes_in_group("modern_traffic")[0]
	out["vehicle_crash_audio_us"] = [_us(func(): preload("res://audio/VehicleCrashAudio.gd").play(car, target, car.global_position, 300.0)), _us(func(): preload("res://audio/VehicleCrashAudio.gd").play(car, target, car.global_position, 300.0))]
	out["player_car_crash_deformation_us"] = _us(func(): car._apply_crash_deformation(Vector2.LEFT, 300.0, car.global_position + Vector2(30, 0)))
	out["engine"] = Engine.get_version_info().string
	out["debug_build"] = OS.is_debug_build()
	var file := FileAccess.open(dir.path_join("probe.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(out, "\t"))
	file.close()
	print("PROBE_CRASH ", JSON.stringify(out))
	quit(0)
