extends SceneTree

## Rendered integration probe for the global SubViewport quality refresh.
##
## It boots the production HarborGame, keeps its real population/traffic views,
## selects already-resident cached 3D views and changes quality exactly as the
## settings menu does. Headless is rejected because this probe measures the
## renderer and GPU-backed viewport allocations.

const GAME := preload("res://world/harbor/HarborGame.tscn")
const STARTUP_TIMEOUT_MSEC := 180000
const SETTLE_FRAMES := 45
const SAMPLE_FRAMES := 30

var _failures: Array[String] = []
var _output_dir := "res://_codex_diag/render-quality-refresh"
var _property_only := false
var _late_population_wake := false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		_fail("rendered viewport refresh probe cannot run headless")
		quit(1)
		return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("out_dir="):
			_output_dir = arg.trim_prefix("out_dir=")
		elif arg == "--property-only":
			_property_only = true
		elif arg == "--late-population-wake":
			_late_population_wake = true
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_output_dir))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	root.size = Vector2i(1280, 720)
	root.content_scale_size = Vector2i(1280, 720)

	var saves := root.get_node("SaveManager")
	saves.set("_save_dir", ProjectSettings.globalize_path(_output_dir.path_join("saves")) + "/")
	saves.set("_save_directory_ready", false)
	saves.clear_pending_save()
	var campaign := root.get_node("CampaignState")
	campaign.reset_campaign()
	for flag in [
		&"harbor_arrival_seen", &"harbor_arrival_call_complete", &"harbor_maciota_met",
		&"harbor_delivery_started", &"harbor_delivery_picked_up", &"harbor_delivery_complete",
	]:
		campaign.set_campaign_flag(flag, true)

	var world := GAME.instantiate()
	root.add_child(world)
	current_scene = world
	var deadline := Time.get_ticks_msec() + STARTUP_TIMEOUT_MSEC
	while (not bool(world.get("gameplay_ready")) or not bool(world.get("world_build_ready"))) and Time.get_ticks_msec() < deadline:
		await process_frame
	if not bool(world.get("gameplay_ready")) or not bool(world.get("world_build_ready")) or paused:
		_fail("HarborGame did not reach its normal playable state")
		await _finish(world, {})
		return

	var settings := root.get_node("SettingsManager")
	settings.msaa_3d = Viewport.MSAA_2X
	if not _property_only:
		settings.display_settings_changed.emit()
	for _frame in SETTLE_FRAMES:
		await process_frame

	var inventory := _inventory()
	var dormant: Array[SubViewport] = []
	for candidate in get_nodes_in_group("quality_viewports"):
		var viewport := candidate as SubViewport
		if viewport == null or viewport.disable_3d or viewport.size.x <= 1 or viewport.size.y <= 1:
			continue
		if viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED:
			dormant.append(viewport)
	if dormant.size() < 8:
		_fail("expected at least 8 resident cached 3D views, found %d" % dormant.size())
	if _property_only:
		for viewport in dormant:
			viewport.msaa_3d = Viewport.MSAA_2X
		for _frame in 5:
			await process_frame

	var stable_samples := await _sample_frames(SAMPLE_FRAMES)
	var memory_before := _render_memory_bytes()
	var change_started := Time.get_ticks_usec()
	settings.msaa_3d = Viewport.MSAA_4X
	if _property_only:
		for viewport in dormant:
			viewport.msaa_3d = Viewport.MSAA_4X
	else:
		settings.display_settings_changed.emit()
	var signal_usec := Time.get_ticks_usec() - change_started
	var immediate_wakes := _count_update_once(dormant)
	var immediate_4x := _count_msaa(dormant, Viewport.MSAA_4X)
	var refresh_samples := await _sample_frames(SAMPLE_FRAMES)
	var render_quality := _render_quality_node(settings)
	var idle_wait_frames := 0
	if not _property_only and render_quality != null:
		while idle_wait_frames < 120 and not bool(render_quality.get_refresh_stats().get("idle", false)):
			await process_frame
			idle_wait_frames += 1
	await RenderingServer.frame_post_draw
	var memory_after := _render_memory_bytes()
	var remaining_wakes := _count_update_once(dormant)
	var final_4x := _count_msaa(dormant, Viewport.MSAA_4X)
	var late_population_wake := _exercise_late_population_wake(world) if _late_population_wake else {}
	var refresh_telemetry: Dictionary = render_quality.get_refresh_stats() if render_quality != null and render_quality.has_method("get_refresh_stats") else {}
	if not _property_only and (int(refresh_telemetry.get("pending", -1)) != 0 or not bool(refresh_telemetry.get("idle", false))):
		_fail("RenderQuality did not become idle after its bounded refresh window")
	var authored_mismatches := _authored_quality_mismatches()
	if authored_mismatches > 0:
		_fail("%d authored 3D views lost their explicit MSAA contract" % authored_mismatches)
	root.get_texture().get_image().save_png(_output_dir.path_join("after-refresh.png"))

	var result := {
		"mode": "property_only" if _property_only else "quality_signal",
		"gpu": RenderingServer.get_video_adapter_name(),
		"renderer": RenderingServer.get_current_rendering_method(),
		"resolution": str(root.size),
		"inventory": inventory,
		"dormant_selected": dormant.size(),
		"dormant_pixels": _viewport_pixels(dormant),
		"refresh_signal_usec": signal_usec,
		"immediate_update_once": immediate_wakes,
		"immediate_msaa_4x": immediate_4x,
		"final_msaa_4x": final_4x,
		"remaining_update_once_after_samples": remaining_wakes,
		"authored_quality_mismatches": authored_mismatches,
		"refresh_telemetry": refresh_telemetry,
		"idle_wait_frames": idle_wait_frames,
		"late_population_wake": late_population_wake,
		"stable": _stats(stable_samples),
		"refresh": _stats(refresh_samples),
		"render_memory_before_bytes": memory_before,
		"render_memory_after_bytes": memory_after,
		"render_memory_delta_bytes": memory_after - memory_before,
		"failures": _failures,
	}
	var file := FileAccess.open(_output_dir.path_join("result.json"), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(result, "\t"))
	print("RENDER_QUALITY_REFRESH_RESULT ", JSON.stringify(result))
	await _finish(world, result)


