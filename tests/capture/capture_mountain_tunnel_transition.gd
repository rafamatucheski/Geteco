extends "res://tests/measure/measure_mountain_tunnel_camera.gd"
## Evidência temporal, NÃO benchmark: JPG .8 de cada frame desenhado, cap 30 FPS
## só durante a captura. --no-save --benchmark --scenario=foot_portal --output=...
## --night usa .94. Tráfego, NPCs, câmera, clima e colisão continuam reais.
const CAPTURE_SCRIPT := "res://tests/capture/capture_mountain_tunnel_transition.gd"
const CAPTURE_FPS := 30
var capture_hash := ""
var night := false

func run() -> void:
	var args := OS.get_cmdline_user_args()
	if "--scenario=foot_portal" not in args:
		push_error("Temporal tunnel capture only accepts explicit --scenario=foot_portal")
		quit(2)
		return
	for arg in args:
		if arg.begins_with("--scenario=") and arg != "--scenario=foot_portal":
			push_error("Conflicting tunnel capture scenario")
			quit(2)
			return
	night = "--night" in args
	capture_hash = FileAccess.get_sha256(CAPTURE_SCRIPT)
	report["artifact_type"] = "temporal_render_capture_not_performance"
	report["capture_script_sha256"] = capture_hash
	report["capture_time_of_day"] = .94 if night else .45
	report["full_approach"] = "--full-approach" in args
	await super.run()

func stage(point: Vector3, riding: bool) -> bool:
	if "--full-approach" in OS.get_cmdline_user_args():
		point.x = CONNECTION.TUNNEL_START_X-26.0
	if not await super.stage(point, riding): return false
	if night:
		world.session.weather.time_of_day = .94
		world.session.weather._update()
	return true

func environment() -> Dictionary:
	var result := super.environment()
	result["artifact_type"] = "temporal_render_capture_not_performance"
	result["capture_cap_fps"] = CAPTURE_FPS
	result["capture_jpeg_quality"] = .8
	result["capture_time_of_day"] = .94 if night else .45
	result["notes"] = "Production Main, live NPCs/traffic/physics and gameplay camera. Only capture phase has a 30 FPS cap. Synchronous JPG encoding/disk writes affect frame intervals: this run cannot approve performance. Warmup records inherited from the harness are diagnostic only. Frame timestamps, engine-frame gaps and estimated 30 Hz slot misses describe capture continuity; misses do not distinguish GPU/CPU/disk. No settings or personal saves are written."
	return result

