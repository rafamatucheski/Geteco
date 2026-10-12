extends "res://tests/measure/measure_harbor_idle_regression.gd"
## Main temporal evidence: --market --walk --camera-preview --night --reveal-off.
## Every frame_post_draw for30s; first10s stationary, then20s real walking.
## Full viewport JPG quality1.0. Readback/encoding/writes INVALIDATE FPS results.
const TEMPORAL_DURATION_USEC := 30000000
const TEMPORAL_STILL_USEC := 10000000
const TEMPORAL_JPEG_QUALITY := 1.0
const TEMPORAL_ANCHORS := [Vector3(100,0,40),Vector3(120,0,40),Vector3(100,0,55)]
var _temporal_start := 0
var _temporal_stop := 0
var _temporal_folder := ""
var _temporal_journal: FileAccess
var _temporal_rows: Array[Dictionary] = []
var _temporal_failures: Array[String] = []
var _temporal_gaps: Array[Dictionary] = []
var _temporal_previous_drawn := -1
var _temporal_previous_usec := 0
var _temporal_busy := false
var _temporal_active := false
var _temporal_closed := false
var _temporal_start_state: Dictionary = {}
var _temporal_walk_start := 0
var _temporal_requested_seconds := 0.0
var _temporal_parent_invalid := ""

func run() -> void:
	var args := OS.get_cmdline_user_args()
	for required in ["--market","--walk","--camera-preview","--night","--reveal-off"]:
		if required not in args:
			push_error("BUILDING_TEMPORAL_REQUIRES_"+required)
			quit(7)
			return
	if "--profile" in args or "--reveal-on" in args:
		push_error("BUILDING_TEMPORAL_REQUIRES_NO_PROFILE_NO_REVEAL_ON")
		quit(7)
		return
	RenderingServer.frame_post_draw.connect(_capture_temporal_frame)
	await super.run()
	_stop_temporal(Time.get_ticks_usec())
	if RenderingServer.frame_post_draw.is_connected(_capture_temporal_frame):
		RenderingServer.frame_post_draw.disconnect(_capture_temporal_frame)
	var parent_path := output.path_join(label+".json")
	if FileAccess.file_exists(parent_path):
		var parent_report: Variant = JSON.parse_string(FileAccess.get_file_as_string(parent_path))
		if parent_report is Dictionary: _temporal_parent_invalid = str(parent_report.get("invalid",""))
	_export_temporal()

func settle_load() -> bool:
	_temporal_requested_seconds = seconds
	seconds = maxf(seconds,31.0)
	return await super.settle_load()

func apply_load(now: int) -> void:
	if _temporal_start == 0:
		# Preserve the inherited warm-up behavior. Recording starts only after
		# the parent has begun its measured frame array.
		super.apply_load(now)
		if not frames.is_empty() and not _temporal_closed: _start_temporal(now)
	elif _temporal_active:
		if now-_temporal_start >= TEMPORAL_DURATION_USEC:
			_stop_temporal(now)
		elif now-_temporal_start < TEMPORAL_STILL_USEC:
			world.player.automatic_direction = Vector3.ZERO
		else:
			if _temporal_walk_start == 0: _temporal_walk_start = now
			super.apply_load(now)
	else:
		world.player.automatic_direction = Vector3.ZERO

func _start_temporal(now: int) -> void:
	_temporal_folder = output.path_join(label+"-temporal-"+str(now))
	var result := DirAccess.make_dir_recursive_absolute(_temporal_folder)
	if result != OK:
		_temporal_failures.append("directory_error:"+str(result))
		_stop_temporal(now)
		return
	_temporal_journal = FileAccess.open(_temporal_folder.path_join("frames.jsonl"),FileAccess.WRITE)
	if _temporal_journal == null:
		_temporal_failures.append("journal_open_error:"+str(FileAccess.get_open_error()))
		_stop_temporal(now)
		return
	world.player.automatic_direction = Vector3.ZERO
	_walk_anchor = world.player.global_position
	_previous_walk_point = _walk_anchor
	_temporal_start_state = state()
	_temporal_start = Time.get_ticks_usec()
	_temporal_active = true
	print("BUILDING_TEMPORAL_READY ",JSON.stringify({"start_usec":_temporal_start,"end_usec":_temporal_start+TEMPORAL_DURATION_USEC,"folder":_temporal_folder,"fps_invalid":true}))

