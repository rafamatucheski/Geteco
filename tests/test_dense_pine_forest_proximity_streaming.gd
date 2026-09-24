extends SceneTree

const BUILDER := preload("res://world/mountain_pass/MountainSceneryBuilder.gd")
const STREAMER := preload("res://world/mountain_pass/MountainForestStreamer.gd")
const PINE := preload("res://world/mountain_pass/MountainPine3D.gd")
const SIXTY_FPS_BUDGET_USEC := 16667
const EXPECTED_ITEMS := 547
const EXPECTED_TREES := 522
const EXPECTED_VARIANTS := {0: 68, 1: 67, 2: 67, 3: 67, 4: 52, 5: 62, 6: 66, 7: 73}
const MAX_WAIT_FRAMES := 700
const MOVE_STEP := 22.0

class FocusProbe extends Node2D:
	var velocity := Vector2.ZERO
	var is_driven_by_player := false

var failures: Array[String] = []
var peak_interval_usec := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, message: String) -> void:
	print("PASS " if condition else "FAIL ", message)
	if not condition:
		failures.append(message)

func _plan_signature(plan: Array[Dictionary]) -> Dictionary:
	var variants := {}
	var snowy := 0
	var dry := 0
	var grove := 0
	var rocks := 0
	for item in plan:
		var pos: Vector2 = item["position"]
		var seed_value := int(pos.x * 43 + pos.y * 71)
		if bool(item["rock"]):
			rocks += 1
			continue
		var variant := posmod(seed_value, 8)
		variants[variant] = int(variants.get(variant, 0)) + 1
		var is_snowy := (bool(item["snow_region"]) and posmod(seed_value, 7) != 0) or (not bool(item["snow_region"]) and pos.y < -650.0 and posmod(seed_value, 5) == 0)
		if is_snowy:
			snowy += 1
		else:
			dry += 1
		if bool(item["grove"]):
			grove += 1
	return {"variants": variants, "snowy": snowy, "dry": dry, "grove": grove, "rocks": rocks}

func _instance_signature(node: Node2D) -> String:
	if node.get_script() == PINE:
		return "pine:%d:%.4f:%s:%s" % [int(node.variant_seed), float(node.tree_scale), str(bool(node.is_snowy)), str(node.has_meta("mountain_grove"))]
	return "rock:%d:%s:%s" % [int(node.variant_seed), str(node.rock_size), str(node.base_color)]

func _resident_instances(forest: Node2D) -> Array[Node2D]:
	var instances: Array[Node2D] = []
	for cell in forest.get_children():
		if not cell is Node2D or not cell.has_meta("forest_cell"):
			continue
		for child in cell.get_children():
			if child is Node2D and child.has_meta("forest_plan_index"):
				instances.append(child)
	return instances

func _resident_signature_by_id(forest: Node2D) -> Dictionary:
	var signature := {}
	for child in _resident_instances(forest):
		var index := int(child.get_meta("forest_plan_index"))
		signature[index] = _instance_signature(child)
	return signature

func _resident_collisions_are_valid(forest: Node2D) -> bool:
	for child in _resident_instances(forest):
		if child.get_script() != PINE:
			continue
		var collision := child.get_node_or_null("TrunkCol") as CollisionShape2D
		if collision == null or collision.shape == null:
			return false
	return true

func _max_resident_distance(forest: Node2D, focus_position: Vector2) -> float:
	var maximum := 0.0
	for child in _resident_instances(forest):
		maximum = maxf(maximum, child.position.distance_to(focus_position))
	return maximum

func _plan_areas_are_clear(plan: Array[Dictionary], road: MountainPassRoad) -> bool:
	var lake_bounds := Rect2(6680, -320, 800, 700)
	var secret_lake_bounds := Rect2(5080, -1500, 740, 680)
	var bunker_bounds := Rect2(6340, -2920, 320, 260)
	var ammu_bounds := Rect2(7560, -320, 380, 260)
	for item in plan:
		var pos: Vector2 = item["position"]
		if road.is_point_on_road(pos, 130.0): return false
		if BUILDER._is_point_on_dirt_road(pos, 42.0): return false
		if lake_bounds.has_point(pos) or secret_lake_bounds.has_point(pos): return false
		if bunker_bounds.has_point(pos) or ammu_bounds.has_point(pos): return false
	return true

func _sample_frame(previous_tick: int) -> int:
	var now := Time.get_ticks_usec()
	peak_interval_usec = maxi(peak_interval_usec, now - previous_tick)
	return now

