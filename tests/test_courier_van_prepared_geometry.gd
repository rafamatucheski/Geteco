extends SceneTree

const MODEL_PATH := "res://prototypes/living_cast/models/CourierVanModel.gd"
const RESOURCE_PATH := "res://prototypes/living_cast/models/CourierVanPreparedGeometry.scn"
const CACHE := preload("res://cars/VehicleGeometryCache.gd")
const SCHEDULER := preload("res://systems/RuntimeWorkScheduler.gd")
const GAME_LOADING := preload("res://ui/GameLoading.gd")
const CLEARANCE := preload("res://prototypes/living_cast/VehicleWheelClearance.gd")
const WHEEL_RIG := preload("res://prototypes/living_cast/VehicleWheelRig.gd")
const BATCHER := preload("res://cars/VehicleMeshBatcher.gd")
const SURFACE_KEYS_META := &"courier_van_surface_material_keys"
const EXPECTED_SIGNATURE := 4069370056
const EXPECTED_MESHES := 19
const EXPECTED_SURFACES := 31
const EXPECTED_TRIANGLES := 24488
const STAGE_BUDGET_USEC := 6000
const ADJACENT_FRAME_BUDGET_USEC := 16670
const MAX_STAGE_STEPS := 48

var failures: Array[String] = []

class LoadingScreenProbe extends Control:
	var stages: Array[Dictionary] = []

	func set_stage(progress: float, label: String) -> void:
		stages.append({"progress": progress, "label": label})


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_reset_caches()
	var loading_bootstrap: Dictionary = {}
	var loading_mode := OS.get_cmdline_user_args().has("--loading-bootstrap")
	if loading_mode:
		loading_bootstrap = await _exercise_loading_bootstrap()
		_clear_courier_templates_only()
		var bootstrap_after_reset := CACHE.vehicle_graphics_bootstrap_snapshot()
		loading_bootstrap["courier_template_cleared_after_loading"] = not CACHE._models.has(MODEL_PATH) and not CACHE._prepared.has(MODEL_PATH)
		loading_bootstrap["other_harbor_templates_retained"] = not CACHE._models.is_empty()
		loading_bootstrap["renderer_pipelines_retained"] = bool(bootstrap_after_reset.get("ready", false))
		loading_bootstrap["template_reset_scope"] = "Courier template only; renderer pipelines and other Harbor templates remain resident to model a future regional Courier cache miss"
		_check(bool(loading_bootstrap.courier_template_cleared_after_loading), "future-region fixture removes only the Courier template after loading")
		_check(bool(loading_bootstrap.other_harbor_templates_retained), "future-region fixture retains other Harbor templates")
		_check(bool(loading_bootstrap.renderer_pipelines_retained), "future-region fixture retains loading-compiled renderer pipelines")
	var cancellation := await _exercise_cancelled_partial_attach()
	if loading_mode:
		SCHEDULER.reset_for_tests()
		_clear_courier_templates_only()
	else:
		_reset_caches()
	var idle_baseline := await _measure_idle_render_baseline()
	var regional := await _exercise_cold_regional_job(idle_baseline)
	var functional := await _exercise_live_contract()
	var fallback := _exercise_procedural_fallback()
	print("COURIER_VAN_PREPARED_CONTRACT ", JSON.stringify({
		"renderer": RenderingServer.get_current_rendering_method(),
		"adapter": RenderingServer.get_video_adapter_name() if DisplayServer.get_name() != "headless" else "not_measured",
		"stage_budget_usec": STAGE_BUDGET_USEC,
		"mode": "loading_bootstrap" if loading_mode else "direct_cold_diagnostic",
		"loading_bootstrap": loading_bootstrap,
		"idle_render_baseline": idle_baseline,
		"cancellation": cancellation,
		"regional": regional,
		"functional": functional,
		"fallback": fallback,
		"failures": failures,
	}))
	if not failures.is_empty():
		for failure in failures:
			push_error(failure)
		quit(1)
		return
	quit(0)