func _capture_temporal_frame() -> void:
	if not _temporal_active: return
	var began := Time.get_ticks_usec()
	if began-_temporal_start >= TEMPORAL_DURATION_USEC:
		_stop_temporal(began)
		return
	if _temporal_busy:
		_temporal_failures.append("reentrant_frame_post_draw:"+str(began))
		return
	_temporal_busy = true
	var drawn := Engine.get_frames_drawn()
	var delta_drawn := drawn-_temporal_previous_drawn if _temporal_previous_drawn >= 0 else 0
	var gap_usec := began-_temporal_previous_usec if _temporal_previous_usec > 0 else 0
	if _temporal_previous_drawn >= 0 and delta_drawn != 1:
		_temporal_gaps.append({"usec":began,"previous":_temporal_previous_drawn,"current":drawn,"delta":delta_drawn})
		_temporal_failures.append("draw_counter_gap:"+str(drawn))
	var camera: Camera3D = world.camera
	var anchor_canvas_size := camera.get_viewport().get_visible_rect().size
	var anchor_pixels: Array = []
	for point: Vector3 in TEMPORAL_ANCHORS:
		var pixel := camera.unproject_position(point)
		anchor_pixels.append([pixel.x,pixel.y])
	var filename := "frame-%06d.jpg" % _temporal_rows.size()
	var row := {"index":_temporal_rows.size(),"filename":filename,"capture_start_usec":began,
		"elapsed_usec":began-_temporal_start,"frames_drawn":drawn,"draw_counter_delta":delta_drawn,
		"process_frame":Engine.get_process_frames(),"physics_frame":Engine.get_physics_frames(),
		"since_previous_capture_usec":gap_usec,"focused":DisplayServer.window_is_focused(),
		"window_mode":DisplayServer.window_get_mode(),"viewport_size":str(root.size),
		"motion_phase":"still" if _temporal_walk_start == 0 else "walk",
		"player_position":str(world.player.global_position),"player_velocity":str(world.player.velocity),
		"player_render_transform":str(world.player.get_global_transform_interpolated()),
		"camera_transform":str(camera.global_transform),"camera_render_transform":str(camera.get_global_transform_interpolated()),
		"camera_size":camera.size,"camera_near":camera.near,"camera_far":camera.far,
		"anchor_pixels_xy":anchor_pixels,
		"anchor_canvas_size_xy":[anchor_canvas_size.x,anchor_canvas_size.y],
		"exterior_reveal":camera._exterior_reveal.debug_snapshot()}
	if camera._exterior_reveal.enabled:
		_temporal_failures.append("reveal_enabled:"+str(drawn))
	var readback_start := Time.get_ticks_usec()
	var image: Image = root.get_texture().get_image()
	var readback_end := Time.get_ticks_usec()
	var saved := ERR_CANT_CREATE
	if image != null and not image.is_empty():
		row.image_size = str(image.get_size())
		saved = image.save_jpg(_temporal_folder.path_join(filename),TEMPORAL_JPEG_QUALITY)
	var saved_usec := Time.get_ticks_usec()
	row.readback_usec = readback_end-readback_start
	row.jpeg_and_write_usec = saved_usec-readback_end
	row.capture_end_usec = saved_usec
	row.save_error = saved
	if saved != OK: _temporal_failures.append("jpeg_error:"+filename+":"+str(saved))
	_temporal_rows.append(row)
	_temporal_journal.store_line(JSON.stringify(row))
	if _temporal_journal.get_error() != OK:
		_temporal_failures.append("journal_write_error:"+str(_temporal_journal.get_error()))
	_temporal_previous_drawn = drawn
	_temporal_previous_usec = began
	_temporal_busy = false
	if saved != OK or _temporal_journal.get_error() != OK:
		_stop_temporal(Time.get_ticks_usec())