func _wait_for_corridor(forest: Node2D, max_frames := MAX_WAIT_FRAMES) -> bool:
	var previous_tick := Time.get_ticks_usec()
	for _frame in max_frames:
		await process_frame
		previous_tick = _sample_frame(previous_tick)
		if bool(forest.get_meta("stream_corridor_ready", false)):
			return true
	return false

func _move_gradually(actor: FocusProbe, target: Vector2) -> void:
	var previous_tick := Time.get_ticks_usec()
	while actor.position.distance_to(target) > 0.01:
		var remaining := target - actor.position
		var direction := remaining.normalized()
		actor.velocity = direction * 520.0
		actor.position += direction * minf(MOVE_STEP, remaining.length())
		await process_frame
		previous_tick = _sample_frame(previous_tick)
	actor.velocity = Vector2.ZERO

func _run() -> void:
	create_timer(55.0).timeout.connect(func(): quit(2))
	# Headless valida ciclo de vida e cadência; não certifica FPS renderizado.
	Engine.max_fps = 0
	var world := Node2D.new()
	root.add_child(world)
	current_scene = world
	var scenery := Node2D.new()
	world.add_child(scenery)
	var road := MountainPassRoad.new()
	road._build_curve()
	BUILDER._init_dirt_roads()
	var player := FocusProbe.new()
	player.position = BUILDER.FOREST_STREAM_ENTRY
	player.add_to_group("player")
	world.add_child(player)

	var planning_started := Time.get_ticks_usec()
	BUILDER.build_dense_pine_forest(scenery, road, true)
	var initial_return_usec := Time.get_ticks_usec() - planning_started
	var forest := scenery.get_node_or_null("DensePineForest") as Node2D
	_check(forest != null, "streamer da floresta é criado")
	if forest == null:
		quit(1)
		return
	_check(forest.get_script() == STREAMER, "caminho streamed usa runtime de células")
	_check(int(forest.get_meta("stream_resident_count", -1)) == 0 and forest.get_child_count() == 0, "build inicial retorna sem nós ou colisões distantes")
	_check(initial_return_usec < SIXTY_FPS_BUDGET_USEC, "build inicial devolve controle antes de 16,67 ms em headless")
	var planning_wait_frames := 0
	while not bool(forest.get_meta("streamed_build_complete", false)) and planning_wait_frames < MAX_WAIT_FRAMES:
		await process_frame
		planning_wait_frames += 1
	_check(bool(forest.get_meta("streamed_build_complete", false)), "plano completo termina em segundo plano com prazo finito")

	var plan: Array[Dictionary] = forest.get_plan_snapshot()
	var signature := _plan_signature(plan)
	var tree_count := int(signature.snowy) + int(signature.dry)
	_check(plan.size() == EXPECTED_ITEMS and tree_count == EXPECTED_TREES, "layout determinístico mantém 547 itens e 522 pinheiros")
	_check(signature.variants == EXPECTED_VARIANTS, "as oito variantes mantêm a distribuição determinística")
	_check(int(signature.snowy) == 157 and int(signature.dry) == 365 and int(signature.grove) == 85 and int(signature.rocks) == 25, "neve, árvores secas, bosques e rochas permanecem estáveis")
	_check(_plan_areas_are_clear(plan, road), "estradas e áreas reservadas permanecem livres")
	_check(int(forest.get_meta("stream_planning_frames", 0)) > 1, "planejamento continua fatiado")
	_check(int(forest.get_meta("stream_planning_peak_usec", SIXTY_FPS_BUDGET_USEC)) < SIXTY_FPS_BUDGET_USEC, "pico estrutural de planejamento fica abaixo de 16,67 ms")

	var entry_ready := await _wait_for_corridor(forest)
	_check(entry_ready, "corredor da entrada fica residente com prazo finito")
	var entry_resident: int = int(forest.get_resident_count())
	var entry_ids: Array[int] = forest.get_resident_plan_ids()
	var entry_signatures := _resident_signature_by_id(forest)
	_check(entry_resident > 0 and entry_resident < plan.size(), "entrada carrega janela local, não a floresta inteira")
	_check(_resident_collisions_are_valid(forest), "pinheiros residentes mantêm footprint de colisão")

	await _move_gradually(player, Vector2(5850, 680))
	var vehicle := FocusProbe.new()
	vehicle.position = player.position
	vehicle.is_driven_by_player = true
	vehicle.add_to_group("vehicle")
	world.add_child(vehicle)
	player.hide()
	var route := [Vector2(6750, 560), Vector2(8300, 650), Vector2(8100, 100), Vector2(7800, -800), Vector2(7150, -1750), Vector2(6950, -2550), Vector2(6200, -2700)]
	for point in route:
		await _move_gradually(vehicle, point)
	_check(await _wait_for_corridor(forest), "corredor à frente do veículo conclui após deslocamento físico")
	_check(bool(forest.get_meta("stream_focus_is_vehicle", false)), "foco usa RegionTravel.controlled_car enquanto o jogador dirige")
	_check(int(forest.get_meta("stream_evicted_total", 0)) > 0, "células distantes são removidas com o avanço")
	var allowed_resident_distance := maxf(STREAMER.EVICT_RADIUS, STREAMER.MAX_LOOKAHEAD_DISTANCE + STREAMER.AHEAD_LOAD_RADIUS) + STREAMER.CELL_SIZE * sqrt(2.0)
	_check(_max_resident_distance(forest, vehicle.position) <= allowed_resident_distance, "nenhum sólido ou colisão permanece fora do envelope com histerese")
	var summit_ids: Array[int] = forest.get_resident_plan_ids()
	var stale_entry_count := 0
	for id in entry_ids:
		if id in summit_ids:
			stale_entry_count += 1
	_check(stale_entry_count < entry_ids.size() / 4, "faixa da entrada não permanece residente no cume")

	route.reverse()
	for point in route:
		await _move_gradually(vehicle, point)
	await _move_gradually(vehicle, Vector2(5850, 680))
	player.position = vehicle.position
	vehicle.is_driven_by_player = false
	player.show()
	vehicle.queue_free()
	await process_frame
	await _move_gradually(player, BUILDER.FOREST_STREAM_ENTRY)
	_check(await _wait_for_corridor(forest), "entrada volta a ficar pronta por aproximação")
	_check(int(forest.get_meta("stream_reentered_total", 0)) > 0, "reentrada rematerializa células já visitadas")
	var reentry_signatures := _resident_signature_by_id(forest)
	var deterministic_reentry := true
	var compared := 0
	for index in entry_signatures:
		if reentry_signatures.has(index):
			compared += 1
			if reentry_signatures[index] != entry_signatures[index]:
				deterministic_reentry = false
	_check(compared > 0 and deterministic_reentry, "reentrada preserva escala, variante, neve/bare e rochas")
	_check(_resident_collisions_are_valid(forest), "colisões reaparecem corretamente na reentrada")
	_check(_max_resident_distance(forest, player.position) <= allowed_resident_distance, "reentrada também respeita o envelope máximo de residência")

	var peak_resident := int(forest.get_meta("stream_peak_resident", plan.size()))
	_check(peak_resident < plan.size() / 2, "residência máxima permanece abaixo de metade do mapa")
	_check(int(forest.get_meta("stream_peak_instances_per_frame", 99)) <= BUILDER.FOREST_STREAM_MAX_INSTANCES, "materialização respeita duas instâncias por frame")
	_check(int(forest.get_meta("stream_build_peak_usec", SIXTY_FPS_BUDGET_USEC)) < SIXTY_FPS_BUDGET_USEC, "pico headless de materialização fica abaixo de 16,67 ms")
	_check(int(forest.get_meta("stream_evict_peak_usec", SIXTY_FPS_BUDGET_USEC)) < SIXTY_FPS_BUDGET_USEC, "pico headless de evicção fica abaixo de 16,67 ms")

	print("DENSE_PINE_PROXIMITY_STREAM plan=", plan.size(), " initial_return_usec=", initial_return_usec,
		" entry_resident=", entry_resident, " peak_resident=", peak_resident,
		" resident_now=", forest.get_meta("stream_resident_count", -1),
		" materialized_total=", forest.get_meta("stream_materialized_total", -1),
		" evicted_total=", forest.get_meta("stream_evicted_total", -1),
		" reentered_total=", forest.get_meta("stream_reentered_total", -1),
		" planning_peak_usec=", forest.get_meta("stream_planning_peak_usec", -1),
		" build_peak_usec=", forest.get_meta("stream_build_peak_usec", -1),
		" evict_peak_usec=", forest.get_meta("stream_evict_peak_usec", -1),
		" peak_interval_usec=", peak_interval_usec, " failures=", failures)
	world.queue_free()
	for _frame in 3:
		await process_frame
	quit(0 if failures.is_empty() else 1)
