extends SceneTree
const VEHICLE_GEOMETRY_CACHE := preload("res://cars/VehicleGeometryCache.gd")
var _profile_views: Array[Viewport] = []
var _profile_last_ms := 0
var _scenario_world: Node
const STARTUP_TIMEOUT_MSEC := 120000
const DEFAULT_STALL_THRESHOLD_MS := 100.0
const MAX_STALL_TRACES := 32
var _scenario_hour := 0.45
var _sample_failed := false
var _stall_threshold_ms := DEFAULT_STALL_THRESHOLD_MS
var _trace_stall_events := false
var _tree_event_serial := 0
var _recent_tree_events: Array[Dictionary] = []
## Rendered, finite production checkpoint diagnostic. Each invocation uses a
## fresh scene and redirects gameplay saves to its evidence directory.
## User args: out_dir=<absolute directory> --police --normal-cap --night

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Frame stability requires a real renderer")
		quit(1)
		return
	var args := OS.get_cmdline_user_args()
	_trace_stall_events = args.has("--trace-stalls")
	var output := ProjectSettings.globalize_path("user://tests/frame-stability")
	for arg in args:
		if arg.begins_with("out_dir="): output = arg.trim_prefix("out_dir=")
		elif arg.begins_with("stall_threshold_ms="):
			_stall_threshold_ms = maxf(16.67, float(arg.trim_prefix("stall_threshold_ms=")))
	if DirAccess.make_dir_recursive_absolute(output.path_join("saves")) != OK:
		push_error("Cannot create benchmark output: " + output)
		quit(1)
		return
	var saves := root.get_node("SaveManager")
	saves.set("_save_dir", output.path_join("saves") + "/")
	saves.set("_save_directory_ready", false)
	saves.clear_pending_save()
	seed(12092026)
	root.size = Vector2i(1280, 720)
	for arg in args:
		if arg.begins_with("resolution="):
			var dimensions := arg.trim_prefix("resolution=").split("x")
			if dimensions.size() == 2:
				root.size = Vector2i(int(dimensions[0]), int(dimensions[1]))
	# Keep identical world coverage while changing the native pixel workload.
	root.content_scale_size = Vector2i(1280, 720)
	if not args.has("--normal-cap"):
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		Engine.max_fps = 0
	var campaign := root.get_node("CampaignState")
	campaign.reset_campaign()
	for flag in ["harbor_arrival_seen", "harbor_arrival_call_complete", "harbor_maciota_met", "harbor_delivery_complete"]:
		campaign.set_campaign_flag(StringName(flag), true)
	var world = load("res://world/harbor/HarborGame.tscn").instantiate()
	root.add_child(world)
	current_scene = world
	var deadline := Time.get_ticks_msec() + STARTUP_TIMEOUT_MSEC
	while (not world.gameplay_ready or not world.world_build_ready) and Time.get_ticks_msec() < deadline:
		await process_frame
	if not world.gameplay_ready or not world.world_build_ready or paused:
		push_error("Frame stability checkpoint unavailable")
		quit(1)
		return
	# Match the normal loading screen's geometry preparation at the same real
	# downtown position used by the police/chaos sample. Preparing at the arrival
	# spawn and teleporting afterward leaves visible residents in the first
	# gameplay window and measures the harness instead of the city.
	var preparation_player: Node2D = world.get_node("Player")
	var preparation_car: Node2D = world.get_node("PlayerCar")
	preparation_player.global_position = Vector2(2200, 1050)
	preparation_player.reset_physics_interpolation()
	var preparation_camera: Camera2D = preparation_player.get_node("Camera")
	preparation_camera.global_position = preparation_player.global_position
	preparation_camera.reset_smoothing()
	preparation_car.global_position = Vector2(700, 425)
	preparation_car.rotation = 0.0
	preparation_car.reset_physics_interpolation()
	paused = true
	await preload("res://cars/VehicleGeometryCache.gd").prepare_common_models(self)
	if not args.has("--skip-resident-preparation"):
		await preload("res://cars/VehicleGeometryCache.gd").prepare_resident_presentations(self)
	await root.get_node("EmergencyPool").prepare_presentations()
	await preload("res://audio/VehicleEngineSound.gd").prepare_catalog(self)
	paused = false
	_scenario_world = world
	_scenario_hour = 0.90 if args.has("--night") else 0.45
	world.weather.is_dynamic_time = true
	_hold_scenario_clock()
	world.weather.set_biome(world.weather.current_biome)
	world.weather.set_weather(1 if args.has("--rain") else 0)
	world.weather.weather_timer = 1000000.0
	var player: Node2D = world.get_node("Player")
	var car: CharacterBody2D = world.get_node("PlayerCar")
	player.global_position = Vector2(2200, 1050)
	car.global_position = Vector2(700, 425)
	car.rotation = 0.0
	world.call("_drive")
	await _sample(output, "warmup", 10.0, car)
	if _sample_failed:
		quit(1)
		return
	if args.has("--profile-render"):
		_collect_profile_views(root)
	if args.has("--police"): root.get_node("WantedManager").report_crime(240)
	Input.action_press("move_up")
	await _sample(output, "driving", 30.0, car)
	Input.action_release("move_up")
	if args.has("--capture"):
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output.path_join("gameplay.png"))
	quit(1 if _sample_failed else 0)

