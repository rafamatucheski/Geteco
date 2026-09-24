extends SceneTree

const ROAD_SCRIPT := preload("res://world/mountain_pass/MountainPassRoad.gd")
const RUNTIME_WORK_SCHEDULER := preload("res://systems/RuntimeWorkScheduler.gd")
const FRAME_BUDGET_USEC := 16667

var failures := 0

class StreamParent extends Node2D:
	var streamed_region := true

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, description: String) -> void:
	print("PASS " if condition else "FAIL ", description)
	if not condition:
		failures += 1

func _elapsed(start_usec: int) -> int:
	return Time.get_ticks_usec() - start_usec

func _simplify_open(points: PackedVector2Array, epsilon: float) -> PackedVector2Array:
	if points.size() <= 2:
		return points.duplicate()
	var keep := PackedByteArray()
	keep.resize(points.size())
	keep[0] = 1
	keep[points.size() - 1] = 1
	var ranges: Array[Vector2i] = [Vector2i(0, points.size() - 1)]
	while not ranges.is_empty():
		var span: Vector2i = ranges.pop_back()
		var furthest := -1
		var maximum := epsilon
		for index in range(span.x + 1, span.y):
			var closest := Geometry2D.get_closest_point_to_segment(points[index], points[span.x], points[span.y])
			var distance := points[index].distance_to(closest)
			if distance > maximum:
				maximum = distance
				furthest = index
		if furthest >= 0:
			keep[furthest] = 1
			ranges.append(Vector2i(span.x, furthest))
			ranges.append(Vector2i(furthest, span.y))
	var result := PackedVector2Array()
	for index in points.size():
		if keep[index] != 0:
			result.append(points[index])
	return result

func _simplify_closed(points: PackedVector2Array, epsilon: float) -> PackedVector2Array:
	if points.size() <= 4:
		return points.duplicate()
	var split := 1
	var greatest := 0.0
	for index in range(1, points.size()):
		var distance := points[0].distance_squared_to(points[index])
		if distance > greatest:
			greatest = distance
			split = index
	var first := _simplify_open(points.slice(0, split + 1), epsilon)
	var second_source := points.slice(split, points.size())
	second_source.append(points[0])
	var second := _simplify_open(second_source, epsilon)
	first.resize(first.size() - 1)
	second.resize(second.size() - 1)
	first.append_array(second)
	return first

func _configure_junctions(road: Node) -> void:
	road.junctions.road_curve = road.curve
	road.junctions.half_road = road.road_width * 0.5
	road.junctions.add_access(road.winter_pocket_access, 31.0, false, "winter_pocket")
	road.junctions.add_access(road.resort_curve, 70.0, false, "resort_access")
	road.junctions.add_access(road.summit_connector_curve, 64.0, false, "summit_connector")

func _profile_stages() -> Dictionary:
	var road := ROAD_SCRIPT.new()
	var result := {}
	var started := Time.get_ticks_usec()
	road._build_curve()
	result.curve_usec = _elapsed(started)
	started = Time.get_ticks_usec()
	_configure_junctions(road)
	result.junctions_usec = _elapsed(started)
	started = Time.get_ticks_usec()
	road._build_pavement()
	result.pavement_usec = _elapsed(started)
	result.pavement_breakdown = road.get_meta("pavement_stage_usec", {}).duplicate()
	started = Time.get_ticks_usec()
	road._build_guard_rails()
	result.guard_and_cliffs_usec = _elapsed(started)
	result.guard_breakdown = road.get_meta("guard_stage_usec", {}).duplicate()
	result.guard_collision_count = road.guard_rails.get_child_count()
	result.cliff_patch_count = road.cliff_edges.patches.size() if is_instance_valid(road.cliff_edges) else 0
	started = Time.get_ticks_usec()
	road._build_ice_hazard_area()
	result.ice_usec = _elapsed(started)
	started = Time.get_ticks_usec()
	road._precompute_road_draw_geometry()
	result.draw_geometry_usec = _elapsed(started)
	result.total_usec = int(result.curve_usec) + int(result.junctions_usec) + int(result.pavement_usec) + int(result.guard_and_cliffs_usec) + int(result.ice_usec) + int(result.draw_geometry_usec)
	road.free()
	return result

