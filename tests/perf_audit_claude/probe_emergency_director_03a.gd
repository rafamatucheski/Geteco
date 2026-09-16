extends SceneTree
## GETECO-PERF-03A — mede HarborEmergencyDirector.configure() em isolamento,
## sobre o mundo real já carregado, para confirmar (ou descartar) a hipótese
## de custo antes de tocar produção. Não altera nada.
## Uso: --script ...probe_emergency_director_03a.gd -- run=<nome>

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	if DisplayServer.get_name() == "headless" or not OS.get_user_data_dir().replace("\\", "/").contains("perf_audit_claude"):
		push_error("PROBE requer renderização e user data isolado")
		quit(1)
		return
	var run_name := "probe_emergency_director"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("run="): run_name = arg.trim_prefix("run=")
	var out := ProjectSettings.globalize_path("res://tests/perf_audit_claude/results/%s" % run_name)
	DirAccess.make_dir_recursive_absolute(out.path_join("saves"))
	var saves := root.get_node("SaveManager")
	saves.set("_save_dir", out.path_join("saves") + "/")
	saves.set("_save_directory_ready", false)
	saves.clear_pending_save()
	root.size = Vector2i(1280, 720)
	var campaign := root.get_node("CampaignState")
	campaign.reset_campaign()
	for flag in ["harbor_arrival_seen", "harbor_arrival_call_complete", "harbor_maciota_met", "harbor_delivery_complete"]:
		campaign.set_campaign_flag(StringName(flag), true)
	var world = load("res://world/harbor/HarborGame.tscn").instantiate()
	root.add_child(world)
	current_scene = world
	var deadline := Time.get_ticks_msec() + 60000
	while (not world.gameplay_ready or not world.world_build_ready) and Time.get_ticks_msec() < deadline:
		await process_frame
	var out_result := {}
	out_result["reached_ready"] = world.gameplay_ready and world.world_build_ready

	# configure() on the ALREADY-loaded HarborEmergencyDirector short-circuits
	# (if not _depots.is_empty(): return) after the FIRST real call already
	# made by the production boot. Measure a FRESH instance's first configure()
	# on the same real world, the same call the real loader made.
	var fresh := preload("res://world/harbor/HarborEmergencyDirector.gd").new()
	var t0 := Time.get_ticks_usec()
	fresh.configure(world)
	out_result["fresh_configure_ms"] = (Time.get_ticks_usec() - t0) / 1000.0
	out_result["fresh_depot_count"] = fresh._depots.size() if "_depots" in fresh else -1
	fresh.free()

	# Também isolar cada trecho de configure() manualmente (cópia read-only,
	# não chamada de produção) para saber ONDE dentro dele o tempo vai.
	var t1 := Time.get_ticks_usec()
	var medical_parking: Node = load("res://world/harbor/HarborMedicalParking.gd").new()
	out_result["medical_parking_new_ms"] = (Time.get_ticks_usec() - t1) / 1000.0
	medical_parking.free()

	var t2 := Time.get_ticks_usec()
	var patrol: Node = load("res://world/harbor/HarborPatrolParking.gd").new()
	out_result["patrol_parking_new_ms"] = (Time.get_ticks_usec() - t2) / 1000.0
	patrol.free()

	var t3 := Time.get_ticks_usec()
	var depot: Node = load("res://emergency/EmergencyDepotMarker.gd").new()
	out_result["depot_marker_new_ms"] = (Time.get_ticks_usec() - t3) / 1000.0
	depot.free()

	print("PROBE_EMERGENCY_DIRECTOR ", JSON.stringify(out_result))
	var file := FileAccess.open(out.path_join("result.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(out_result, "\t"))
	file.close()
	quit(0)