func _exercise_loading_bootstrap() -> Dictionary:
	CACHE.reset_vehicle_graphics_bootstrap_for_tests()
	var loading := GAME_LOADING.new()
	root.add_child(loading)
	var screen_probe := LoadingScreenProbe.new()
	screen_probe.visible = true
	loading.add_child(screen_probe)
	loading.screen = screen_probe
	loading.active = true
	await process_frame
	var was_paused := paused
	paused = true
	var result: Dictionary = await loading._prepare_vehicle_models()
	var material_bootstrap: Dictionary = result.get("material_bootstrap", {}) as Dictionary
	var harbor: Dictionary = result.get("harbor", {}) as Dictionary
	_check(paused, "GameLoading keeps gameplay paused until vehicle material/bootstrap and Harbor prewarm finish")
	_check(bool(result.get("world_paused", false)), "GameLoading telemetry records paused controls during vehicle prewarm")
	_check(bool(result.get("loading_visible", false)), "GameLoading keeps a visible loading presentation through vehicle prewarm")
	_check(not screen_probe.stages.is_empty(), "GameLoading reports the vehicle preparation stage on the visible screen")
	_check(bool(material_bootstrap.get("ready", false)), "canonical vehicle material variants render during GameLoading")
	_check(String(material_bootstrap.get("charged_to", "")) == "loading", "vehicle shader/pipeline compilation is charged to loading")
	_check(bool(material_bootstrap.get("temporary_viewport_released", false)), "vehicle material bootstrap releases its temporary viewport")
	_check(bool(harbor.get("completed", false)), "GameLoading completes the real Harbor vehicle prewarm")
	_check(CACHE._models.has(MODEL_PATH) and CACHE._prepared.has(MODEL_PATH), "real Harbor prewarm includes CourierVan before controls unlock")
	result["harbor_cached_models_before_template_reset"] = CACHE._models.size()
	result["courier_cached_before_template_reset"] = CACHE._models.has(MODEL_PATH) and CACHE._prepared.has(MODEL_PATH)
	result["fixture_scope"] = "visible_game_loading_vehicle_phase"
	result["fixture_loading_active"] = loading.active
	result["fixture_screen_visible"] = is_instance_valid(loading.screen) and loading.screen.visible
	paused = was_paused
	loading.active = false
	loading.free()
	await process_frame
	return result


func _measure_idle_render_baseline() -> Dictionary:
	const WARMUP_FRAMES := 6
	const SAMPLE_FRAMES := 60
	var viewport := SubViewport.new()
	viewport.name = "CourierIdleRenderBaseline"
	viewport.size = Vector2i(64, 64)
	viewport.own_world_3d = true
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var camera := Camera3D.new()
	viewport.add_child(camera)
	camera.look_at_from_position(Vector3(0.0, 0.0, 2.5), Vector3.ZERO, Vector3.UP)
	var probe := MeshInstance3D.new()
	probe.mesh = BoxMesh.new()
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("d8dde3")
	material.roughness = 0.9
	probe.material_override = material
	viewport.add_child(probe)
	var previous_usec := Time.get_ticks_usec()
	for _warmup in WARMUP_FRAMES:
		await process_frame
		previous_usec = Time.get_ticks_usec()
	var samples: Array[int] = []
	for _sample in SAMPLE_FRAMES:
		await process_frame
		var now := Time.get_ticks_usec()
		samples.append(maxi(0, now - previous_usec))
		previous_usec = now
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	viewport.free()
	await process_frame
	return _timing_summary(samples)


