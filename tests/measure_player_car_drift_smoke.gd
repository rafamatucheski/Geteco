extends SceneTree

const GAME := preload("res://world/harbor/HarborGame.tscn")
const SAMPLE_SECONDS := 30.0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Drift smoke benchmark requires a real renderer")
		quit(1)
		return
	root.size = Vector2i(1280, 720)
	root.content_scale_size = Vector2i(1280, 720)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	root.get_node("SaveManager").clear_pending_save()
	var campaign := root.get_node("CampaignState")
	campaign.reset_campaign()
	for flag in ["harbor_arrival_seen", "harbor_arrival_call_complete", "harbor_maciota_met", "harbor_delivery_complete"]:
		campaign.set_campaign_flag(StringName(flag), true)

	var world := GAME.instantiate()
	root.add_child(world)
	current_scene = world
	var deadline := Time.get_ticks_msec() + 120000
	while (not world.gameplay_ready or not world.world_build_ready) and Time.get_ticks_msec() < deadline:
		await process_frame
	if not world.gameplay_ready or not world.world_build_ready or paused:
		push_error("HarborGame did not reach its playable checkpoint")
		quit(1)
		return

	var car: CharacterBody2D = world.get_node("PlayerCar")
	car.global_position = Vector2(2200.0, 1050.0)
	car.rotation = 0.0
	car.reset_physics_interpolation()
	car.get_node("Camera").make_current()
	car.set_physics_process(false)
	car.is_driven_by_player = true
	car.velocity = car.transform.y * 160.0
	car.is_skidding = true
	for i in 300:
		await process_frame

	var smoke_off: Dictionary
	var smoke_on: Dictionary
	if OS.get_cmdline_user_args().has("--on-first"):
		car.drift_smoke_l.emitting = true
		car.drift_smoke_r.emitting = true
		smoke_on = await _sample("on")
		car.drift_smoke_l.emitting = false
		car.drift_smoke_r.emitting = false
		smoke_off = await _sample("off")
	else:
		car.drift_smoke_l.emitting = false
		car.drift_smoke_r.emitting = false
		smoke_off = await _sample("off")
		car.drift_smoke_l.emitting = true
		car.drift_smoke_r.emitting = true
		smoke_on = await _sample("on")
	car.drift_smoke_l.emitting = false
	car.drift_smoke_r.emitting = false

	var p95_delta_pct := 100.0 * (float(smoke_on.p95_ms) - float(smoke_off.p95_ms)) / maxf(float(smoke_off.p95_ms), 0.001)
	print("DRIFT_SMOKE_COMPARISON renderer=%s resolution=1280x720 off_p95_ms=%.3f on_p95_ms=%.3f delta_p95_pct=%.2f" % [
		RenderingServer.get_current_rendering_method(), smoke_off.p95_ms, smoke_on.p95_ms, p95_delta_pct])
	world.queue_free()
	await process_frame
	quit(0)

func _sample(label: String) -> Dictionary:
	var samples := PackedFloat64Array()
	var total_ms := 0.0
	var over_33 := 0
	var over_66 := 0
	var previous_usec := Time.get_ticks_usec()
	while total_ms < SAMPLE_SECONDS * 1000.0:
		await process_frame
		var now_usec := Time.get_ticks_usec()
		var frame_ms := maxf(0.001, float(now_usec - previous_usec) / 1000.0)
		previous_usec = now_usec
		samples.append(frame_ms)
		total_ms += frame_ms
		if frame_ms > 33.3: over_33 += 1
		if frame_ms > 66.7: over_66 += 1
	samples.sort()
	var count := samples.size()
	var result := {
		"frames": count,
		"avg_fps": float(count) * 1000.0 / total_ms,
		"p50_ms": samples[clampi(int(ceil(count * 0.50)) - 1, 0, count - 1)],
		"p95_ms": samples[clampi(int(ceil(count * 0.95)) - 1, 0, count - 1)],
		"p99_ms": samples[clampi(int(ceil(count * 0.99)) - 1, 0, count - 1)],
		"max_ms": samples[count - 1],
		"over_33": over_33,
		"over_66": over_66,
	}
	print("DRIFT_SMOKE_SAMPLE state=%s seconds=%.2f frames=%d avg_fps=%.2f p50_ms=%.3f p95_ms=%.3f p99_ms=%.3f max_ms=%.3f over_33=%d over_66=%d" % [
		label, total_ms / 1000.0, result.frames, result.avg_fps, result.p50_ms,
		result.p95_ms, result.p99_ms, result.max_ms, result.over_33, result.over_66])
	return result
