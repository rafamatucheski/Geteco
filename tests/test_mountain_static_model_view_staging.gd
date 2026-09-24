extends SceneTree

const VIEW := preload("res://world/mountain_pass/MountainStaticModelView.gd")
const WINTER_MODEL := preload("res://world/mountain_pass/transit/MountainWinterDressing3D.gd")
const RUNTIME_WORK := preload("res://systems/RuntimeWorkScheduler.gd")
const VIEW_COUNT := 6
const FRAME_BUDGET_USEC := 16667
const RENDER_SIZE := Vector2i(960, 800)

var failures: Array[String] = []
var _notifier_entries := 0
var _probe_mesh: BoxMesh
var _diagnostic_no_shadows := false
var _diagnostic_half_scale := false

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("STATIC_VIEW_STAGING: " + message)

func _snapshot() -> Dictionary:
	return {
		"objects": int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		"resources": int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)),
		"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"orphans": int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)),
	}

func _make_visible_probe(view: Node2D, index: int) -> void:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "VisibilityProbe%d" % index
	if _probe_mesh == null:
		_probe_mesh = BoxMesh.new()
		_probe_mesh.size = Vector3(2.4, 3.2, 2.0)
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(0.92, 0.32, 0.08, 1.0)
		material.roughness = 0.72
		_probe_mesh.material = material
	mesh_instance.mesh = _probe_mesh
	mesh_instance.position = Vector3(0, 1.6, 0)
	view.model.add_child(mesh_instance)

func _attach_notifier(view: Node2D) -> void:
	var notifier := VisibleOnScreenNotifier2D.new()
	notifier.name = "StaticViewVisibility"
	notifier.rect = Rect2(-220, -190, 440, 380)
	notifier.screen_entered.connect(func(): _notifier_entries += 1)
	view.add_child(notifier)

func _has_visible_pixels(image: Image) -> bool:
	if image == null or image.is_empty() or image.get_size() != RENDER_SIZE:
		return false
	var step_x := maxi(1, image.get_width() / 48)
	var step_y := maxi(1, image.get_height() / 40)
	for y in range(0, image.get_height(), step_y):
		for x in range(0, image.get_width(), step_x):
			if image.get_pixel(x, y).a > 0.05:
				return true
	return false

func _has_global_tree_callback(view: Node) -> bool:
	for signal_value in [node_added, node_removed]:
		for connection_variant in signal_value.get_connections():
			var connection: Dictionary = connection_variant
			var callable: Callable = connection.get("callable", Callable())
			if callable.is_valid() and callable.get_object() == view:
				return true
	return false

func _build_six(render_probes: bool) -> Dictionary:
	var holder := Node2D.new()
	holder.name = "StaticViewBatch"
	root.add_child(holder)
	var views: Array[Node2D] = []
	var call_usec: Array[int] = []
	var frame_usec: Array[int] = []
	var build_profiles: Array[Dictionary] = []
	var internal_peak_usec := 0
	for index in VIEW_COUNT:
		var view := VIEW.new()
		view.name = "WinterStaticView%d" % index
		if not render_probes:
			view.set_background_static_preparation_enabled(false)
		# Streamed static views settle outside the camera before the player reaches
		# them. Keeping the fixture distant exercises that production contract and
		# prevents background GPU preparation from running near the player.
		view.position = Vector2(5000 + (index % 3) * 360, 5000 + (index / 3) * 340)
		holder.add_child(view)
		var started := Time.get_ticks_usec()
		view.build_view(WINTER_MODEL, 26.0, 18.0, Vector3(0, 1, 0), Vector3(0, 24, 20), RENDER_SIZE)
		var elapsed := Time.get_ticks_usec() - started
		call_usec.append(elapsed)
		if _diagnostic_no_shadows:
			for child in view.viewport_3d.get_children():
				if child is DirectionalLight3D:
					child.shadow_enabled = false
		if _diagnostic_half_scale:
			view.viewport_3d.scaling_3d_scale = 0.5
		# This is what streamed winter dressing does immediately after build_view.
		view.viewport_3d.render_target_update_mode = SubViewport.UPDATE_DISABLED
		if render_probes:
			_make_visible_probe(view, index)
		if view.has_method("get_build_profile"):
			var profile: Dictionary = view.get_build_profile()
			build_profiles.append(profile)
			for value in profile.values():
				if value is int or value is float:
					internal_peak_usec = maxi(internal_peak_usec, int(value))
		var before_frame := Time.get_ticks_usec()
		await process_frame
		frame_usec.append(Time.get_ticks_usec() - before_frame)
		views.append(view)
	return {
		"holder": holder,
		"views": views,
		"call_usec": call_usec,
		"frame_usec": frame_usec,
		"build_profiles": build_profiles,
		"internal_peak_usec": internal_peak_usec,
	}