func _stop_temporal(now: int) -> void:
	if _temporal_closed: return
	_temporal_closed = true
	_temporal_active = false
	_temporal_stop = now
	if _temporal_journal != null:
		_temporal_journal.flush()
		_temporal_journal.close()
		_temporal_journal = null
	if is_instance_valid(world): world.player.automatic_direction = Vector3.ZERO
	if _temporal_rows.is_empty(): _temporal_failures.append("no_frames_captured")
	for row in _temporal_rows:
		if not row.focused:
			_temporal_failures.append("capture_lost_focus")
			break
	if _temporal_start > 0 and now-_temporal_start < TEMPORAL_DURATION_USEC:
		_temporal_failures.append("incomplete_30_second_window")
	_export_temporal()

func stats(values: Array[float]) -> Dictionary:
	_stop_temporal(Time.get_ticks_usec())
	var summary := super.stats(values)
	summary["invalid_for_fps"] = true
	summary["reason"] = "Every rendered frame was read back, JPEG encoded and written; temporal visual evidence only."
	return summary

func _export_temporal() -> void:
	if output.is_empty(): return
	DirAccess.make_dir_recursive_absolute(output)
	var cadence: Array[float] = []
	var focused_draws := 0
	var still_frames := 0
	var walk_frames := 0
	for row in _temporal_rows:
		if int(row.since_previous_capture_usec) > 0: cadence.append(float(row.since_previous_capture_usec)/1000.0)
		if row.focused: focused_draws += 1
		if row.motion_phase == "still": still_frames += 1
		else: walk_frames += 1
	var report := {"label":label,"invalid_for_fps":true,"failures":_temporal_failures,
		"parent_invalid":_temporal_parent_invalid,"folder":_temporal_folder,"frames":_temporal_rows,
		"start_usec":_temporal_start,"requested_end_usec":_temporal_start+TEMPORAL_DURATION_USEC,
		"stop_usec":_temporal_stop,"walk_start_usec":_temporal_walk_start,
		"first_capture_usec":_temporal_rows[0].capture_start_usec if not _temporal_rows.is_empty() else 0,
		"last_capture_usec":_temporal_rows[-1].capture_start_usec if not _temporal_rows.is_empty() else 0,
		"captured_frames":_temporal_rows.size(),"still_frames":still_frames,"walk_frames":walk_frames,
		"focused_draws":focused_draws,"draw_counter_gaps":_temporal_gaps,
		"capture_cadence_ms":metric_stats(cadence,"ms"),"jpeg_quality":TEMPORAL_JPEG_QUALITY,
		"anchor_world_xyz":[[100,0,40],[120,0,40],[100,0,55]],
		"anchor_canvas_size_xy":_temporal_rows[0].anchor_canvas_size_xy if not _temporal_rows.is_empty() else [],
		"requested_seconds":_temporal_requested_seconds,"effective_parent_seconds":seconds,
		"state_start":_temporal_start_state,"state_end":state() if is_instance_valid(world) else {},
		"configuration":{"viewport":str(root.size),"max_fps":Engine.max_fps,
			"vsync":DisplayServer.window_get_vsync_mode(),"physics_hz":Engine.physics_ticks_per_second,
			"max_physics_steps":Engine.max_physics_steps_per_frame},
		"scope":"Temporal evidence only, all FPS results invalidated by synchronous viewport readback, JPEG encoding and disk writes. Connected to every frame_post_draw within the exact30s recording window after inherited warmup; no sampling stride, resized images, recording FPS cap, quality-setting changes or population/streaming changes. JPG quality1.0 at original viewport dimensions. First10s use zero automatic input, then20s use normal walking; actual velocity/timestamps reveal boundary settling. Capture cadence includes observer cost. Counter gaps and IO errors are explicit; JSONL preserves completed metadata if interrupted."}
	FileAccess.open(output.path_join(label+"-temporal.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