func _exercise_cold_regional_job(idle_baseline: Dictionary) -> Dictionary:
	_check(ResourceLoader.exists(RESOURCE_PATH, "PackedScene"), "CourierVan prepared scene exists")
	var session := CACHE.begin_region_session(self, &"emergency")
	var job := _courier_job(session)
	_check(not job.is_empty(), "Emergency region exposes CourierVan")
	if job.is_empty():
		CACHE.finish_region_session(session, true)
		return {"error": "job_missing"}
	var resource_state := CACHE.request_region_job_resource(session, job)
	var wait_frames := 0
	while String(resource_state.get("state", "")) == "loading" and wait_frames < 600:
		await process_frame
		wait_frames += 1
		resource_state = CACHE.poll_region_job_resource(session, job)
	_check(not resource_state.has("error") and resource_state.get("resource") is Script, "CourierVan threaded Script and prepared dependency load")
	if resource_state.has("error") or not resource_state.get("resource") is Script:
		CACHE.finish_region_session(session, true)
		return {"error": resource_state.get("error", "resource_load_failed")}

	var rows: Array[Dictionary] = []
	var execution: Dictionary = {"complete": false}
	for _step in MAX_STAGE_STEPS:
		execution = await _advance_with_ticket(session, job, resource_state.resource as Resource)
		var stage_detail: Dictionary = execution.get("stage_detail", {}) as Dictionary
		var row := {
			"stage": String(execution.get("stage", "")),
			"actual_usec": int(execution.get("actual_usec", 0)),
			"over_budget": bool(execution.get("over_budget", false)),
			"ticket_id": int(execution.get("ticket_id", -1)),
			"ticket_frame": int(execution.get("ticket_frame", -1)),
			"ticket_granted_usec": int(execution.get("ticket_granted_usec", 0)),
			"slice_index": int(stage_detail.get("slice_index", -2)),
			"slice_count": int(stage_detail.get("slice_count", 0)),
			"unit_name": String(stage_detail.get("unit_name", "")),
		}
		rows.append(row)
		_check(not execution.has("error"), "CourierVan regional stage succeeds: %s" % row.stage)
		_check(int(row.actual_usec) <= STAGE_BUDGET_USEC, "CourierVan cold stage %s stays within 6 ms, got %.3f ms" % [row.stage, int(row.actual_usec) / 1000.0])
		if execution.has("error") or bool(execution.get("complete", false)):
			break
	_check(bool(execution.get("complete", false)), "CourierVan direct prepared job reaches atomic commit")
	for row_index in rows.size() - 1:
		rows[row_index]["adjacent_frame_usec"] = maxi(
			0,
			int(rows[row_index + 1].get("ticket_granted_usec", 0)) - int(rows[row_index].get("ticket_granted_usec", 0))
		)
	if not rows.is_empty():
		rows[-1]["adjacent_frame_usec"] = 0
	var absolute_budget_breaches: Array[Dictionary] = []
	for row in rows:
		var adjacent_usec := int(row.get("adjacent_frame_usec", 0))
		if adjacent_usec <= 0:
			continue
		if adjacent_usec > ADJACENT_FRAME_BUDGET_USEC:
			absolute_budget_breaches.append({
				"stage": String(row.get("stage", "")),
				"slice_index": int(row.get("slice_index", -1)),
				"unit_name": String(row.get("unit_name", "")),
				"actual_usec": int(row.get("actual_usec", 0)),
				"adjacent_frame_usec": adjacent_usec,
				"adjacent_frame_ms": adjacent_usec / 1000.0,
			})
	_check(bool(execution.get("preparation", {}).get("direct_prepared", false)), "CourierVan uses the direct prepared-resource path")
	_check(not _stage_names(rows).has("procedural_build"), "CourierVan regional prewarm performs no procedural build")
	_check(not _stage_names(rows).has("wheel_mount"), "CourierVan prepared resource defers live wheel pivots to restore")
	_check(not _stage_names(rows).has("batching"), "CourierVan regional prewarm performs no runtime batching")
	_check(not _stage_names(rows).has("capture_pack"), "CourierVan direct publication performs no second geometry pack")
	_check(CACHE._models.has(MODEL_PATH) and CACHE._prepared.has(MODEL_PATH), "CourierVan publishes cache scene and prepared marker together")
	if CACHE._models.has(MODEL_PATH):
		_check(bool(CACHE._models[MODEL_PATH].get("direct_prepared_resource", false)), "CourierVan cache entry records direct prepared publication")
	var preparation: Dictionary = execution.get("preparation", {})
	_check((preparation.get("unsafe_reference_properties", PackedStringArray()) as PackedStringArray).is_empty(), "CourierVan prepared publication has no live Node references")
	var report := CACHE.finish_region_session(session, false)
	var courier_over_budget: Array = []
	for entry in report.get("over_budget_stages", []):
		if String(entry.get("path", "")) == MODEL_PATH:
			courier_over_budget.append(entry)
	_check(courier_over_budget.is_empty(), "CourierVan regional report has no hidden over-budget stage")
	var attach_slices := _stage_rows(rows, "prepared_scene_attach_slice")
	_check(attach_slices.size() == EXPECTED_MESHES, "CourierVan attaches exactly one prepared group in each of 19 slices")
	var ticket_ids := {}
	var previous_frame := -1
	for slice in attach_slices:
		var ticket_id := int(slice.get("ticket_id", -1))
		var ticket_frame := int(slice.get("ticket_frame", -1))
		_check(ticket_id > 0 and not ticket_ids.has(ticket_id), "each CourierVan attach slice owns a unique scheduler ticket")
		ticket_ids[ticket_id] = true
		_check(ticket_frame > previous_frame, "CourierVan attach slices execute on strictly increasing reserved frames")
		previous_frame = ticket_frame
	var reported_slices: Array = []
	for step_value in report.get("stage_steps", []):
		var step := step_value as Dictionary
		if String(step.get("path", "")) == MODEL_PATH and String(step.get("stage", "")) == "prepared_scene_attach_slice":
			reported_slices.append(step)
	_check(reported_slices.size() == EXPECTED_MESHES, "regional telemetry records every CourierVan attach slice")
	for slice in reported_slices:
		_check(int(slice.get("ticket_id", -1)) > 0 and int(slice.get("frame", -1)) >= 0, "attach slice telemetry includes scheduler ticket and frame")
	var max_attach_slice: Dictionary = {}
	var max_adjacent_frame_usec := 0
	var job_adjacent_samples: Array[int] = []
	var attach_active_samples: Array[int] = []
	var attach_adjacent_samples: Array[int] = []
	for row in rows:
		var adjacent_usec := int(row.get("adjacent_frame_usec", 0))
		if adjacent_usec > 0:
			job_adjacent_samples.append(adjacent_usec)
	for slice in attach_slices:
		if max_attach_slice.is_empty() or int(slice.get("actual_usec", 0)) > int(max_attach_slice.get("actual_usec", 0)):
			max_attach_slice = slice.duplicate(true)
		var adjacent_usec := int(slice.get("adjacent_frame_usec", 0))
		max_adjacent_frame_usec = maxi(max_adjacent_frame_usec, adjacent_usec)
		if adjacent_usec > 0:
			attach_active_samples.append(int(slice.get("actual_usec", 0)))
			attach_adjacent_samples.append(adjacent_usec)
	var job_timing := _timing_summary(job_adjacent_samples)
	var attach_timing := _timing_summary(attach_adjacent_samples)
	var baseline_p95_usec := int(idle_baseline.get("p95_usec", 0))
	_check(int(idle_baseline.get("count", 0)) > 0, "CourierVan delta attribution has a rendered idle baseline")
	var job_delta_p95_usec := maxi(0, int(job_timing.get("p95_usec", 0)) - baseline_p95_usec)
	# Compare maxima with the stable idle p95, not idle max: a single unrelated
	# idle outlier must never hide a Courier spike.
	var job_delta_max_usec := maxi(0, int(job_timing.get("max_usec", 0)) - baseline_p95_usec)
	var attach_delta_p95_usec := maxi(0, int(attach_timing.get("p95_usec", 0)) - baseline_p95_usec)
	var attach_delta_max_usec := maxi(0, int(attach_timing.get("max_usec", 0)) - baseline_p95_usec)
	_check(job_delta_p95_usec <= STAGE_BUDGET_USEC, "CourierVan job p95 frame delta over rendered idle stays within 6 ms, got %.3f ms" % [job_delta_p95_usec / 1000.0])
	_check(job_delta_max_usec <= STAGE_BUDGET_USEC, "CourierVan job max frame delta over rendered idle stays within 6 ms, got %.3f ms" % [job_delta_max_usec / 1000.0])
	_check(attach_delta_p95_usec <= STAGE_BUDGET_USEC, "CourierVan attach p95 frame delta over rendered idle stays within 6 ms, got %.3f ms" % [attach_delta_p95_usec / 1000.0])
	_check(attach_delta_max_usec <= STAGE_BUDGET_USEC, "CourierVan attach max frame delta over rendered idle stays within 6 ms, got %.3f ms" % [attach_delta_max_usec / 1000.0])
	# finish_region_session queues its private viewport; let that ownership
	# boundary settle so a passing isolated process exits with no leaked object.
	await process_frame
	await process_frame
	return {
		"wait_frames": wait_frames,
		"stages": rows,
		"max_stage_usec": _max_stage_usec(rows),
		"max_stage_ms": _max_stage_usec(rows) / 1000.0,
		"over_budget_stages": courier_over_budget,
		"attach_slices": attach_slices,
		"max_attach_slice": max_attach_slice,
		"max_adjacent_frame_usec": max_adjacent_frame_usec,
		"max_adjacent_frame_ms": max_adjacent_frame_usec / 1000.0,
		"idle_render_baseline": idle_baseline,
		"job_adjacent": job_timing,
		"job_delta_over_idle": {
			"p95_usec": job_delta_p95_usec,
			"p95_ms": job_delta_p95_usec / 1000.0,
			"max_usec": job_delta_max_usec,
			"max_ms": job_delta_max_usec / 1000.0,
		},
		"attach_adjacent": attach_timing,
		"attach_delta_over_idle": {
			"p95_usec": attach_delta_p95_usec,
			"p95_ms": attach_delta_p95_usec / 1000.0,
			"max_usec": attach_delta_max_usec,
			"max_ms": attach_delta_max_usec / 1000.0,
		},
		"attach_active_adjacent_correlation": _pearson_correlation(attach_active_samples, attach_adjacent_samples),
		"absolute_frame_budget_usec": ADJACENT_FRAME_BUDGET_USEC,
		"absolute_budget_breaches": absolute_budget_breaches,
		"absolute_route_approval_deferred": true,
		"direct_prepared": bool(preparation.get("direct_prepared", false)),
	}


