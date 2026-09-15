extends SceneTree
## GETECO-PERF-02B — validação visual da apresentação de veículos.
## Mesma semente, cor, ângulo e impacto; captura a textura do SubViewport de cada
## veículo limpo e danificado, em duas árvores (antes = worktree sem o patch,
## depois = árvore principal), e compara pixel a pixel.
## Captura:   --script <este arquivo> -- mode=capture out=<pasta absoluta>
## Comparação: --script <este arquivo> -- mode=compare a=<pasta> b=<pasta> out=<pasta>
const TRAFFIC := ["union_sedan", "route_city", "american_tanker_truck", "police_suv"]
const COLOR := Color(0.18, 0.42, 0.78)

func _initialize() -> void:
	_run.call_deferred()

func _arg(name: String, fallback := "") -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with(name + "="): return arg.trim_prefix(name + "=")
	return fallback

func _run() -> void:
	if DisplayServer.get_name() == "headless" or not OS.get_user_data_dir().replace("\\", "/").contains("perf_audit_claude"):
		push_error("CAPTURE requer renderização e user data isolado")
		quit(1)
		return
	if _arg("mode", "capture") == "compare":
		_compare(_arg("a"), _arg("b"), _arg("out"))
		return
	var out := _arg("out")
	DirAccess.make_dir_recursive_absolute(out)
	root.size = Vector2i(1280, 720)
	var budget := root.get_node("PresentationBudget")
	budget.set_process(false)
	var world := Node2D.new()
	root.add_child(world)
	current_scene = world
	var camera := Camera2D.new()
	world.add_child(camera)
	camera.make_current()
	await process_frame
	var factory = load("res://emergency/ModernTrafficFactory.gd")
	var index := 0
	for archetype in TRAFFIC:
		seed(15092026)
		var car = factory.spawn_parked_vehicle(world, "Capture" + str(index), Vector2(index * 400, 0), 0.0, archetype, 0, COLOR)
		index += 1
		budget.pending.erase(car)
		car.ensure_presentation()
		await _save_view(car.body_viewport, out.path_join(archetype + "_clean.png"))
		car.body_model.apply_impact(Vector3(0.9, 0.8, -1.4), Vector3(-1, 0, 0), 14.0)
		car.body_model.apply_impact(Vector3(-0.8, 0.7, -2.0), Vector3(0, 0, 1), 18.0)
		car.body_model.update_lens_damage()
		car.body_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		await _save_view(car.body_viewport, out.path_join(archetype + "_damaged.png"))
		car.body_model.repair()
		car.body_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		await _save_view(car.body_viewport, out.path_join(archetype + "_repaired.png"))
		car.queue_free()
		await process_frame
	seed(15092026)
	var unit = (load("res://emergency/EmergencyVehicle.tscn") as PackedScene).instantiate()
	unit.type = 0
	unit.police_archetype = "police_suv"
	unit.visible = false
	world.add_child(unit)
	unit.ensure_presentation()
	unit.visible = true
	await _save_view(unit.body_viewport, out.path_join("emergency_police_clean.png"))
	var info := FileAccess.open(out.path_join("capture_info.txt"), FileAccess.WRITE)
	info.store_line("engine=%s renderer=%s adapter=%s debug=%s" % [Engine.get_version_info().string, RenderingServer.get_current_rendering_method(), RenderingServer.get_video_adapter_name(), OS.is_debug_build()])
	info.store_line("project=%s" % ProjectSettings.globalize_path("res://"))
	info.close()
	budget.set_process(true)
	print("CAPTURE_02B done ", out)
	quit(0)

func _save_view(view: SubViewport, path: String) -> void:
	view.render_target_update_mode = SubViewport.UPDATE_ONCE
	for i in 3:
		await RenderingServer.frame_post_draw
	view.get_texture().get_image().save_png(path)

func _compare(a_dir: String, b_dir: String, out: String) -> void:
	DirAccess.make_dir_recursive_absolute(out)
	var rows: Array = []
	for file in DirAccess.get_files_at(a_dir):
		if not file.ends_with(".png"): continue
		var a := Image.load_from_file(a_dir.path_join(file))
		var b_path := b_dir.path_join(file)
		if not FileAccess.file_exists(b_path):
			rows.append({"file": file, "error": "ausente em b"})
			continue
		var b := Image.load_from_file(b_path)
		if a.get_size() != b.get_size():
			rows.append({"file": file, "error": "tamanhos diferentes %s x %s" % [a.get_size(), b.get_size()]})
			continue
		a.convert(Image.FORMAT_RGBA8)
		b.convert(Image.FORMAT_RGBA8)
		var differing := 0
		var max_delta := 0.0
		var total := a.get_width() * a.get_height()
		var diff := Image.create(a.get_width(), a.get_height(), false, Image.FORMAT_RGBA8)
		for y in a.get_height():
			for x in a.get_width():
				var ca := a.get_pixel(x, y)
				var cb := b.get_pixel(x, y)
				var delta := maxf(maxf(absf(ca.r - cb.r), absf(ca.g - cb.g)), maxf(absf(ca.b - cb.b), absf(ca.a - cb.a)))
				max_delta = maxf(max_delta, delta)
				if delta > 2.0 / 255.0:
					differing += 1
					diff.set_pixel(x, y, Color(1, 0, 0, 1))
		diff.save_png(out.path_join("diff_" + file))
		rows.append({"file": file, "pixels": total, "differing_over_2_of_255": differing, "differing_ratio": float(differing) / total, "max_channel_delta_0_255": max_delta * 255.0})
	var summary := FileAccess.open(out.path_join("compare.json"), FileAccess.WRITE)
	summary.store_string(JSON.stringify(rows, "\t"))
	summary.close()
	print("COMPARE_02B ", JSON.stringify(rows))
	quit(0)
