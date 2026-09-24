extends SceneTree

const BUILDER := preload("res://world/mountain_pass/MountainSceneryBuilder.gd")
const STREAMER := preload("res://world/mountain_pass/MountainForestStreamer.gd")
const PINE := preload("res://world/mountain_pass/MountainPine3D.gd")
const MAX_FRAMES := 700
const MAX_TREES_PER_FRAME := 2
const SIXTY_FPS_BUDGET_USEC := 16667
const STANDALONE_BASELINE_ITEMS := 546
const STANDALONE_BASELINE_TREES := 519
const STREAMED_EXPECTED_ITEMS := 547
const STREAMED_EXPECTED_TREES := 522
const STREAMED_EXPECTED_VARIANTS := {0: 68, 1: 67, 2: 67, 3: 67, 4: 52, 5: 62, 6: 66, 7: 73}

var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, message: String) -> void:
	print("PASS " if condition else "FAIL ", message)
	if not condition:
		failures.append(message)

func _start_build(parent: Node2D, road: MountainPassRoad) -> void:
	BUILDER.build_dense_pine_forest(parent, road, true)

func _has_arg(value: String) -> bool:
	return value in OS.get_cmdline_user_args()

func _tree_count(forest: Node2D) -> int:
	var count := 0
	for child in forest.get_children():
		if child.get_script() == PINE:
			count += 1
	return count

func _layout_signature(forest: Node2D) -> Dictionary:
	var variants := {}
	var snowy := 0
	var dry := 0
	var grove := 0
	var rocks := 0
	var collision_trees := 0
	for child in forest.get_children():
		if child.get_script() == PINE:
			var variant := posmod(int(child.variant_seed), 8)
			variants[variant] = int(variants.get(variant, 0)) + 1
			if child.is_snowy:
				snowy += 1
			else:
				dry += 1
			if child.has_meta("mountain_grove"):
				grove += 1
			var collision := child.get_node_or_null("TrunkCol") as CollisionShape2D
			if collision != null and collision.shape != null:
				collision_trees += 1
		elif child.has_meta("mountain_grove"):
			rocks += 1
	return {
		"variants": variants,
		"snowy": snowy,
		"dry": dry,
		"grove": grove,
		"rocks": rocks,
		"collision_trees": collision_trees,
	}

func _areas_are_clear(forest: Node2D, road: MountainPassRoad) -> bool:
	var lake_bounds := Rect2(6680, -320, 800, 700)
	var secret_lake_bounds := Rect2(5080, -1500, 740, 680)
	var bunker_bounds := Rect2(6340, -2920, 320, 260)
	var ammu_bounds := Rect2(7560, -320, 380, 260)
	for child in forest.get_children():
		if not child is Node2D:
			continue
		var pos := (child as Node2D).position
		if road.is_point_on_road(pos, 130.0): return false
		if BUILDER._is_point_on_dirt_road(pos, 42.0): return false
		if lake_bounds.has_point(pos) or secret_lake_bounds.has_point(pos): return false
		if bunker_bounds.has_point(pos) or ammu_bounds.has_point(pos): return false
	return true