func _exercise_cancelled_partial_attach() -> Dictionary:
	var session := CACHE.begin_region_session(self, &"emergency")
	var job := _courier_job(session)
	_check(not job.is_empty(), "Cancellation fixture exposes CourierVan")
	if job.is_empty():
		CACHE.finish_region_session(session, true)
		return {"error": "job_missing"}
	var resource_state := CACHE.request_region_job_resource(session, job)
	var wait_frames := 0
	while String(resource_state.get("state", "")) == "loading" and wait_frames < 600:
		await process_frame
		wait_frames += 1
		resource_state = CACHE.poll_region_job_resource(session, job)
	if resource_state.has("error") or not resource_state.get("resource") is Script:
		_check(false, "Cancellation fixture loads CourierVan resource")
		CACHE.finish_region_session(session, true)
		return {"error": resource_state.get("error", "resource_load_failed")}

	var execution: Dictionary = {}
	var completed_slices := 0
	for _step in MAX_STAGE_STEPS:
		execution = await _advance_with_ticket(session, job, resource_state.resource as Resource)
		_check(not execution.has("error"), "CourierVan partial attach reaches cancellation point")
		_check(not CACHE._models.has(MODEL_PATH) and not CACHE._prepared.has(MODEL_PATH), "CourierVan remains unpublished before commit")
		if String(execution.get("stage", "")) == "prepared_scene_attach_slice":
			completed_slices += 1
			if completed_slices == 2:
				break
		if execution.has("error") or bool(execution.get("complete", false)):
			break
	_check(completed_slices == 2, "Cancellation interrupts CourierVan after two attached groups")
	var state: Dictionary = (session.get("job_states", {}) as Dictionary).get(MODEL_PATH, {}) as Dictionary
	var staged_root := state.get("prepared_root") as Node3D
	var root_ref: WeakRef = weakref(staged_root) if staged_root != null else null
	var detached_refs: Array[WeakRef] = []
	for child_value in state.get("prepared_attach_children", []):
		var child := child_value as Node
		if is_instance_valid(child):
			detached_refs.append(weakref(child))
	_check(staged_root != null and staged_root.get_child_count() == 2, "Cancellation observes only the two completed groups under the private staging root")
	var report := CACHE.finish_region_session(session, true)
	await process_frame
	await process_frame
	_check(bool(report.get("cancelled", false)), "Cancelled CourierVan session reports cancellation")
	_check(not CACHE._models.has(MODEL_PATH) and not CACHE._prepared.has(MODEL_PATH), "Cancellation rolls back without partial CourierVan publication")
	_check((session.get("job_states", {}) as Dictionary).is_empty(), "Cancellation clears CourierVan resumable state")
	_check(root_ref == null or not is_instance_valid(root_ref.get_ref()), "Cancellation frees the private staging root")
	var children_freed := true
	for child_ref in detached_refs:
		if is_instance_valid(child_ref.get_ref()):
			children_freed = false
	_check(children_freed, "Cancellation frees attached and not-yet-attached CourierVan groups")
	_check(int(SCHEDULER.telemetry_snapshot().get("pending", -1)) == 0, "Cancellation leaves no pending scheduler reservation")
	return {
		"completed_slices": completed_slices,
		"published": CACHE._models.has(MODEL_PATH) or CACHE._prepared.has(MODEL_PATH),
		"scheduler_pending": int(SCHEDULER.telemetry_snapshot().get("pending", -1)),
	}