func _profile_pavement_variants() -> Dictionary:
	var road := ROAD_SCRIPT.new()
	road._build_curve()
	_configure_junctions(road)
	var started := Time.get_ticks_usec()
	var parts: Array[PackedVector2Array] = []
	parts.append_array(Geometry2D.offset_polyline(road.smooth_points, road.road_width * 0.5, Geometry2D.JOIN_ROUND, Geometry2D.END_BUTT))
	for route in [road.resort_smooth_points, road.summit_connector_smooth_points]:
		var half_width := 70.0 if route == road.resort_smooth_points else 64.0
		parts.append_array(Geometry2D.offset_polyline(route, half_width, Geometry2D.JOIN_ROUND, Geometry2D.END_ROUND))
	parts.append(road._circle_polygon(road.control_points[-1], 80.0))
	parts.append(road._circle_polygon(Vector2(7140, -2545), 108.0))
	parts.append(PackedVector2Array([Vector2(6918,-2662),Vector2(7062,-2662),Vector2(7062,-2485),Vector2(6918,-2485)]))
	var outline := parts.pop_front() as PackedVector2Array
	for part in parts:
		var merged := Geometry2D.merge_polygons(outline, part)
		for polygon in merged:
			if not Geometry2D.is_polygon_clockwise(polygon):
				outline = polygon
	var merge_usec := _elapsed(started)
	var merged_vertices := outline.size()
	started = Time.get_ticks_usec()
	var inset := Geometry2D.offset_polygon(outline, -14.0, Geometry2D.JOIN_ROUND)
	if inset.size() == 1:
		var rounded := Geometry2D.offset_polygon(inset[0], 14.0, Geometry2D.JOIN_ROUND)
		if rounded.size() == 1:
			outline = rounded[0]
	var finish_usec := _elapsed(started)
	var triangles_started := Time.get_ticks_usec()
	var triangles := Geometry2D.triangulate_polygon(outline)
	var triangulate_usec := _elapsed(triangles_started)
	var simplify_started := Time.get_ticks_usec()
	var simplified := _simplify_closed(outline, 0.75)
	var simplify_usec := _elapsed(simplify_started)
	triangles_started = Time.get_ticks_usec()
	var simplified_triangles := Geometry2D.triangulate_polygon(simplified)
	var simplified_triangulate_usec := _elapsed(triangles_started)
	var result := {
		"merge_usec": merge_usec,
		"merged_vertices": merged_vertices,
		"single_round_usec": finish_usec,
		"rounded_vertices": outline.size(),
		"triangulate_usec": triangulate_usec,
		"triangle_indices": triangles.size(),
		"simplify_usec": simplify_usec,
		"simplified_vertices": simplified.size(),
		"simplified_triangulate_usec": simplified_triangulate_usec,
		"simplified_triangle_indices": simplified_triangles.size(),
	}
	road.free()
	return result

func _road_geometry_signature(road: Node) -> Dictionary:
	var guard_segment_count := 0
	var guard_length := 0.0
	for section in road._guard_rail_sections():
		guard_segment_count += maxi(0, section.size() - 1)
		for i in range(section.size() - 1):
			guard_length += section[i].distance_to(section[i + 1])
	var pavement_vertices := 0
	for polygon in road.pavement:
		pavement_vertices += polygon.size()
	var physical_segments := 0
	var rail_collision := road.guard_rails.get_node_or_null("GuardRailSegments") as CollisionShape2D
	if rail_collision != null and rail_collision.shape is ConcavePolygonShape2D:
		physical_segments = (rail_collision.shape as ConcavePolygonShape2D).segments.size() / 2
	return {
		"smooth_points": road.smooth_points.size(),
		"curve_length": road.curve.get_baked_length(),
		"pavement_polygons": road.pavement.size(),
		"pavement_vertices": pavement_vertices,
		"guard_segments": guard_segment_count,
		"guard_length": guard_length,
		"guard_collision_nodes": road.guard_rails.get_child_count(),
		"guard_collision_segments": physical_segments,
		"cliff_patches": road.cliff_edges.patches.size() if is_instance_valid(road.cliff_edges) else 0,
		"shoulder_patches": road._cached_shoulder_patches_shoulder.size() + road._cached_shoulder_patches_inner.size(),
		"snow_patches": road._cached_snow_edge_patches.size(),
		"marking_segments": road._cached_tire_track_segments.size() + road._cached_edge_line_segments.size() + road._cached_centerlines_low.size() + road._cached_centerlines_up.size() + road._cached_resort_markings.size(),
	}