func _hold_scenario_clock() -> void:
	if not is_instance_valid(_scenario_world): return
	var bridge := _scenario_world.get_node_or_null("CobraCampaign")
	if bridge != null and bridge.ledger != null:
		bridge.ledger.data.day_elapsed = fposmod(_scenario_hour - 0.35, 1.0) * preload("res://world/harbor/campaign/CobraCampaignState.gd").DAY_SECONDS
	_scenario_world.weather.time_of_day = _scenario_hour

func _collect_profile_views(node: Node) -> void:
	# Per-viewport GPU timestamp instrumentation can itself stall the driver
	# with hundreds of cached SubViewports. Opt into that only for diagnosis;
	# normal frame certification runs without --profile-render altogether.
	if node is Viewport and (node == root or OS.get_cmdline_user_args().has("--profile-all-views")):
		_profile_views.append(node)
		RenderingServer.viewport_set_measure_render_time(node.get_viewport_rid(), true)
	for child in node.get_children(): _collect_profile_views(child)

func _report_render() -> void:
	if _profile_views.is_empty() or Time.get_ticks_msec() - _profile_last_ms < 1000: return
	_profile_last_ms = Time.get_ticks_msec()
	var rows: Array[Dictionary] = []
	for view in _profile_views:
		if not is_instance_valid(view): continue
		if view is SubViewport and view.render_target_update_mode == SubViewport.UPDATE_DISABLED: continue
		var rid := view.get_viewport_rid()
		var cpu := RenderingServer.viewport_get_measured_render_time_cpu(rid)
		var gpu := RenderingServer.viewport_get_measured_render_time_gpu(rid)
		if cpu > 0.1 or gpu > 0.1: rows.append({"path":str(view.get_path()),"cpu_ms":cpu,"gpu_ms":gpu})
	rows.sort_custom(func(a,b): return a.cpu_ms + a.gpu_ms > b.cpu_ms + b.gpu_ms)
	print("RENDER_BREAKDOWN ", JSON.stringify(rows.slice(0,12)))