func _advance_with_ticket(session: Dictionary, job: Dictionary, resource: Resource) -> Dictionary:
	var producer := StringName(job.get("producer", &"vehicle_prewarm:emergency"))
	var ticket: Dictionary = await SCHEDULER.reserve(
		self,
		producer,
		SCHEDULER.PRIORITY_VISIBLE,
		STAGE_BUDGET_USEC
	)
	if ticket.is_empty():
		return {"error": "scheduler_ticket_missing", "stage": "scheduler_wait"}
	var ticket_granted_usec := Time.get_ticks_usec()
	var execution := CACHE.advance_region_job(session, job, resource, ticket)
	var actual_usec := int(execution.get("actual_usec", 0))
	SCHEDULER.complete(ticket, actual_usec)
	execution["ticket_id"] = int(ticket.get("id", -1))
	execution["ticket_frame"] = int(ticket.get("frame", -1))
	execution["ticket_granted_usec"] = ticket_granted_usec
	return execution


func _exercise_live_contract() -> Dictionary:
	var script := load(MODEL_PATH) as Script
	_check(script != null, "CourierVan model Script loads")
	if script == null:
		return {"error": "script_missing"}
	var stage := Node3D.new()
	root.add_child(stage)
	var hits_before := CACHE.hits
	var live := script.new() as Node3D
	stage.add_child(live)
	var sibling := script.new() as Node3D
	stage.add_child(sibling)
	_check(CACHE.hits == hits_before + 2, "CourierVan gameplay instances restore from direct prepared cache")
	_check(live.get_meta("courier_van_geometry_source", &"") == &"prepared", "CourierVan restore retains prepared source metadata")
	_check(bool(live.get_meta("vehicle_mesh_batched", false)), "CourierVan restore remains prebatched")
	_check(_mesh_count(live) == EXPECTED_MESHES and _triangle_count(live) == EXPECTED_TRIANGLES, "CourierVan restore preserves 19 meshes and 24,488 triangles")
	_check(_surface_count(live) == EXPECTED_SURFACES, "CourierVan restore preserves the 31-surface render compactness contract")
	_check(_surface_materials_match_runtime_roles(live), "CourierVan restore binds every surface to live materials")
	_check(_surface_materials_match_runtime_roles(sibling), "CourierVan sibling binds independent live materials")

	var prepared_hits_before := CLEARANCE.prepared_hits
	var mount_started := Time.get_ticks_usec()
	var rig := WHEEL_RIG.new()
	var mounted := rig.mount(live)
	var mount_usec := Time.get_ticks_usec() - mount_started
	_check(mounted and rig.pivots.size() == 4, "CourierVan restore mounts four articulated 3D wheels")
	_check(CLEARANCE.prepared_hits == prepared_hits_before + 1, "CourierVan restore reuses prepared wheel clearance")
	_check(BATCHER.batch_model(live) == 0, "CourierVan restore never repeats mesh batching")
	_check(_visual_signature(live) == EXPECTED_SIGNATURE, "CourierVan restore preserves exact triangle/material geometry")

	var originals := live.get("originals") as Dictionary
	var lamps := live.get("lamp_sources") as Dictionary
	_check(originals.size() == 1, "CourierVan restore keeps one compact damage body")
	_check(lamps.size() == 4, "CourierVan restore captures two headlamps and two taillamps")
	var lamp_materials: Dictionary = {}
	for lamp in lamps:
		lamp_materials[lamp] = (lamp as MeshInstance3D).material_override
	live.call("apply_impact", Vector3(0.75, 0.72, -2.38), Vector3(-1.0, 0.0, 0.0), 12.0)
	_check(int(live.get("impact_count")) == 1 and bool((live.get("broken_lamps") as Array)[1]), "CourierVan prepared body and localized headlamp accept damage")
	live.call("repair")
	_check(int(live.get("impact_count")) == 0 and not bool((live.get("broken_lamps") as Array)[1]), "CourierVan repair restores body and lamp state")
	var lamps_restored := true
	for lamp in lamp_materials:
		if is_instance_valid(lamp) and (lamp as MeshInstance3D).material_override != lamp_materials[lamp]:
			lamps_restored = false
	_check(lamps_restored and _visual_signature(live) == EXPECTED_SIGNATURE, "CourierVan repair restores exact prepared presentation")

	var live_paint := live.get("paint") as StandardMaterial3D
	var sibling_paint := sibling.get("paint") as StandardMaterial3D
	_check(live_paint != null and sibling_paint != null and live_paint != sibling_paint, "CourierVan paint remains independent per instance")
	if live_paint != null and sibling_paint != null:
		var sibling_color := sibling_paint.albedo_color
		live_paint.albedo_color = Color.MAGENTA
		_check(sibling_paint.albedo_color == sibling_color, "Repainting one CourierVan cannot recolor another")
		_check(sibling_color.v > 0.15 and sibling_color.a > 0.99, "CourierVan prepared paint remains visible and non-black")

	var result := {
		"meshes": _mesh_count(live),
		"surfaces": _surface_count(live),
		"triangles": _triangle_count(live),
		"signature": EXPECTED_SIGNATURE,
		"wheels": rig.pivots.size(),
		"lamps": lamps.size(),
		"damage_parts": originals.size(),
		"runtime_mount_usec": mount_usec,
		"runtime_mount_ms": mount_usec / 1000.0,
	}
	rig = null
	live.free()
	sibling.free()
	stage.free()
	return result