func _await_background_preparation(views: Array[Node2D]) -> Dictionary:
	var frame_usec: Array[int] = []
	var completed := 0
	for frame_index in 128:
		var started := Time.get_ticks_usec()
		await process_frame
		frame_usec.append(Time.get_ticks_usec() - started)
		completed = 0
		for view in views:
			if bool(view.get_render_profile().get("prepared_for_first_presentation", false)):
				completed += 1
		if completed == views.size():
			break
	var profiles: Array[Dictionary] = []
	var claimed_frames: Dictionary = {}
	for view in views:
		var profile: Dictionary = view.get_render_profile()
		profiles.append(profile)
		for key in ["prepare_bootstrap_frame", "prepare_target_frame", "prepare_full_frame"]:
			var claimed := int(profile.get(key, -1))
			_check(claimed >= 0, "%s was not recorded for %s" % [key, view.name])
			_check(not claimed_frames.has(claimed),
				"two static GPU preparation phases shared frame %d" % claimed)
			claimed_frames[claimed] = true
		var unit_frames: Array = profile.get("prepare_unit_frames", [])
		_check(not unit_frames.is_empty(), "unit warmup phase was not recorded for %s" % view.name)
		for unit_frame_value in unit_frames:
			var unit_frame := int(unit_frame_value)
			_check(unit_frame >= 0, "invalid unit warmup frame for %s" % view.name)
			_check(not claimed_frames.has(unit_frame),
				"two static GPU preparation slices shared frame %d" % unit_frame)
			claimed_frames[unit_frame] = true
		_check(int(profile.get("tracked_mutation_nodes", -1)) == 0,
			"local mutation tracking must disconnect after preparation for %s" % view.name)
	_check(completed == views.size(),
		"all distant views must finish bounded background preparation; got %d" % completed)
	return {
		"frame_usec": frame_usec,
		"profiles": profiles,
		"claimed_frames": claimed_frames.keys(),
	}

func _activate_and_verify(views: Array[Node2D]) -> Dictionary:
	var activation_usec: Array[int] = []
	var readback_usec: Array[int] = []
	var visible_images := 0
	for index in views.size():
		var view := views[index]
		view.position = Vector2(120 + (index % 3) * 300, 130 + (index / 3) * 180)
		_attach_notifier(view)
		var projected: Vector2 = view.project_floor(Vector2(1.75, -2.25))
		var round_trip: Vector2 = view.unproject_floor(view.to_global(projected))
		_check(round_trip.distance_to(Vector2(1.75, -2.25)) < 0.02,
			"view %d projection round-trip drifted: %s" % [index, round_trip])
		# Request all six in the same frame, exactly like several visibility
		# notifiers becoming visible together at a streaming boundary.
		view.viewport_3d.render_target_update_mode = SubViewport.UPDATE_ONCE
	var activation_frames := 0
	var completed := 0
	while activation_frames < 4:
		var activation_started := Time.get_ticks_usec()
		await process_frame
		activation_usec.append(Time.get_ticks_usec() - activation_started)
		activation_frames += 1
		completed = 0
		for view in views:
			if bool(view.get_render_profile().get("first_presentation_reused", false)):
				completed += 1
		if completed == VIEW_COUNT:
			break
	_check(activation_frames <= 2,
		"prepared first presentation should not wake six render targets")
	_check(completed == VIEW_COUNT,
		"all queued static views must report render completion; got %d" % completed)
	for notifier_frame in 24:
		if _notifier_entries == VIEW_COUNT:
			break
		# VisibleOnScreenNotifier2D is resolved by the render pass, after the
		# SceneTree process signal used by the timing loop above.
		await RenderingServer.frame_post_draw
		await process_frame
	var render_profiles: Array[Dictionary] = []
	for index in views.size():
		var view := views[index]
		render_profiles.append(view.get_render_profile())
		var readback_started := Time.get_ticks_usec()
		var image: Image = view.viewport_3d.get_texture().get_image()
		readback_usec.append(Time.get_ticks_usec() - readback_started)
		if _has_visible_pixels(image):
			visible_images += 1
		view.viewport_3d.render_target_update_mode = SubViewport.UPDATE_DISABLED
	return {
		"activation_usec": activation_usec,
		"activation_frames": activation_frames,
		"render_profiles": render_profiles,
		"readback_usec": readback_usec,
		"visible_images": visible_images,
	}