func _inventory() -> Dictionary:
	var result := {
		"total": 0,
		"three_d": 0,
		"disabled": 0,
		"once": 0,
		"live": 0,
		"authored_msaa": 0,
		"generic_msaa": 0,
	}
	for candidate in get_nodes_in_group("quality_viewports"):
		var viewport := candidate as SubViewport
		if viewport == null:
			continue
		result.total += 1
		if viewport.disable_3d:
			continue
		result.three_d += 1
		if int(viewport.get_meta("authored_msaa", Viewport.MSAA_DISABLED)) > Viewport.MSAA_DISABLED:
			result.authored_msaa += 1
		else:
			result.generic_msaa += 1
		match viewport.render_target_update_mode:
			SubViewport.UPDATE_DISABLED:
				result.disabled += 1
			SubViewport.UPDATE_ONCE:
				result.once += 1
			_:
				result.live += 1
	return result


func _render_quality_node(settings: Node) -> Node:
	for child in settings.get_children():
		if child.get_script() == preload("res://systems/RenderQuality.gd"):
			return child
	return null


func _exercise_late_population_wake(world: Node) -> Dictionary:
	var activities: Array = []
	var continuous := world.find_child("ContinuousWorld", true, false)
	if continuous != null:
		var activity = continuous.get("population_activity")
		if activity != null:
			activities.append(activity)
	var harbor_life := world.find_child("HarborLife", true, false)
	if harbor_life != null:
		var activity = harbor_life.get("_population_activity")
		if activity != null:
			activities.append(activity)
	for activity in activities:
		var sleeping: Dictionary = activity.get("sleeping")
		for actor_value in sleeping.keys():
			var actor := actor_value as Node2D
			if not is_instance_valid(actor):
				continue
			for child in actor.find_children("*", "SubViewport", true, false):
				var viewport := child as SubViewport
				if viewport == null or not viewport.has_meta("quality_residency_hook"):
					continue
				var before_msaa := int(viewport.msaa_3d)
				var before_mode := int(viewport.render_target_update_mode)
				activity.call("set_active", actor, true)
				var result := {
					"actor": actor.name,
					"viewport": viewport.name,
					"before_msaa": before_msaa,
					"after_msaa": int(viewport.msaa_3d),
					"before_mode": before_mode,
					"after_mode": int(viewport.render_target_update_mode),
					"hook_consumed": not viewport.has_meta("quality_residency_hook"),
				}
				if int(viewport.msaa_3d) != Viewport.MSAA_4X or not bool(result.hook_consumed):
					_fail("Production PopulationActivity late wake did not consume current quality")
				return result
	_fail("No sleeping production population viewport retained a late residency hook")
	return {}