func _exercise_procedural_fallback() -> Dictionary:
	# Keep the direct cache intact for gameplay; constructor deferral creates a
	# private shell whose explicit build(false) proves the authored fallback.
	var script := load(MODEL_PATH) as Script
	CACHE._deferred_constructor_paths[MODEL_PATH] = 1
	var fallback := script.new() as Node3D
	CACHE._deferred_constructor_paths.erase(MODEL_PATH)
	fallback.call("build", false)
	root.add_child(fallback)
	var authored_meshes := _mesh_count(fallback)
	var rig := WHEEL_RIG.new()
	var mounted := rig.mount(fallback)
	var removed := BATCHER.batch_model(fallback)
	_flatten_wheels(fallback, rig)
	_check(mounted and rig.pivots.size() == 4, "CourierVan procedural fallback mounts four wheels")
	_check(authored_meshes == 93, "CourierVan fallback retains the 93-mesh authored source")
	_check(_triangle_count(fallback) == EXPECTED_TRIANGLES, "CourierVan fallback reaches the same post-clearance triangle count")
	_check(_visual_signature(fallback) == EXPECTED_SIGNATURE, "CourierVan fallback reaches the exact prepared visual signature")
	var result := {
		"authored_meshes": authored_meshes,
		"batched_removed": removed,
		"triangles": _triangle_count(fallback),
		"signature": _visual_signature(fallback),
		"wheels": rig.pivots.size(),
	}
	rig = null
	fallback.free()
	return result