func _check_route_contract(road: Node) -> void:
	_check(road.curve != null and road.curve.get_baked_length() > 7000.0, "a rota principal continua longa e conectada")
	_check(road.smooth_points.size() > 900, "a spline preserva amostragem suficiente para as curvas")
	_check(road.pavement.size() == 1 and road.pavement[0].size() > 300, "o pavimento unido preserva seu contorno curvo sem excesso subpixel")
	_check(road.resort_curve != null and road.summit_connector_curve != null and road.winter_pocket_access != null, "junctions e acessos laterais continuam publicados")
	_check(road.guard_rails != null and road._guard_rail_sections().size() >= 4, "guard rails continuam cobrindo os hairpins")
	var rail_collision := road.guard_rails.get_node_or_null("GuardRailSegments") as CollisionShape2D
	_check(rail_collision != null and rail_collision.shape is ConcavePolygonShape2D, "guard rails usam uma colisão estática agregada")
	if rail_collision != null and rail_collision.shape is ConcavePolygonShape2D:
		var physical_segments := (rail_collision.shape as ConcavePolygonShape2D).segments.size() / 2
		var expected_segments := 0
		for section in road._guard_rail_sections(): expected_segments += section.size() - 1
		_check(physical_segments == expected_segments, "a agregação preserva todos os segmentos físicos")
	_check(road.ice_trigger_area != null and road.ice_trigger_area.get_child_count() == 1, "a zona de black ice continua física")
	var sample_offsets := PackedFloat32Array([0.0, 500.0, 1800.0, 3200.0, 4800.0, 6400.0, road.curve.get_baked_length() - 1.0])
	for offset in sample_offsets:
		var pose: Transform2D = road.curve.sample_baked_with_rotation(offset, true)
		var center: Vector2 = pose.origin
		var normal := Vector2(-pose.x.y, pose.x.x)
		_check(road.is_point_on_road(center, 76.0), "centro da pista reconhecido na amostra %.0f" % offset)
		_check(Geometry2D.is_point_in_polygon(center, road.pavement[0]), "pavimento cobre a amostra %.0f" % offset)
		_check(not road.is_point_on_road(center + normal * 190.0, 76.0), "fora da pista permanece livre na amostra %.0f" % offset)
	_check(road.is_point_on_road(Vector2(7140, -2545), 76.0), "ilha do resort continua conectada")
	_check(road.is_point_on_road(Vector2(6990, -2570), 76.0), "conector do cume continua conectado")

func _profile_streamed_build() -> Dictionary:
	RUNTIME_WORK_SCHEDULER.reset_for_tests()
	var parent := StreamParent.new()
	root.add_child(parent)
	var road := ROAD_SCRIPT.new()
	# A distinct cache key proves the cold streamed path instead of reusing the
	# 140 px geometry built by the synchronous baseline above.
	road.road_width = 140.125
	var started := Time.get_ticks_usec()
	parent.add_child(road)
	var initial_return_usec := _elapsed(started)
	var frames := 0
	var maximum_interval_usec := 0
	var previous := Time.get_ticks_usec()
	while not road.build_complete and frames < 24:
		await process_frame
		var now := Time.get_ticks_usec()
		maximum_interval_usec = maxi(maximum_interval_usec, now - previous)
		previous = now
		frames += 1
	var scheduler_snapshot: Dictionary = RUNTIME_WORK_SCHEDULER.telemetry_snapshot()
	var road_records: Array[Dictionary] = []
	var granted_frames: Dictionary = {}
	for record_variant in scheduler_snapshot.records:
		var record: Dictionary = record_variant
		if not String(record.get("producer", "")).begins_with("mountain_road/"):
			continue
		road_records.append(record)
		var granted_frame := int(record.get("frame", -1))
		granted_frames[granted_frame] = int(granted_frames.get(granted_frame, 0)) + 1
	var duplicate_grant_frames := 0
	for count_variant in granted_frames.values():
		if int(count_variant) > 1:
			duplicate_grant_frames += 1
	var result := {
		"complete": road.build_complete,
		"frames": frames,
		"initial_return_usec": initial_return_usec,
		"maximum_interval_usec": maximum_interval_usec,
		"peak_stage_usec": road.build_peak_usec,
		"stages": road.build_stage_usec.duplicate(),
		"guard_breakdown": road.get_meta("guard_stage_usec", {}).duplicate(),
		"scheduler_records": road_records.size(),
		"scheduler_completed": road_records.filter(func(record: Dictionary): return String(record.get("status", "")) == "completed").size(),
		"scheduler_duplicate_grant_frames": duplicate_grant_frames,
		"scheduler_over_budget": road_records.filter(func(record: Dictionary): return record.get("over_budget", false) == true).size(),
	}
	parent.queue_free()
	await process_frame
	return result