func _authored_quality_mismatches() -> int:
	var mismatches := 0
	for candidate in get_nodes_in_group("quality_viewports"):
		var viewport := candidate as SubViewport
		if viewport == null or viewport.disable_3d:
			continue
		var authored := int(viewport.get_meta("authored_msaa", Viewport.MSAA_DISABLED))
		if authored > Viewport.MSAA_DISABLED and not bool(viewport.get_meta("quality_follow_global", false)) and int(viewport.msaa_3d) != authored:
			mismatches += 1
	return mismatches


func _sample_frames(count: int) -> Array[float]:
	var samples: Array[float] = []
	var previous := Time.get_ticks_usec()
	for _frame in count:
		await process_frame
		var now := Time.get_ticks_usec()
		samples.append(float(now - previous) / 1000.0)
		previous = now
	return samples


func _stats(samples: Array[float]) -> Dictionary:
	if samples.is_empty():
		return {}
	var ordered := samples.duplicate()
	ordered.sort()
	var total := 0.0
	var over_16 := 0
	var over_33 := 0
	var over_66 := 0
	for sample in samples:
		total += sample
		if sample > 16.67: over_16 += 1
		if sample > 33.3: over_33 += 1
		if sample > 66.7: over_66 += 1
	return {
		"mean_ms": total / samples.size(),
		"p50_ms": ordered[clampi(int(samples.size() * 0.50), 0, ordered.size() - 1)],
		"p95_ms": ordered[clampi(int(ceil(samples.size() * 0.95)) - 1, 0, ordered.size() - 1)],
		"p99_ms": ordered[clampi(int(ceil(samples.size() * 0.99)) - 1, 0, ordered.size() - 1)],
		"max_ms": ordered[-1],
		"over_16_67": over_16,
		"over_33_3": over_33,
		"over_66_7": over_66,
	}


func _render_memory_bytes() -> int:
	return RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED)


func _count_update_once(viewports: Array[SubViewport]) -> int:
	var count := 0
	for viewport in viewports:
		if is_instance_valid(viewport) and viewport.render_target_update_mode == SubViewport.UPDATE_ONCE:
			count += 1
	return count


func _count_msaa(viewports: Array[SubViewport], value: Viewport.MSAA) -> int:
	var count := 0
	for viewport in viewports:
		if is_instance_valid(viewport) and viewport.msaa_3d == value:
			count += 1
	return count


func _viewport_pixels(viewports: Array[SubViewport]) -> int:
	var pixels := 0
	for viewport in viewports:
		if is_instance_valid(viewport):
			pixels += viewport.size.x * viewport.size.y
	return pixels


func _fail(message: String) -> void:
	_failures.append(message)
	push_error(message)


func _finish(world: Node, result: Dictionary) -> void:
	if is_instance_valid(world):
		world.queue_free()
	await process_frame
	quit(0 if _failures.is_empty() and not result.is_empty() else 1)