func _courier_job(session: Dictionary) -> Dictionary:
	for job in CACHE.region_session_jobs(session):
		if String(job.get("path", "")) == MODEL_PATH:
			return job
	return {}


func _stage_names(rows: Array[Dictionary]) -> Array[String]:
	var result: Array[String] = []
	for row in rows:
		result.append(String(row.stage))
	return result


func _stage_rows(rows: Array[Dictionary], stage: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for row in rows:
		if String(row.get("stage", "")) == stage:
			result.append(row)
	return result


func _max_stage_usec(rows: Array[Dictionary]) -> int:
	var maximum := 0
	for row in rows:
		maximum = maxi(maximum, int(row.actual_usec))
	return maximum


func _timing_summary(samples: Array[int]) -> Dictionary:
	if samples.is_empty():
		return {
			"count": 0,
			"mean_usec": 0.0,
			"p50_usec": 0,
			"p95_usec": 0,
			"p99_usec": 0,
			"max_usec": 0,
		}
	var ordered := samples.duplicate()
	ordered.sort()
	var total := 0
	for sample in ordered:
		total += sample
	var p50: int = ordered[_percentile_index(ordered.size(), 0.50)]
	var p95: int = ordered[_percentile_index(ordered.size(), 0.95)]
	var p99: int = ordered[_percentile_index(ordered.size(), 0.99)]
	var maximum: int = ordered[-1]
	return {
		"count": ordered.size(),
		"mean_usec": float(total) / ordered.size(),
		"mean_ms": float(total) / ordered.size() / 1000.0,
		"p50_usec": p50,
		"p50_ms": p50 / 1000.0,
		"p95_usec": p95,
		"p95_ms": p95 / 1000.0,
		"p99_usec": p99,
		"p99_ms": p99 / 1000.0,
		"max_usec": maximum,
		"max_ms": maximum / 1000.0,
	}


func _percentile_index(count: int, quantile: float) -> int:
	return clampi(int(ceil((count - 1) * quantile)), 0, count - 1)


func _pearson_correlation(left: Array[int], right: Array[int]) -> float:
	var count := mini(left.size(), right.size())
	if count < 2:
		return 0.0
	var left_mean := 0.0
	var right_mean := 0.0
	for index in count:
		left_mean += left[index]
		right_mean += right[index]
	left_mean /= count
	right_mean /= count
	var covariance := 0.0
	var left_variance := 0.0
	var right_variance := 0.0
	for index in count:
		var left_delta := left[index] - left_mean
		var right_delta := right[index] - right_mean
		covariance += left_delta * right_delta
		left_variance += left_delta * left_delta
		right_variance += right_delta * right_delta
	if left_variance <= 0.000001 or right_variance <= 0.000001:
		return 0.0
	return covariance / sqrt(left_variance * right_variance)


func _reset_caches() -> void:
	SCHEDULER.reset_for_tests()
	CACHE._models.erase(MODEL_PATH)
	CACHE._prepared.erase(MODEL_PATH)
	CACHE._operationally_warmed_paths.erase(MODEL_PATH)
	CACHE._miss_started_usec.erase(MODEL_PATH)
	CACHE._deferred_constructor_paths.erase(MODEL_PATH)
	CACHE._regional_capture_suppressed_paths.erase(MODEL_PATH)
	CLEARANCE._cache.clear()
	CLEARANCE._content_keys.clear()
	BATCHER._mesh_cache.clear()
	BATCHER._format_cache.clear()
	BATCHER._primitive_formats.clear()


func _clear_courier_templates_only() -> void:
	CACHE._models.erase(MODEL_PATH)
	CACHE._prepared.erase(MODEL_PATH)
	CACHE._operationally_warmed_paths.erase(MODEL_PATH)
	CACHE._miss_started_usec.erase(MODEL_PATH)
	CACHE._deferred_constructor_paths.erase(MODEL_PATH)
	CACHE._regional_capture_suppressed_paths.erase(MODEL_PATH)


func _surface_materials_match_runtime_roles(model: Node3D) -> bool:
	var model_materials := model.get("materials") as Dictionary
	for child in model.get_children():
		var part := child as MeshInstance3D
		if part == null or part.mesh == null:
			continue
		var roles: PackedStringArray = part.get_meta(SURFACE_KEYS_META, PackedStringArray())
		if roles.size() != part.mesh.get_surface_count():
			return false
		for surface_index in roles.size():
			var expected := model_materials.get(StringName(roles[surface_index])) as Material
			var actual := part.material_override
			if actual == null:
				actual = part.get_surface_override_material(surface_index)
			if actual != expected:
				return false
	return true


func _flatten_wheels(model: Node3D, rig: RefCounted) -> void:
	for pivot in rig.pivots:
		if not is_instance_valid(pivot):
			continue
		_flatten_mesh_descendants(pivot, model)
		pivot.free()


func _flatten_mesh_descendants(parent: Node, model: Node3D) -> void:
	for child in parent.get_children():
		if child is MeshInstance3D:
			child.reparent(model, true)
		elif child is Node3D:
			_flatten_mesh_descendants(child, model)


func _mesh_count(node: Node) -> int:
	var count := 1 if node is MeshInstance3D and (node as MeshInstance3D).mesh != null else 0
	for child in node.get_children():
		count += _mesh_count(child)
	return count


func _triangle_count(node: Node) -> int:
	var count := 0
	if node is MeshInstance3D:
		var mesh := (node as MeshInstance3D).mesh
		if mesh != null:
			for surface_index in mesh.get_surface_count():
				var arrays := mesh.surface_get_arrays(surface_index)
				var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
				var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX] if arrays[Mesh.ARRAY_VERTEX] != null else PackedVector3Array()
				count += indices.size() / 3 if not indices.is_empty() else vertices.size() / 3
	for child in node.get_children():
		count += _triangle_count(child)
	return count