func _free_cycle(holder: Node, views: Array[Node2D]) -> Dictionary:
	var tracked: Array[WeakRef] = []
	for view in views:
		tracked.append(weakref(view))
	holder.queue_free()
	for frame in 8:
		await process_frame
	var released := 0
	for reference in tracked:
		if reference.get_ref() == null:
			released += 1
	var result := _snapshot()
	result["released_views"] = released
	return result

func _verify_near_guard() -> Dictionary:
	var holder := Node2D.new()
	holder.name = "NearPreparationGuard"
	root.add_child(holder)
	var view := VIEW.new()
	view.position = Vector2(240, 180)
	holder.add_child(view)
	view.build_view(WINTER_MODEL, 26.0, 18.0, Vector3(0, 1, 0), Vector3(0, 24, 20), RENDER_SIZE)
	view.viewport_3d.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_make_visible_probe(view, 99)
	for frame in 20:
		await process_frame
	var guarded: Dictionary = view.get_render_profile()
	_check(not bool(guarded.get("prepared_for_first_presentation", false)),
		"automatic GPU preparation must stay disabled near the screen")
	_check(int(guarded.get("generation", -1)) == 0,
		"near guard must not render speculatively")
	_check(int(guarded.get("background_deferred_near_frames", 0)) > 0,
		"near guard deferral must be visible in telemetry")
	view.viewport_3d.render_target_update_mode = SubViewport.UPDATE_ONCE
	for frame in 6:
		await process_frame
		if int(view.get_render_profile().get("generation", 0)) >= 1:
			break
	var presented: Dictionary = view.get_render_profile()
	_check(int(presented.get("generation", 0)) == 1,
		"a real near-screen request must still render")
	var image: Image = view.viewport_3d.get_texture().get_image()
	_check(_has_visible_pixels(image), "near-screen requested render must be visible")
	holder.queue_free()
	for frame in 6:
		await process_frame
	return {"guarded": guarded, "presented": presented}

func _max_int(values: Array[int]) -> int:
	var result := 0
	for value in values:
		result = maxi(result, value)
	return result