func _run() -> void:
	create_timer(45.0).timeout.connect(func(): quit(2))
	# Wall intervals only represent work when the project's 60 FPS limiter is
	# disabled. This remains a structural headless test, not FPS certification.
	Engine.max_fps = 0
	var world := Node2D.new()
	world.name = "DensePineStreamCadenceWorld"
	root.add_child(world)
	current_scene = world
	var scenery := Node2D.new()
	world.add_child(scenery)
	var focus_probe := Node2D.new()
	focus_probe.name = "PlayerProbe"
	focus_probe.position = BUILDER.FOREST_STREAM_ENTRY
	focus_probe.add_to_group("player")
	world.add_child(focus_probe)
	var road := MountainPassRoad.new()
	road._build_curve()
	BUILDER._init_dirt_roads()
	if _has_arg("baseline-only"):
		seed(9137)
		var baseline_started := Time.get_ticks_usec()
		await BUILDER.build_dense_pine_forest(scenery, road, false)
		var baseline_forest := scenery.get_node("DensePineForest") as Node2D
		var baseline_signature := _layout_signature(baseline_forest)
		print("DENSE_PINE_STANDALONE_BASELINE usec=", Time.get_ticks_usec() - baseline_started,
			" items=", baseline_forest.get_child_count(), " signature=", baseline_signature)
		world.queue_free()
		await process_frame
		quit(0)
		return

	for warmup_frame in 3:
		await process_frame
	_start_build.call_deferred(scenery, road)
	var frame_count := 0
	var previous_tree_count := 0
	var observed_peak_trees := 0
	var peak_interval_usec := 0
	var slow_frames: Array[Dictionary] = []
	var previous_tick := Time.get_ticks_usec()
	var forest: Node2D = null
	while frame_count < MAX_FRAMES:
		await process_frame
		var now := Time.get_ticks_usec()
		var interval_usec := now - previous_tick
		peak_interval_usec = maxi(peak_interval_usec, interval_usec)
		previous_tick = now
		forest = scenery.get_node_or_null("DensePineForest") as Node2D
		if forest != null:
			var current_tree_count := _tree_count(forest)
			observed_peak_trees = maxi(observed_peak_trees, current_tree_count - previous_tree_count)
			if interval_usec >= SIXTY_FPS_BUDGET_USEC:
				slow_frames.append({"frame": frame_count, "usec": interval_usec, "trees_added": current_tree_count - previous_tree_count, "trees": current_tree_count})
			previous_tree_count = current_tree_count
			if forest.get_meta("streamed_build_complete", false):
				break
		frame_count += 1

	_check(forest != null, "floresta streamed é criada")
	if forest == null:
		quit(1)
		return
	# Compatibilidade: o contrato novo conclui a configuração do streamer, não
	# a materialização integral do mapa. A cobertura completa de aproximação,
	# evicção e reentrada vive no teste de proximidade específico.
	if forest.get_script() == STREAMER:
		var plan: Array[Dictionary] = forest.get_plan_snapshot()
		var wait_frames := 0
		while not bool(forest.get_meta("stream_corridor_ready", false)) and wait_frames < MAX_FRAMES:
			await process_frame
			wait_frames += 1
		_check(plan.size() == STREAMED_EXPECTED_ITEMS, "plano determinístico permanece estável")
		_check(forest.get_resident_count() > 0 and forest.get_resident_count() < plan.size(), "somente a janela próxima fica residente")
		_check(int(forest.get_meta("stream_peak_instances_per_frame", 99)) <= BUILDER.FOREST_STREAM_MAX_INSTANCES, "materialização respeita o limite por frame")
		_check(int(forest.get_meta("stream_planning_peak_usec", SIXTY_FPS_BUDGET_USEC)) < SIXTY_FPS_BUDGET_USEC, "planejamento fica abaixo de 16,67 ms em headless")
		_check(int(forest.get_meta("stream_build_peak_usec", SIXTY_FPS_BUDGET_USEC)) < SIXTY_FPS_BUDGET_USEC, "janela inicial fica abaixo de 16,67 ms em headless")
		print("DENSE_PINE_STREAM_CADENCE proximity=true plan=", plan.size(),
			" resident=", forest.get_resident_count(),
			" peak_resident=", forest.get_meta("stream_peak_resident", -1),
			" planning_peak_usec=", forest.get_meta("stream_planning_peak_usec", -1),
			" build_peak_usec=", forest.get_meta("stream_build_peak_usec", -1),
			" failures=", failures)
		world.queue_free()
		for _frame in 3:
			await process_frame
		quit(0 if failures.is_empty() else 1)
		return
	var plan_count := int(forest.get_meta("stream_plan_count", -1))
	var signature := _layout_signature(forest)
	var tree_count := int(signature.snowy) + int(signature.dry)
	_check(forest.get_meta("streamed_build_complete", false), "construção streamed conclui")
	_check(frame_count > 100 and frame_count < MAX_FRAMES, "construção é distribuída em muitos frames com limite finito")
	_check(forest.get_child_count() == plan_count, "todo item planejado é materializado antes de concluir")
	_check(plan_count >= STANDALONE_BASELINE_ITEMS, "contagem final não cai abaixo do baseline standalone")
	_check(tree_count >= STANDALONE_BASELINE_TREES, "contagem final de pinheiros não cai abaixo do baseline standalone")
	_check(plan_count == STREAMED_EXPECTED_ITEMS and tree_count == STREAMED_EXPECTED_TREES, "contagem determinística do layout streamed permanece estável")
	_check(signature.variants == STREAMED_EXPECTED_VARIANTS and int(signature.snowy) == 157 and int(signature.dry) == 365 and int(signature.grove) == 85 and int(signature.rocks) == 25, "assinatura determinística de variantes, neve e bosques permanece estável")
	_check(int(signature.variants.size()) == 8, "as oito variantes permanecem presentes")
	_check(int(signature.snowy) > 0 and int(signature.dry) > 0, "árvores secas e nevadas permanecem presentes")
	_check(int(signature.grove) > 0 and int(signature.rocks) > 0, "bosques mistos e rochas permanecem presentes")
	_check(int(signature.collision_trees) == tree_count, "todo pinheiro mantém footprint de colisão")
	_check(_areas_are_clear(forest, road), "estradas e áreas reservadas permanecem livres")
	_check(observed_peak_trees <= MAX_TREES_PER_FRAME, "observação externa confirma o máximo de árvores por frame")
	_check(int(forest.get_meta("stream_peak_trees_per_frame", 99)) <= MAX_TREES_PER_FRAME, "telemetria confirma o máximo de árvores por frame")
	_check(int(forest.get_meta("stream_peak_instances_per_frame", 99)) <= BUILDER.FOREST_STREAM_MAX_INSTANCES, "árvores e rochas respeitam o limite por frame")
	_check(int(forest.get_meta("stream_planning_frames", 0)) > 1, "planejamento também é fatiado")
	_check(int(forest.get_meta("stream_build_frames", 0)) > 1, "instanciação também é fatiada")
	var runtime_label := "headless" if DisplayServer.get_name() == "headless" else "renderizado"
	_check(int(forest.get_meta("stream_planning_peak_usec", SIXTY_FPS_BUDGET_USEC)) < SIXTY_FPS_BUDGET_USEC, "pico de planejamento %s fica abaixo de 16,67 ms" % runtime_label)
	_check(int(forest.get_meta("stream_build_peak_usec", SIXTY_FPS_BUDGET_USEC)) < SIXTY_FPS_BUDGET_USEC, "pico de instanciação %s fica abaixo de 16,67 ms" % runtime_label)
	_check(peak_interval_usec < SIXTY_FPS_BUDGET_USEC, "pico estrutural %s permanece abaixo de 16,67 ms" % runtime_label)
	var first_count := mini(24, forest.get_child_count())
	var first_distance := 0.0
	var last_distance := 0.0
	for index in first_count:
		first_distance += (forest.get_child(index) as Node2D).position.distance_to(BUILDER.FOREST_STREAM_ENTRY)
		last_distance += (forest.get_child(forest.get_child_count() - 1 - index) as Node2D).position.distance_to(BUILDER.FOREST_STREAM_ENTRY)
	_check(first_count > 0 and first_distance < last_distance, "faixa próxima da entrada recebe sólidos antes das células distantes")

	print("DENSE_PINE_STREAM_CADENCE frames=", frame_count,
		" plan=", plan_count,
		" trees=", tree_count,
		" peak_trees=", observed_peak_trees,
		" peak_interval_usec=", peak_interval_usec,
		" planning_peak_usec=", forest.get_meta("stream_planning_peak_usec", -1),
		" build_peak_usec=", forest.get_meta("stream_build_peak_usec", -1),
		" slow_frames=", slow_frames,
		" signature=", signature,
		" failures=", failures)
	world.queue_free()
	for frame in 3:
		await process_frame
	quit(0 if failures.is_empty() else 1)