func _run() -> void:
	create_timer(30.0).timeout.connect(func(): quit(2))
	var capture_enabled := OS.get_cmdline_user_args().has("--capture")
	if capture_enabled:
		root.size = Vector2i(1280, 720)
		root.content_scale_size = root.size
		var camera := Camera2D.new()
		camera.position = Vector2(6500, -1200)
		camera.zoom = Vector2.ONE * 0.22
		root.add_child(camera)
		camera.make_current()
	var stages := _profile_stages()
	var pavement_variants := _profile_pavement_variants()
	var road := ROAD_SCRIPT.new()
	var started := Time.get_ticks_usec()
	root.add_child(road)
	var ready_usec := _elapsed(started)
	await process_frame
	var signature := _road_geometry_signature(road)
	_check_route_contract(road)
	if capture_enabled:
		await RenderingServer.frame_post_draw
		var capture_error := root.get_texture().get_image().save_png("res://_codex_diag/mountain-pass-road-after.png")
		_check(capture_error == OK, "a captura renderizada isolada foi gravada")
	print("MOUNTAIN_PASS_ROAD_STAGES curve_usec=%d junctions_usec=%d pavement_usec=%d guard_and_cliffs_usec=%d ice_usec=%d draw_geometry_usec=%d staged_total_usec=%d ready_usec=%d frame_budget_usec=%d" % [
		stages.curve_usec, stages.junctions_usec, stages.pavement_usec, stages.guard_and_cliffs_usec,
		stages.ice_usec, stages.draw_geometry_usec, stages.total_usec, ready_usec, FRAME_BUDGET_USEC
	])
	print("MOUNTAIN_PASS_ROAD_GEOMETRY ", JSON.stringify(signature))
	print("MOUNTAIN_PASS_ROAD_PAVEMENT_BREAKDOWN ", JSON.stringify(stages.pavement_breakdown))
	print("MOUNTAIN_PASS_ROAD_GUARD_BREAKDOWN ", JSON.stringify(stages.guard_breakdown))
	print("MOUNTAIN_PASS_ROAD_PAVEMENT_VARIANTS ", JSON.stringify(pavement_variants))
	road.queue_free()
	await process_frame
	var streamed := await _profile_streamed_build()
	_check(streamed.complete == true, "a construção parcelada conclui antes do limite do fixture")
	_check(int(streamed.frames) >= 8 and int(streamed.frames) < 24, "a construção de streaming distribui os estágios por vários quadros")
	var expected_scheduler_records := ROAD_SCRIPT.STREAM_STAGE_CONTRACT.size() - 1
	_check(int(streamed.scheduler_records) == expected_scheduler_records, "todos os estágios assíncronos reservam trabalho global")
	_check(int(streamed.scheduler_completed) == expected_scheduler_records, "todas as reservas da estrada são concluídas com telemetria")
	_check(int(streamed.scheduler_duplicate_grant_frames) == 0, "a estrada nunca recebe duas reservas pesadas no mesmo quadro")
	print("MOUNTAIN_PASS_ROAD_STREAMED ", JSON.stringify(streamed))
	print("MOUNTAIN_PASS_ROAD_RESULT failures=%d" % failures)
	quit(failures)