func _run() -> void:
	_diagnostic_no_shadows = "--diagnostic-no-shadows" in OS.get_cmdline_user_args()
	_diagnostic_half_scale = "--diagnostic-half-scale" in OS.get_cmdline_user_args()
	# Diagnostic-only: expose real work instead of measuring the configured
	# 60 FPS limiter's intentional wait. The product configuration is untouched.
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	RUNTIME_WORK.reset_for_tests()
	VIEW.reset_static_render_telemetry_for_tests()
	for frame in 5:
		await process_frame
	var before := _snapshot()
	var first := await _build_six(true)
	for view in first.views:
		_check(not _has_global_tree_callback(view),
			"static view must not subscribe to SceneTree node_added/node_removed")
	var preparation := await _await_background_preparation(first.views)
	var activation := await _activate_and_verify(first.views)
	var structural_peak := maxi(_max_int(first.call_usec), _max_int(first.frame_usec))
	var preparation_peak := _max_int(preparation.frame_usec)
	var activation_peak := _max_int(activation.activation_usec)
	_check(structural_peak < FRAME_BUDGET_USEC,
		"six-view structural peak exceeds 60 FPS budget: %d usec" % structural_peak)
	_check(preparation_peak < FRAME_BUDGET_USEC,
		"serialized background preparation exceeds 60 FPS budget: %d usec" % preparation_peak)
	_check(activation_peak < FRAME_BUDGET_USEC,
		"single-view activation peak exceeds 60 FPS budget: %d usec" % activation_peak)
	_check(activation.visible_images == VIEW_COUNT,
		"activated views must all produce a non-empty 960x800 image")
	_check(_notifier_entries == VIEW_COUNT,
		"all six on-screen notifiers must enter; got %d" % _notifier_entries)
	var generation_before := int(first.views[0].get_render_profile().generation)
	first.views[0].viewport_3d.render_target_update_mode = SubViewport.UPDATE_ONCE
	for frame in 5:
		await process_frame
		if int(first.views[0].get_render_profile().generation) == generation_before + 1:
			break
	_check(int(first.views[0].get_render_profile().generation) == generation_before + 1,
		"a completed static view must accept a later notifier reactivation")
	first.views[1].viewport_3d.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	await process_frame
	_check(first.views[1].viewport_3d.render_target_update_mode == SubViewport.UPDATE_ALWAYS,
		"dynamic UPDATE_ALWAYS requests must bypass the static cadence")
	first.views[1].viewport_3d.render_target_update_mode = SubViewport.UPDATE_DISABLED
	var after_first := await _free_cycle(first.holder, first.views)
	_check(after_first.released_views == VIEW_COUNT,
		"all first-cycle views must be released; got %d" % after_first.released_views)

	# A second identical lifecycle distinguishes a bounded shared cache from a
	# per-view leak: retained counts must not grow after the cache is warm.
	var second := await _build_six(false)
	var after_second := await _free_cycle(second.holder, second.views)
	_check(after_second.released_views == VIEW_COUNT,
		"all second-cycle views must be released; got %d" % after_second.released_views)
	_check(after_second.nodes <= after_first.nodes,
		"node count grows across identical cycles: %s -> %s" % [after_first.nodes, after_second.nodes])
	_check(after_second.orphans <= after_first.orphans,
		"orphan count grows across identical cycles: %s -> %s" % [after_first.orphans, after_second.orphans])
	_check(after_second.resources <= after_first.resources,
		"resource count grows across identical cycles: %s -> %s" % [after_first.resources, after_second.resources])
	var near_guard := await _verify_near_guard()

	var render_telemetry: Dictionary = VIEW.static_render_telemetry_snapshot()
	_check(int(render_telemetry.get("pending", -1)) == 0,
		"static render scheduler queue must drain")
	_check(int(render_telemetry.get("in_flight", -1)) == 0,
		"static render preparation must not remain in flight")
	_check(int(render_telemetry.get("unit_slices_total", 0)) >= VIEW_COUNT,
		"each staged view must warm at least one visual unit")
	var scheduler_over_budget := 0
	var adjacent_samples := 0
	for record_value in render_telemetry.get("records", []):
		var record := record_value as Dictionary
		if int(record.get("actual_usec", 0)) > RUNTIME_WORK.FRAME_BUDGET_USEC:
			scheduler_over_budget += 1
		if int(record.get("adjacent_frame_usec", 0)) > 0:
			adjacent_samples += 1
	_check(scheduler_over_budget == 0,
		"static render issue slices must stay inside the 6 ms scheduler budget")
	_check(adjacent_samples > 0,
		"render telemetry must preserve adjacent-frame latency separately")
	print("MOUNTAIN_STATIC_VIEW_PROFILE structural_call_usec=", first.call_usec,
		" diagnostic_no_shadows=", _diagnostic_no_shadows,
		" diagnostic_half_scale=", _diagnostic_half_scale,
		" structural_frame_usec=", first.frame_usec,
		" build_profiles=", first.build_profiles,
		" internal_peak_usec=", first.internal_peak_usec,
		" preparation_frame_usec=", preparation.frame_usec,
		" preparation_profiles=", preparation.profiles,
		" preparation_claimed_frames=", preparation.claimed_frames,
		" preparation_peak_usec=", preparation_peak,
		" activation_usec=", activation.activation_usec,
		" activation_frames=", activation.activation_frames,
		" render_profiles=", activation.render_profiles,
		" readback_usec=", activation.readback_usec,
		" visible_images=", activation.visible_images,
		" notifier_entries=", _notifier_entries,
		" before=", before,
		" after_first=", after_first,
		" after_second=", after_second,
		" near_guard=", near_guard,
		" render_telemetry=", render_telemetry,
		" failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
