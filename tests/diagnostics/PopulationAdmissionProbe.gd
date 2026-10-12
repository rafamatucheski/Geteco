extends SceneTree
## Read-only admission diagnostic in rendered Main. Production keeps its normal
## population jobs; this probe only selects and validates, never spawns an actor.
## Its copied validator deliberately measures the original, unclipped-route policy.
## Run with the compiled .NET engine and -- --no-save --skip-arrival.
const MARKET_POINT := Vector3(109.375, .12, 32.8875)
const PORT_POLICY := preload("res://gameplay/urban_v1/HarborPortPolicy.gd")
const CANAL_TUNNEL := preload("res://world/urban_detail/CanalTunnel3D.gd")
const OUTPUT := "res://evidence/heart-performance-20261011/admission-probe.json"
const SAMPLE_COUNT := 128
const PER_FRAME := 4
var world: Node
var initialized_usec := 0
var ready_usec := 0
var setup_usec := 0
var settle_usec := 0
var probe_usec := 0
var completed := false
var reason := ""
var counts: Dictionary = {}
var rows: Array[Dictionary] = []
var population_states: Array[Dictionary] = []
var timing_totals_usec: Dictionary = {}

func _initialize() -> void:
	initialized_usec = Time.get_ticks_usec()
	run.call_deferred()

func _deadline() -> void:
	if completed: return
	reason = "140_second_deadline"
	_export()
	push_error("POPULATION_ADMISSION_PROBE_TIMEOUT")
	quit(4)

func run() -> void:
	create_timer(140.0).timeout.connect(_deadline)
	if "--no-save" not in OS.get_cmdline_user_args() or "--skip-arrival" not in OS.get_cmdline_user_args():
		reason = "requires_no_save_and_skip_arrival"
		_export()
		quit(2)
		return
	if DisplayServer.get_name() == "headless" or not ClassDB.class_exists(&"CSharpScript") or not OS.get_environment("HARBOR_NO_CSHARP").is_empty():
		reason = "requires_rendered_compiled_dotnet_path"
		_export()
		quit(3)
		return
	seed(21092026)
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	root.add_child(world)
	current_scene = world
	while world.session == null or not world.session.ready_for_play or world.production == null or not world.production.ready_for_play or root.has_node("LoadingCurtain") or world.has_node("LoadingCurtain"):
		await process_frame
	ready_usec = Time.get_ticks_usec()
	if not world.production.no_save:
		reason = "production_no_save_not_active"
		_export()
		quit(3)
		return
	world.session.state.intro.stage = "complete"
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	world.camera.set_preview_view(false)
	world.camera.heading = 0.0
	world.camera.set_process_unhandled_input(false)
	world.driving.set_process_unhandled_input(false)
	world.session.set_process_input(false)
	var controls: Node = root.get_node("GameInput")
	controls.set_process_input(false)
	controls._clear_camera_motion()
	controls.touch_aim = Vector2(5.0, 3.0).normalized()
	world.session.weather.time_of_day = .4
	world.session.weather.weather_state = 0
	world.session.weather.weather_timer = 99999.0
	world.session.weather._update()
	world.production.region.prepare_collision_at(MARKET_POINT)
	world.player.teleport(MARKET_POINT)
	world.production.region.set_focus(MARKET_POINT)
	world.session.railway_world.set_focus(MARKET_POINT)
	world.camera.initialized = false
	setup_usec = Time.get_ticks_usec()
	var next_state := setup_usec
	while Time.get_ticks_usec() - setup_usec < 30000000:
		await process_frame
		var now := Time.get_ticks_usec()
		if now >= next_state:
			population_states.append(_state())
			next_state = now + 1000000
	settle_usec = Time.get_ticks_usec()
	population_states.append(_state())
	for index in SAMPLE_COUNT:
		if index % PER_FRAME == 0: await process_frame
		var began := Time.get_ticks_usec()
		var row := _evaluate()
		row["index"] = index
		row["process_frame"] = Engine.get_process_frames()
		row["total_usec"] = Time.get_ticks_usec() - began
		rows.append(row)
		var outcome: String = row.outcome
		counts[outcome] = int(counts.get(outcome, 0)) + 1
		for stage in row.timings_usec:
			timing_totals_usec[stage] = int(timing_totals_usec.get(stage, 0)) + int(row.timings_usec[stage])
	probe_usec = Time.get_ticks_usec()
	population_states.append(_state())
	completed = true
	_export()
	print("POPULATION_ADMISSION_PROBE ", JSON.stringify({"counts": counts, "rows": rows.size(), "timings_usec": timing_totals_usec, "output": OUTPUT, "population": _state()}))
	quit(0)

