extends SceneTree

const PINE := preload("res://world/mountain_pass/MountainPine3D.gd")
const FRAME_BUDGET_USEC := 16667
const MAX_PRESENT_FRAMES := 180

var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, label: String) -> void:
	print("PASS " if condition else "FAIL ", label)
	if not condition:
		failures.append(label)

func _has_arg(value: String) -> bool:
	return value in OS.get_cmdline_user_args()

func _arg_value(prefix: String) -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with(prefix):
			return arg.trim_prefix(prefix)
	return ""

func _spawn(parent: Node2D, seed: int, snowy: bool, position: Vector2) -> Dictionary:
	var pine := PINE.new()
	pine.variant_seed = seed
	pine.is_snowy = snowy
	pine.tree_scale = 1.0
	pine.position = position
	var started := Time.get_ticks_usec()
	parent.add_child(pine)
	return {"pine": pine, "add_usec": Time.get_ticks_usec() - started}

func _atlas(key: String) -> SubViewport:
	for child in root.get_children():
		if child is SubViewport and String(child.get_meta("pine_atlas_key", "")) == key:
			return child as SubViewport
	return null

func _sample_until_ready(key: String, max_frames: int) -> Dictionary:
	var peak_usec := 0
	var intervals: Array[int] = []
	var previous := Time.get_ticks_usec()
	var view: SubViewport = null
	for index in max_frames:
		await process_frame
		var now := Time.get_ticks_usec()
		var interval := now - previous
		previous = now
		intervals.append(interval)
		peak_usec = maxi(peak_usec, interval)
		view = _atlas(key)
		if view != null and bool(view.get_meta("pine_atlas_ready", false)):
			break
	return {
		"peak_usec": peak_usec,
		"intervals": intervals,
		"frames": intervals.size(),
		"ready": view != null and bool(view.get_meta("pine_atlas_ready", false)),
		"stage_peak_usec": int(view.get_meta("pine_atlas_peak_stage_usec", 0)) if view != null else 0,
		"stage_samples": view.get_meta("pine_atlas_stage_samples", []) if view != null else [],
	}

func _sample_frames(count: int) -> Dictionary:
	var peak_usec := 0
	var intervals: Array[int] = []
	var previous := Time.get_ticks_usec()
	for index in count:
		await process_frame
		var now := Time.get_ticks_usec()
		var interval := now - previous
		previous = now
		intervals.append(interval)
		peak_usec = maxi(peak_usec, interval)
	return {"peak_usec": peak_usec, "intervals": intervals}