func _sample(output: String, label: String, seconds: float, car: Node2D) -> void:
	var file := FileAccess.open(output.path_join(label + ".csv"), FileAccess.WRITE)
	if file == null:
		_sample_failed = true
		push_error("Cannot write benchmark samples: " + output)
		quit(1)
		return
	var stall_path := output.path_join(label + "_stalls.jsonl")
	var stall_file := FileAccess.open(stall_path, FileAccess.WRITE)
	if stall_file == null:
		_sample_failed = true
		push_error("Cannot write benchmark stall trace: " + stall_path)
		quit(1)
		return
	file.store_line("frame_ms,process_ms,physics_ms,draw_calls,x,y,police,phys_active,phys_pairs,physics_steps,render_cpu_ms,render_gpu_ms,object_count,node_count,resource_count,video_mem_mb,presentation_pending,window_focused")
	var samples: Array[float] = []
	var total := 0.0
	var over_33 := 0
	var over_66 := 0
	var police_peak := 0
	var hour_min := INF
	var hour_max := -INF
	var weather_states: Array[int] = []
	var previous_frame := Time.get_ticks_usec()
	var previous_physics_frame := Engine.get_physics_frames()
	var starting_position := car.global_position
	var previous_position := starting_position
	var travelled_px := 0.0
	var maximum_step_px := 0.0
	var moving_ms := 0.0
	var stopped_ms := 0.0
	var longest_stop_ms := 0.0
	var focused_frames := 0
	var focus_transitions := 0
	var previous_focus := DisplayServer.window_is_focused()
	var stall_count := 0
	var stall_traces := 0
	var frame_index := 0
	_recent_tree_events.clear()
	_tree_event_serial = 0
	if _trace_stall_events:
		node_added.connect(_record_tree_event.bind("add"))
		node_removed.connect(_record_tree_event.bind("remove"))
	var previous_metrics := _frame_metrics_snapshot()
	while total < seconds * 1000.0:
		await process_frame
		var now := Time.get_ticks_usec()
		var ms := (now - previous_frame) / 1000.0
		previous_frame = now
		var step := car.global_position.distance_to(previous_position)
		travelled_px += step
		maximum_step_px = maxf(maximum_step_px, step)
		previous_position = car.global_position
		# Physics can legitimately skip one rendered frame; only sustained stops
		# invalidate motion coverage. A collision still contributes its real cost.
		# Five px/s distinguishes a real crawl behind congestion from interpolation
		# noise. Distance and the five-second continuous-stop limit still prevent a
		# mostly stationary sample from being certified as driving.
		if step > ms * 0.005:
			moving_ms += ms
			stopped_ms = 0.0
		else:
			stopped_ms += ms
			longest_stop_ms = maxf(longest_stop_ms, stopped_ms)
		if is_instance_valid(_scenario_world):
			var hour: float = _scenario_world.weather.time_of_day
			hour_min = minf(hour_min, hour)
			hour_max = maxf(hour_max, hour)
			var weather_state: int = _scenario_world.weather.weather_state
			if not weather_states.has(weather_state): weather_states.append(weather_state)
		_hold_scenario_clock()
		_report_render()
		total += ms
		samples.append(ms)
		if ms > 33.3: over_33 += 1
		if ms > 66.7: over_66 += 1
		var police := 0
		for vehicle in get_nodes_in_group("emergency_vehicle"):
			if is_instance_valid(vehicle) and vehicle.visible and int(vehicle.get("type")) == 0: police += 1
		police_peak = maxi(police_peak, police)
		var physics_frame := Engine.get_physics_frames()
		var physics_steps := physics_frame - previous_physics_frame
		previous_physics_frame = physics_frame
		var active_objects := Performance.get_monitor(Performance.PHYSICS_2D_ACTIVE_OBJECTS)
		var collision_pairs := Performance.get_monitor(Performance.PHYSICS_2D_COLLISION_PAIRS)
		var render_cpu := RenderingServer.viewport_get_measured_render_time_cpu(root.get_viewport_rid())
		var render_gpu := RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid())
		var object_count := Performance.get_monitor(Performance.OBJECT_COUNT)
		var node_count := Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
		var resource_count := Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)
		var video_mem_mb := Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0
		var presentation_budget := root.get_node_or_null("PresentationBudget")
		var presentation_pending: int = int(presentation_budget.pending.size()) if presentation_budget != null else 0
		var focused := DisplayServer.window_is_focused()
		if focused: focused_frames += 1
		if focused != previous_focus: focus_transitions += 1
		previous_focus = focused
		file.store_line("%f,%f,%f,%d,%f,%f,%d,%f,%f,%d,%f,%f,%f,%f,%f,%f,%d,%d" % [ms, Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0, Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), car.global_position.x, car.global_position.y, police, active_objects, collision_pairs, physics_steps, render_cpu, render_gpu, object_count, node_count, resource_count, video_mem_mb, presentation_pending, int(focused)])
		var current_metrics := _frame_metrics_snapshot(presentation_budget, {
			"object_count": object_count,
			"node_count": node_count,
			"resource_count": resource_count,
			"video_mem_mb": video_mem_mb,
			"physics_active": active_objects,
			"physics_pairs": collision_pairs,
			"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		})
		if ms >= _stall_threshold_ms:
			stall_count += 1
			if stall_traces < MAX_STALL_TRACES:
				stall_file.store_line(JSON.stringify(_stall_details(label, frame_index, total, ms, physics_steps, car, previous_metrics, current_metrics)))
				stall_traces += 1
				# Expensive attribution happens between rendered frames. Restart the
				# wall-clock interval so writing the diagnostic cannot manufacture a
				# second false stall in the following gameplay sample.
				previous_frame = Time.get_ticks_usec()
		previous_metrics = current_metrics
		frame_index += 1
	file.close()
	stall_file.close()
	if _trace_stall_events:
		node_added.disconnect(_record_tree_event.bind("add"))
		node_removed.disconnect(_record_tree_event.bind("remove"))
	samples.sort()
	var report := {"scenario": label, "seconds": total / 1000.0, "frames": samples.size(), "fps": samples.size() * 1000.0 / total, "p50_ms": samples[int(samples.size() * .5)], "p95_ms": samples[int(samples.size() * .95)], "p99_ms": samples[int(samples.size() * .99)], "max_ms": samples[-1], "over_33ms": over_33, "over_66ms": over_66, "police_peak": police_peak, "gpu": RenderingServer.get_video_adapter_name(), "renderer": RenderingServer.get_current_rendering_method(), "engine": Engine.get_version_info(), "resolution": str(root.size), "vsync": DisplayServer.window_get_vsync_mode(), "max_fps": Engine.max_fps, "physics_ticks_per_second": Engine.physics_ticks_per_second, "max_physics_steps_per_frame": Engine.max_physics_steps_per_frame, "args": OS.get_cmdline_user_args()}
	var summary := FileAccess.open(output.path_join(label + ".json"), FileAccess.WRITE)
	if summary == null:
		_sample_failed = true
		push_error("Cannot write benchmark report: " + output)
		quit(1)
		return
	report["travelled_px"] = travelled_px
	report["displacement_px"] = car.global_position.distance_to(starting_position)
	report["maximum_step_px"] = maximum_step_px
	report["sample_kind"] = _sample_kind(label)
	report["moving_fraction"] = moving_ms / maxf(total, 1.0)
	report["longest_stop_ms"] = longest_stop_ms
	report["motion_speed_threshold_px_s"] = 5.0
	var focus_fraction := focused_frames / float(maxi(samples.size(), 1))
	var focus_valid := DisplayServer.get_name() == "headless" or focus_fraction >= 0.90
	report["window_focus_fraction"] = focus_fraction
	report["window_focus_transitions"] = focus_transitions
	report["window_focus_valid"] = focus_valid
	var valid_motion := _sample_kind(label) != "driving" or (travelled_px >= 300.0 and moving_ms >= total * 0.70 and longest_stop_ms < 5000.0)
	report["valid_motion"] = valid_motion
	report["subject_end"] = _sample_subject_state(car)
	report["time_of_day_min"] = hour_min
	report["debug_build"] = OS.is_debug_build()
	report["executable"] = OS.get_executable_path()
	report["time_of_day_max"] = hour_max
	report["weather_states"] = weather_states
	report["stall_threshold_ms"] = _stall_threshold_ms
	report["stall_count"] = stall_count
	report["stall_traces_written"] = stall_traces
	report["stall_trace_path"] = stall_path
	report["stall_event_trace_enabled"] = _trace_stall_events
	if is_instance_valid(_scenario_world): report["is_dark"] = _scenario_world.weather.is_dark
	if is_instance_valid(_scenario_world):
		var stream := _scenario_world.get_node_or_null("ContinuousWorld")
		if stream != null: report["streaming"] = stream.get_streaming_stats()
	summary.store_string(JSON.stringify(report, "\t"))
	summary.close()
	print("FRAME_STABILITY ", JSON.stringify(report))
	if not valid_motion:
		_sample_failed = true
		push_error("Driving benchmark failed motion coverage (distance >= 300 px, moving >= 70%, stop < 5 s); not valid driving evidence")
	if not focus_valid:
		_sample_failed = true
		push_error("Rendered benchmark window was not focused for at least 90% of the sample; GPU clocks and frame pacing are not comparable evidence")

func _sample_kind(label: String) -> String:
	return "driving" if label == "driving" else label

func _sample_subject_state(subject: Node2D) -> Dictionary:
	var state := {
		"path": str(subject.get_path()),
		"position": str(subject.global_position),
		"rotation": subject.global_rotation,
		"paused": paused,
		"can_process": subject.can_process(),
	}
	if subject is CharacterBody2D:
		state["velocity"] = str(subject.velocity)
		state["speed"] = subject.velocity.length()
	return state

func _frame_metrics_snapshot(presentation_budget: Node = null, known: Dictionary = {}) -> Dictionary:
	if presentation_budget == null:
		presentation_budget = root.get_node_or_null("PresentationBudget")
	var presentation_stats: Dictionary = presentation_budget.get("_stats") if presentation_budget != null else {}
	var vehicle_cache: Dictionary = VEHICLE_GEOMETRY_CACHE.telemetry()
	return {
		"object_count": known.get("object_count", Performance.get_monitor(Performance.OBJECT_COUNT)),
		"node_count": known.get("node_count", Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"resource_count": known.get("resource_count", Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)),
		"video_mem_mb": known.get("video_mem_mb", Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0),
		"physics_active": known.get("physics_active", Performance.get_monitor(Performance.PHYSICS_2D_ACTIVE_OBJECTS)),
		"physics_pairs": known.get("physics_pairs", Performance.get_monitor(Performance.PHYSICS_2D_COLLISION_PAIRS)),
		"draw_calls": known.get("draw_calls", Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		"presentation_pending": int(presentation_budget.pending.size()) if presentation_budget != null else 0,
		"presentation_requests": int(presentation_stats.get("requests", 0)),
		"presentation_builds": int(presentation_stats.get("builds", 0)),
		"presentation_cancelled": int(presentation_stats.get("cancelled", 0)),
		"presentation_over_budget": int(presentation_stats.get("over_budget_builds", 0)),
		"presentation_max_build_usec": int(presentation_stats.get("max_build_usec", 0)),
		"vehicle_cache_hits": int(vehicle_cache.get("hits", 0)),
		"vehicle_cache_misses": int(vehicle_cache.get("misses", 0)),
		"vehicle_cache_captures": int(vehicle_cache.get("captures", 0)),
		"vehicle_cache_restore_usec": int(vehicle_cache.get("restore_usec", 0)),
		"vehicle_cache_capture_usec": int(vehicle_cache.get("capture_usec", 0)),
		"vehicle_cache_cold_builds": int(vehicle_cache.get("cold_builds", 0)),
		"vehicle_cache_cold_build_usec": int(vehicle_cache.get("cold_build_usec", 0)),
		"tree_event_serial": _tree_event_serial,
	}

func _numeric_delta(previous: Dictionary, current: Dictionary) -> Dictionary:
	var delta := {}
	for key in current:
		if current[key] is int or current[key] is float:
			delta[key] = current[key] - previous.get(key, current[key])
	return delta

func _stall_details(label: String, frame_index: int, elapsed_ms: float, frame_ms: float, physics_steps: int, subject: Node2D, previous: Dictionary, current: Dictionary) -> Dictionary:
	var details := {
		"scenario": label,
		"frame_index": frame_index,
		"elapsed_ms": elapsed_ms,
		"frame_ms": frame_ms,
		"physics_steps": physics_steps,
		"process_ms": Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		"physics_ms": Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
		"render_cpu_ms": RenderingServer.viewport_get_measured_render_time_cpu(root.get_viewport_rid()),
		"render_gpu_ms": RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()),
		"subject": _sample_subject_state(subject),
		"metrics": current,
		"delta": _numeric_delta(previous, current),
		"groups": _stall_group_counts(),
		"tree_events_since_previous_frame": _tree_events_after(int(previous.get("tree_event_serial", 0))),
		"vehicle_geometry_cache": VEHICLE_GEOMETRY_CACHE.telemetry(),
		"static_memory_mb": OS.get_static_memory_usage() / 1048576.0,
	}
	var presentation_budget := root.get_node_or_null("PresentationBudget")
	if presentation_budget != null:
		details["presentation"] = presentation_budget.get_stats()
		details["presentation_pending_sample"] = _pending_presentation_sample(presentation_budget, subject.global_position)
	if is_instance_valid(_scenario_world):
		var stream := _scenario_world.get_node_or_null("ContinuousWorld")
		if stream != null:
			details["streaming"] = stream.get_streaming_stats()
	var wanted := root.get_node_or_null("WantedManager")
	if wanted != null:
		details["wanted"] = {"stars": wanted.current_stars, "crime_points": wanted.crime_points}
	print("FRAME_STALL ", JSON.stringify(details))
	return details

func _stall_group_counts() -> Dictionary:
	var counts := {}
	for group in [
		"modern_traffic", "vehicle", "motorcycle", "pedestrian", "authored_sidewalk_pedestrian",
		"emergency_vehicle", "police_officer", "paramedic", "firefighter", "medical_observer",
		"ground_blood", "explosives", "weapon_effects", "shot_contacts", "person_fire_visuals",
		"explosion_visuals", "explosion_remains", "explosion_scorches",
	]:
		counts[group] = get_nodes_in_group(group).size()
	return counts

func _pending_presentation_sample(presentation_budget: Node, focus: Vector2) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var pending_value: Variant = presentation_budget.get("pending")
	if not pending_value is Array:
		return result
	for candidate in pending_value:
		if result.size() >= 12:
			break
		if not is_instance_valid(candidate) or not candidate is Node2D:
			continue
		var actor := candidate as Node2D
		result.append({
			"path": str(actor.get_path()),
			"script": String(actor.get_script().resource_path) if actor.get_script() != null else "",
			"distance": actor.global_position.distance_to(focus),
			"visible": actor.is_visible_in_tree(),
			"sleeping": actor.get_meta("proximity_sleeping", false),
		})
	return result

func _record_tree_event(node: Node, operation: String) -> void:
	_tree_event_serial += 1
	var script_path := ""
	if is_instance_valid(node) and node.get_script() != null:
		script_path = String(node.get_script().resource_path)
	var event := {
		"serial": _tree_event_serial,
		"time_usec": Time.get_ticks_usec(),
		"operation": operation,
		"name": String(node.name) if is_instance_valid(node) else "",
		"class": node.get_class() if is_instance_valid(node) else "",
		"script": script_path,
		"parent": str(node.get_parent().get_path()) if is_instance_valid(node) and node.get_parent() != null else "",
	}
	if is_instance_valid(node) and node is Node2D:
		event["position"] = str((node as Node2D).global_position)
	_recent_tree_events.append(event)
	if _recent_tree_events.size() > 192:
		_recent_tree_events.pop_front()

func _tree_events_after(serial: int) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	for event in _recent_tree_events:
		if int(event.get("serial", 0)) > serial:
			events.append(event.duplicate())
	return events