func _state() -> Dictionary:
	if not is_instance_valid(world) or world.production == null or not is_instance_valid(world.player): return {}
	var idle := true
	for region in world.production.regions.values():
		if is_instance_valid(region) and (not region.is_streaming_idle() or not region._retiring.is_empty()): idle = false
	return {"engine_usec": Time.get_ticks_usec(), "point": str(world.player.global_position), "people": world.people.size(), "requested_population": world.production.requested_population, "population_cap": world.production._population_cap(), "density_scale": world.production.density_scale, "ambient_traffic": world.production._ambient_traffic_count(), "traffic_cap": world.production._traffic_cap(), "slots": world.production.population_layout.slots.size(), "streaming_idle": idle, "focused": DisplayServer.window_is_focused()}

func _timed(row: Dictionary, stage: String, began: int) -> void:
	row.timings_usec[stage] = Time.get_ticks_usec() - began

func _reject(row: Dictionary, outcome: String) -> Dictionary:
	row["outcome"] = outcome
	return row

func _evaluate() -> Dictionary:
	var production: Node = world.production
	var row := {"timings_usec": {}, "outcome": ""}
	var began := Time.get_ticks_usec()
	var segment: Dictionary = production.population_layout.select(production)
	_timed(row, "select", began)
	if segment.is_empty(): return _reject(row, "slots")
	row["road"] = str(segment.road.id)
	row["road_width"] = float(segment.width)
	row["sidewalk_offset"] = float(segment.width) * .5 + .85
	row["point_selected"] = str(segment.point)
	row["segment_a"] = str(segment.a)
	row["segment_b"] = str(segment.b)
	var along: Vector3 = segment.a.direction_to(segment.b)
	var point: Vector3 = segment.point
	var margin := minf(20.0, segment.a.distance_to(segment.b) * .4)
	var center := Geometry3D.get_closest_point_to_segment(point, segment.a, segment.b)
	var offset := point - center
	var start: Vector3 = center - along * minf(margin, center.distance_to(segment.a) * .8) + offset
	var finish: Vector3 = center + along * minf(margin, center.distance_to(segment.b) * .8) + offset
	var grounded: Array[Vector3] = []
	row["ground_hits"] = []
	began = Time.get_ticks_usec()
	for candidate in [point, start, finish]:
		var ground: Dictionary = world.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(candidate + Vector3.UP * 1.0, candidate - Vector3.UP * 1.0, 1))
		row.ground_hits.append({"candidate": str(candidate), "hit": _hit_description(ground)})
		if ground.is_empty() or absf(ground.position.y - candidate.y) > .4:
			_timed(row, "floor", began)
			return _reject(row, "floor")
		grounded.append(Vector3(candidate.x, ground.position.y + .08, candidate.z))
	_timed(row, "floor", began)
	point = grounded[0]
	start = grounded[1]
	finish = grounded[2]
	row["grounded"] = [str(point), str(start), str(finish)]
	# Preserve production's ordering: carriageway and tunnel checks are
	# interleaved per endpoint, rather than grouping all checks by category.
	for end in [point, start, finish]:
		began = Time.get_ticks_usec()
		var roadway: bool = production._on_carriageway(end)
		row.timings_usec["carriageway"] = int(row.timings_usec.get("carriageway", 0)) + Time.get_ticks_usec() - began
		if roadway:
			row["failed_point"] = str(end)
			return _reject(row, "carriageway")
		began = Time.get_ticks_usec()
		var tunnel: bool = CANAL_TUNNEL.reserves(Vector2(end.x, end.z), .5)
		row.timings_usec["tunnel"] = int(row.timings_usec.get("tunnel", 0)) + Time.get_ticks_usec() - began
		if tunnel:
			row["failed_point"] = str(end)
			return _reject(row, "tunnel")
	var pedestrian_route := PackedVector3Array([start, finish])
	began = Time.get_ticks_usec()
	var private_area: bool = PORT_POLICY.contains_private_area(point) or PORT_POLICY.segment_enters_private_area(pedestrian_route[0], pedestrian_route[1])
	_timed(row, "private", began)
	if private_area: return _reject(row, "private")
	began = Time.get_ticks_usec()
	var clear: bool = world.session.position_clear(point + Vector3.UP * .06)
	_timed(row, "positionclear", began)
	if not clear:
		row["positionclear_detail"] = _position_detail(point + Vector3.UP * .06)
		return _reject(row, "positionclear")
	began = Time.get_ticks_usec()
	var route_clear: bool = production.desert_social_route_clear(pedestrian_route)
	_timed(row, "routeclear", began)
	if not route_clear:
		row["routeclear_detail"] = _route_detail(pedestrian_route)
		return _reject(row, "routeclear")
	return _reject(row, "accepted")