func _run() -> void:
	create_timer(30.0).timeout.connect(func(): quit(2))
	Engine.max_fps = 0
	root.size = Vector2i(1280, 720)
	root.content_scale_size = root.size
	var world := Node2D.new()
	world.name = "MountainPineFirstPresentBudget"
	root.add_child(world)
	current_scene = world
	var camera := Camera2D.new()
	camera.position = Vector2(320, 280)
	world.add_child(camera)
	camera.make_current()
	for warmup in 4:
		await process_frame

	var cold := _spawn(world, 8, false, Vector2(260, 360))
	var first_requester := cold.pine as Node
	first_requester.queue_free()
	var replacement := _spawn(world, 8, false, Vector2(260, 360))
	var replacement_pine := replacement.pine as Node
	_check(not bool(replacement_pine.get("_atlas_ready")), "segundo solicitante começa no fallback enquanto atlas está frio")
	_check((replacement_pine.get("_bough_polys") as Array).size() > 0, "fallback procedural possui copa visível")
	_check(replacement_pine.get_node_or_null("TrunkCol") != null, "fallback mantém collider desde o primeiro frame")
	var fallback_capture_path := _arg_value("fallback_capture=")
	if not fallback_capture_path.is_empty() and DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute(fallback_capture_path.get_base_dir())
		var fallback_capture_error := root.get_texture().get_image().save_png(fallback_capture_path)
		_check(fallback_capture_error == OK, "captura visual do fallback é gravada")
	var cold_frames: Dictionary = await _sample_until_ready("0_0", MAX_PRESENT_FRAMES)
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
	var cold_pine := replacement_pine
	var cold_sprite := cold_pine.get("presentation") as Sprite2D
	var cold_image := cold_sprite.texture.get_image() if cold_sprite != null and cold_sprite.texture != null and DisplayServer.get_name() != "headless" else null
	var cold_present := cold_sprite != null and cold_sprite.texture != null and bool(cold_frames.ready)
	if DisplayServer.get_name() != "headless":
		cold_present = cold_present and cold_image != null and not cold_image.is_empty()

	var hot := _spawn(world, 16, false, Vector2(420, 360))
	var hot_frames: Dictionary = await _sample_frames(4)
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
	var hot_pine := hot.pine as Node
	var hot_sprite := hot_pine.get("presentation") as Sprite2D

	_check(cold_present, "árvore fria recebe apresentação")
	_check(not is_instance_valid(first_requester), "primeiro solicitante é evicto durante a construção")
	_check(bool(cold_pine.get("_atlas_ready")), "segundo solicitante recebe atlas após evicção do primeiro")
	var worker := root.get_node_or_null("MountainPineAtlasWorker")
	_check(worker != null and worker.get_parent() == root, "worker do atlas permanece hospedado na raiz")
	_check(hot_sprite != null and hot_sprite.texture == cold_sprite.texture, "árvore quente reutiliza o atlas da variante")
	_check(cold_pine.get_meta("forest_species", "") == "pine", "variante mantém espécie")
	var collision := cold_pine.get_node_or_null("TrunkCol") as CollisionShape2D
	_check(collision != null and collision.shape is CircleShape2D and is_equal_approx((collision.shape as CircleShape2D).radius, 32.0), "footprint de colisão permanece íntegro")

	var species := {}
	var clearances := [32.0, 24.0, 22.0, 10.0, 12.0, 7.0, 18.0, 25.0]
	var contract_trees: Array[Node] = []
	for snowy_index in 2:
		for variant in 8:
			var entry := _spawn(world, 8 + variant, snowy_index == 1, Vector2(80 + variant * 70, 500 + snowy_index * 100))
			var pine := entry.pine as Node
			contract_trees.append(pine)
			species[String(pine.get_meta("forest_species", ""))] = true
			var variant_collision := pine.get_node_or_null("TrunkCol") as CollisionShape2D
			_check(variant_collision != null and variant_collision.shape is CircleShape2D and is_equal_approx((variant_collision.shape as CircleShape2D).radius, clearances[variant]), "footprint preservado: variante %d" % variant)
	_check(species.size() == 8, "oito variantes visuais/espécies permanecem disponíveis")
	var all_atlases_ready := false
	for wait_frame in 500:
		await process_frame
		all_atlases_ready = true
		for snowy_index in 2:
			for variant in 8:
				var view := _atlas("%d_%d" % [snowy_index, variant])
				if view == null or not bool(view.get_meta("pine_atlas_ready", false)):
					all_atlases_ready = false
					break
			if not all_atlases_ready:
				break
		if all_atlases_ready:
			break
	_check(all_atlases_ready, "atlas seco e nevado conclui para as oito variantes")
	var capture_path := _arg_value("capture=")
	if not capture_path.is_empty() and DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute(capture_path.get_base_dir())
		var capture_error := root.get_texture().get_image().save_png(capture_path)
		_check(capture_error == OK, "captura visual das variantes é gravada")
	var vehicle := CharacterBody2D.new()
	world.add_child(vehicle)
	var snowy_pine := contract_trees[8]
	snowy_pine.receive_vehicle_contact(40.0, Vector2.RIGHT, vehicle)
	_check(int(snowy_pine.get("_last_ice_impact")) > 0, "árvore nevada preserva interação de gelo com veículo")
	_check(not get_nodes_in_group("tree_ice_burst").is_empty(), "contato cria queda de gelo limitada")

	var rendered := DisplayServer.get_name() != "headless"
	if rendered and not _has_arg("--baseline-only"):
		_check(int(cold.add_usec) < FRAME_BUDGET_USEC, "construção fria cabe em 16,67 ms")
		_check(int(cold_frames.peak_usec) < FRAME_BUDGET_USEC, "primeira apresentação cabe em 16,67 ms")
		_check(int(hot.add_usec) < FRAME_BUDGET_USEC, "construção quente cabe em 16,67 ms")

	var report := {
		"renderer": DisplayServer.get_name(),
		"cold_add_usec": cold.add_usec,
		"replacement_add_usec": replacement.add_usec,
		"cold_first_present_peak_usec": cold_frames.peak_usec,
		"cold_present_frames": cold_frames.frames,
		"cold_stage_peak_usec": cold_frames.stage_peak_usec,
		"cold_stage_samples": cold_frames.stage_samples,
		"cold_intervals_usec": cold_frames.intervals,
		"hot_add_usec": hot.add_usec,
		"hot_peak_usec": hot_frames.peak_usec,
		"hot_intervals_usec": hot_frames.intervals,
		"cold_present": cold_present,
	}
	print("MOUNTAIN_PINE_FIRST_PRESENT ", JSON.stringify(report))
	print("MOUNTAIN_PINE_FIRST_PRESENT failures=", failures)
	world.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