func sample(seconds: float) -> Dictionary:
	if seconds < 30.0: return await super.sample(seconds)
	var frames_folder := output.path_join("frames")
	if DirAccess.make_dir_recursive_absolute(frames_folder) != OK:
		fail("Could not create temporal frame directory")
		return {"summary": {"capture_only": true, "frames": 0}}
	var original_cap := Engine.max_fps
	Engine.max_fps = CAPTURE_FPS
	world.player.speed = 3.5
	world.player.automatic_direction = Vector3.ZERO
	var began := Time.get_ticks_usec()
	var previous := began
	var previous_drawn := Engine.get_frames_drawn()
	var frame_index := 0
	var dropped_engine_frames := 0
	var missed_30hz_slots := 0
	var trace: Array[Dictionary] = []
	var events: Array[Dictionary] = []
	var phase := ""
	while Time.get_ticks_usec() - began < seconds * 1000000.0:
		var elapsed := float(Time.get_ticks_usec() - began) / 1000000.0
		var next_phase := _phase_at(elapsed)
		if next_phase != phase:
			phase = next_phase
			_apply_phase(phase)
			events.append({"phase": phase, "elapsed_ms": elapsed * 1000.0, "player_xyz": _xyz(world.player.global_position), "visual_yaw": world.player.visual.rotation.y})
		await process_frame
		await RenderingServer.frame_post_draw
		var now := Time.get_ticks_usec()
		var interval_ms := float(now - previous) / 1000.0
		var drawn := Engine.get_frames_drawn()
		var dropped := maxi(0, drawn - previous_drawn - 1)
		var missed := maxi(0, roundi(interval_ms * float(CAPTURE_FPS) / 1000.0) - 1)
		dropped_engine_frames += dropped
		missed_30hz_slots += missed
		var filename := "frame_%05d.jpg" % frame_index
		var pose := state()
		pose["frame_index"] = frame_index
		pose["filename"] = "frames/" + filename
		pose["engine_frame"] = drawn
		pose["elapsed_ms"] = float(now - began) / 1000.0
		pose["interval_ms"] = interval_ms
		pose["phase"] = phase
		pose["player_xyz"] = _xyz(world.player.global_position)
		pose["camera_xyz"] = _xyz(world.camera.global_position)
		pose["camera_rotation_xyz"] = _xyz(world.camera.global_rotation)
		pose["visual_yaw"] = world.player.visual.rotation.y
		pose["automatic_direction"] = _xyz(world.player.automatic_direction)
		pose["local_fog"] = _fog_state()
		pose["dropped_engine_frames"] = dropped
		pose["estimated_missed_30hz_slots"] = missed
		var image := root.get_texture().get_image()
		var write_started := Time.get_ticks_usec()
		var error := image.save_jpg(frames_folder.path_join(filename), .8)
		pose["jpeg_write_ms"] = float(Time.get_ticks_usec() - write_started) / 1000.0
		pose["saved"] = error == OK
		trace.append(pose)
		if error != OK:
			fail("Temporal JPG failed: " + filename)
			break
		frame_index += 1
		previous = now
		previous_drawn = drawn
	world.player.automatic_direction = Vector3.ZERO
	Engine.max_fps = original_cap
	var result := {"summary": {"capture_only": true, "performance_approved": false, "frames": frame_index, "seconds": float(Time.get_ticks_usec() - began) / 1000000.0, "capture_cap_fps": CAPTURE_FPS, "dropped_engine_frames": dropped_engine_frames, "estimated_missed_30hz_slots": missed_30hz_slots}, "events": events, "trace": trace}
	var file := FileAccess.open(output.path_join("temporal-frames.json"), FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify(result, "\t"))
	else: fail("Could not write temporal frame manifest")
	print("TUNNEL_TEMPORAL_CAPTURE ", JSON.stringify(result.summary))
	return result

func _phase_at(elapsed: float) -> String:
	if elapsed < 5.0: return "stationary_lateral"
	if elapsed < 13.0: return "enter_right"
	if elapsed < 17.0: return "turn_toward_exit"
	if elapsed < 27.0: return "return_left"
	return "stationary_after_return"

func _apply_phase(phase: String) -> void:
	world.player.automatic_direction = Vector3.ZERO
	if phase == "enter_right": world.player.automatic_direction = Vector3.RIGHT
	elif phase == "return_left": world.player.automatic_direction = Vector3.LEFT
	elif phase == "turn_toward_exit": world.player.visual.rotation.y = PI * .5

func _xyz(value: Vector3) -> Array:
	return [value.x, value.y, value.z]

func _fog_state() -> Dictionary:
	return {"time_of_day": world.session.weather.time_of_day, "mountain_weight": CONNECTION.tunnel_camera_weight(world.player.global_position), "chase_blend": world.camera._tunnel_chase_blend, "camera_environment": _environment_fields(world.camera.environment), "source_environment": _environment_fields(world.camera.get_world_3d().environment)}

func _environment_fields(env: Environment) -> Dictionary:
	if env == null: return {"present": false}
	return {"present": true, "environment_id": env.get_instance_id(), "fog_enabled": env.fog_enabled, "fog_density": env.fog_density, "fog_depth_begin": env.fog_depth_begin, "fog_depth_end": env.fog_depth_end, "fog_light_color": [env.fog_light_color.r, env.fog_light_color.g, env.fog_light_color.b], "background_color": [env.background_color.r, env.background_color.g, env.background_color.b]}

func finish() -> void:
	report["capture_script_sha256_end"] = FileAccess.get_sha256(CAPTURE_SCRIPT)
	if report.capture_script_sha256_end != capture_hash: fail("Temporal capture script changed while running")
	await super.finish()