func _hit_description(hit: Dictionary) -> Dictionary:
	if hit.is_empty(): return {}
	var collider: Variant = hit.get("collider")
	return {"position": str(hit.get("position", Vector3.ZERO)), "normal": str(hit.get("normal", Vector3.ZERO)), "collider": str(collider.get_path()) if is_instance_valid(collider) and collider is Node and collider.is_inside_tree() else ""}

func _colliders(hits: Array[Dictionary]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for hit in hits:
		var body: Variant = hit.get("collider")
		result.append({"collider": str(body.get_path()) if is_instance_valid(body) and body is Node and body.is_inside_tree() else "", "class": body.get_class() if is_instance_valid(body) else ""})
	return result

func _position_detail(point: Vector3) -> Dictionary:
	var query := PhysicsShapeQueryParameters3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = .32
	shape.height = 1.7
	query.shape = shape
	query.collision_mask = 7
	query.transform = Transform3D(Basis.IDENTITY, point + Vector3.UP * .9)
	query.exclude = [world.player.get_rid()]
	return {"capsule_hits": _colliders(world.get_world_3d().direct_space_state.intersect_shape(query, 4)), "floor": _hit_description(world.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(point + Vector3.UP * .3, point - Vector3.UP * .5, 1)))}

func _route_detail(route: PackedVector3Array) -> Dictionary:
	var a := route[0]
	var b := route[-1]
	var steps := maxi(1, ceili(a.distance_to(b) / 2.0))
	for i in range(steps + 1):
		var point := a.lerp(b, float(i) / steps)
		if world.production._on_carriageway(point): return {"stage": "intermediate_carriageway", "point": str(point)}
		if not world.session.position_clear(point + Vector3.UP * .08): return {"stage": "intermediate_position", "point": str(point), "detail": _position_detail(point + Vector3.UP * .08)}
	var query := PhysicsShapeQueryParameters3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = .72 if a.distance_squared_to(b) > .01 else .32
	shape.height = 1.7
	query.shape = shape
	query.collision_mask = 1
	query.transform = Transform3D(Basis.IDENTITY, a + Vector3.UP * .98)
	query.motion = b - a
	var hits: Array[Dictionary] = world.get_world_3d().direct_space_state.intersect_shape(query, 4)
	if not hits.is_empty(): return {"stage": "initial_swept_capsule_overlap", "radius": shape.radius, "hits": _colliders(hits)}
	var travel: PackedFloat32Array = world.get_world_3d().direct_space_state.cast_motion(query)
	return {"stage": "swept_capsule_motion", "radius": shape.radius, "travel": [travel[0], travel[1]]}

func _export() -> void:
	var absolute := ProjectSettings.globalize_path(OUTPUT)
	DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	var report := {"scope": "Read-only candidate admission diagnostic in rendered Main, not an FPS benchmark. Live production population jobs remain enabled; selector calls consume its normal RNG but create no actor, change no density/limits and write no save. Rejection details make extra read-only physics queries after the exact production verdict.", "completed": completed, "reason": reason, "engine": Engine.get_version_info().string, "pid": OS.get_process_id(), "main_scene": "res://Main.tscn", "sample_target": SAMPLE_COUNT, "samples_per_process_frame": PER_FRAME, "counts": counts, "timings_usec": timing_totals_usec, "initialized_usec": initialized_usec, "ready_usec": ready_usec, "setup_usec": setup_usec, "settle_end_usec": settle_usec, "probe_end_usec": probe_usec, "elapsed_seconds": (Time.get_ticks_usec() - initialized_usec) / 1000000.0, "population_states": population_states, "last_state": _state(), "rows": rows}
	var file := FileAccess.open(absolute, FileAccess.WRITE)
	if file == null:
		push_error("POPULATION_ADMISSION_PROBE_EXPORT_FAILED: " + absolute)
		return
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