func _surface_count(node: Node) -> int:
	var count := 0
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		count = (node as MeshInstance3D).mesh.get_surface_count()
	for child in node.get_children():
		count += _surface_count(child)
	return count


func _visual_signature(model: Node3D) -> int:
	var entries: Array[String] = []
	_collect_visual(model, model, Transform3D.IDENTITY, entries)
	entries.sort()
	return hash(entries)


func _collect_visual(model: Node3D, node: Node, parent_transform: Transform3D, entries: Array[String]) -> void:
	var world_transform := parent_transform
	if node is Node3D:
		world_transform = parent_transform * (node as Node3D).transform
	if node is MeshInstance3D:
		var part := node as MeshInstance3D
		for surface_index in part.mesh.get_surface_count() if part.mesh != null else 0:
			var material_key := _material_key(model, part.get_active_material(surface_index))
			var arrays := part.mesh.surface_get_arrays(surface_index)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX] if arrays[Mesh.ARRAY_VERTEX] != null else PackedVector3Array()
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			var triangle_count := indices.size() / 3 if not indices.is_empty() else vertices.size() / 3
			for triangle_index in triangle_count:
				var points: Array[String] = []
				for corner in 3:
					var vertex_index := indices[triangle_index * 3 + corner] if not indices.is_empty() else triangle_index * 3 + corner
					var point := world_transform * vertices[vertex_index]
					points.append("%.5f,%.5f,%.5f" % [point.x, point.y, point.z])
				points.sort()
				entries.append("%s:%s" % [material_key, "|".join(points)])
	for child in node.get_children():
		_collect_visual(model, child, world_transform, entries)


func _material_key(model: Node3D, material: Material) -> String:
	var materials: Dictionary = model.get("materials")
	for key in materials:
		if materials[key] == material:
			return String(key)
	return "unknown"


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
