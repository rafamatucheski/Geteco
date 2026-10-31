extends "res://tests/measure/measure_harbor_idle_regression.gd"
## Um início/aquecimento normal do Main, depois parado30s e caminhada física30s.
const MOTION_PHASE_USEC := 30000000
const MOTION_SNAPSHOT_USEC := 5000000
var _motion_phases: Array[Dictionary] = []
var _motion_current: Dictionary = {}
var _motion_frames: Array[float] = []
var _motion_previous := 0
var _motion_next_snapshot := 0
var _motion_done := false
var _motion_invalid: Array[String] = []
var _motion_parent: Dictionary = {}

func run() -> void:
	if "--profile" in OS.get_cmdline_user_args():
		push_error("STANDING_WALK_REQUIRES_PROFILER_DISABLED")
		quit(7)
		return
	await super.run()
	_finish_motion()
	var parent_path := output.path_join(label+".json")
	if FileAccess.file_exists(parent_path):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(parent_path))
		if parsed is Dictionary: _motion_parent = parsed
	_export_motion()

func settle_load() -> bool:
	seconds = maxf(seconds,62.0)
	var settled: bool = await super.settle_load()
	# Sobrescreve só a entrada automática deste diagnóstico, antes do aquecimento herdado.
	_walk = false
	scenario = "standing_then_walking"
	world.player.automatic_direction = Vector3.ZERO
	return settled

func apply_load(now: int) -> void:
	if _motion_done:
		world.player.automatic_direction = Vector3.ZERO
		return
	if _motion_current.is_empty():
		if frames.is_empty():
			super.apply_load(now)
			return
		_open_motion(now)
	else:
		# Este intervalo concluído ocorreu sob a entrada ANTERIOR. Registra-o
		# antes de trocar para caminhada; nunca atribui um intervalo parado à phase2.
		_motion_frames.append(float(now-_motion_previous)/1000.0)
		_motion_previous = now
		if DisplayServer.window_is_focused(): _motion_current.focused_intervals += 1
		else: _motion_current.unfocused_intervals += 1
		if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_MINIMIZED: _motion_current.minimized_intervals += 1
		if now-int(_motion_current.start_usec) >= MOTION_PHASE_USEC:
			_close_motion(now,true)
			if _motion_phases.size() == 2:
				_finish_motion()
				return
			_walk = true
			_open_motion(now)
		elif now >= _motion_next_snapshot:
			_motion_next_snapshot += MOTION_SNAPSHOT_USEC
			_motion_current.snapshots.append({"engine_usec":Time.get_ticks_usec(),"state":state()})
	# A phase2 usa o movimento normal original do Actor e o tratamento de obstáculos.
	super.apply_load(now)

func _open_motion(now: int) -> void:
	_motion_current = {"name":"standing" if _motion_phases.is_empty() else "walking",
		"start_usec":now,"physics_frame_start":Engine.get_physics_frames(),
		"process_frame_start":Engine.get_process_frames(),"drawn_frame_start":Engine.get_frames_drawn(),
		"focused_start":DisplayServer.window_is_focused(),"focused_intervals":0,
		"unfocused_intervals":0,"minimized_intervals":0,"snapshots":[]}
	_motion_current["state_start"] = state()
	_motion_current["start_observer_end_usec"] = Time.get_ticks_usec()
	_motion_frames.clear()
	_motion_previous = now
	_motion_next_snapshot = now+MOTION_SNAPSHOT_USEC

func _close_motion(now: int, complete: bool) -> void:
	_motion_current["end_usec"] = now
	_motion_current["complete"] = complete
	_motion_current["frames_ms"] = _motion_frames.duplicate()
	_motion_current["summary"] = super.stats(_motion_frames)
	_motion_current["state_end"] = state()
	_motion_current["end_observer_end_usec"] = Time.get_ticks_usec()
	var elapsed := maxf(float(now-int(_motion_current.start_usec))/1000000.0,.000001)
	var ticks := Engine.get_physics_frames()-int(_motion_current.physics_frame_start)
	_motion_current["physics_ticks"] = ticks
	_motion_current["actual_physics_hz"] = ticks/elapsed
	_motion_current["process_frames"] = Engine.get_process_frames()-int(_motion_current.process_frame_start)
	_motion_current["drawn_frames"] = Engine.get_frames_drawn()-int(_motion_current.drawn_frame_start)
	_motion_current["boundary_overshoot_usec"] = now-int(_motion_current.start_usec)-MOTION_PHASE_USEC
	if not complete: _motion_invalid.append("incomplete_"+str(_motion_current.name))
	if not bool(_motion_current.focused_start) or int(_motion_current.unfocused_intervals) > 0 or int(_motion_current.minimized_intervals) > 0:
		_motion_invalid.append("presentation_lost_"+str(_motion_current.name))
	_motion_phases.append(_motion_current)
	_motion_current = {}

func _finish_motion() -> void:
	if _motion_done: return
	if not _motion_current.is_empty(): _close_motion(_motion_previous,false)
	_motion_done = true
	_walk = false
	if is_instance_valid(world) and is_instance_valid(world.player): world.player.automatic_direction = Vector3.ZERO
	if _motion_phases.size() != 2: _motion_invalid.append("two_complete_phases_required")

func stats(values: Array[float]) -> Dictionary:
	_finish_motion()
	return super.stats(values)

func state() -> Dictionary:
	var row := super.state()
	row["standing_walk_phase"] = str(_motion_current.get("name","warmup" if not _motion_done else "finished"))
	row.idle_regression_fixture["scope"] = "This diagnostic overrides the inherited walk flag: stationary warm-up and first30s, then physical walking30s. No sampling-time teleportation; movement can be blocked by real obstacles. External concurrency and native presentation still require the inherited validation."
	return row

func _export_motion() -> void:
	if output.is_empty(): return
	var parent_invalid := str(_motion_parent.get("invalid","missing_parent_report"))
	if not parent_invalid.is_empty(): _motion_invalid.append("parent_invalid: "+parent_invalid)
	var report := {"label":label,"invalid":_motion_invalid,"phases":_motion_phases,
		"parent_clock":_motion_parent.get("clock",{}),"parent_configuration":_motion_parent.get("configuration",{}),
		"native_presentation":_motion_parent.get("native_presentation",{}),
		"scope":"Single normal rendered Main scene, one inherited native presentation gate, population settling and >=10s standing warm-up. Standing30s then walking30s; no changes to cap, physics, graphics, interpolation, population or runtime callbacks. Physical walking uses the inherited automatic Actor input between nearby waypoints and preserves obstacles. Parent observation is >=62s to accommodate first-complete-frame detection and boundary overshoot. Phase frames are disjoint complete process-signal intervals; each is recorded before any input change, so the final standing interval never becomes a walking sample. Phase2 starts at the same callback that closes phase1; snapshot/stat observer cost is included in its first interval and explicitly bracketed, not removed. Initial parent-to-phase fringe and final parent tail are outside phase stats and remain visible in parent data. Focus/native presentation validation remains authoritative across the whole parent window. Snapshots every5s and phase endpoints preserve actual population, vehicle motion and physical tick counters. Walking covers only the inherited short market path, not all city areas. No per-event CPU observer, no phase-time file exports; raw frames and existing StallLog remain available."}
	if not _motion_phases.is_empty():
		var clock: Dictionary = _motion_parent.get("clock",{})
		report["parent_start_fringe_usec"] = int(_motion_phases[0].start_usec)-int(clock.get("measurement_start_usec",0))
		report["parent_end_tail_usec"] = int(clock.get("measurement_end_usec",0))-int(_motion_phases[-1].end_usec)
	DirAccess.make_dir_recursive_absolute(output)
	var file := FileAccess.open(output.path_join(label+"-standing-walk.json"),FileAccess.WRITE)
	if file == null:
		push_error("STANDING_WALK_EXPORT_FAILED")
		quit(7)
		return
	file.store_string(JSON.stringify(report,"\t"))
	file.close()
	print("STANDING_WALK ",JSON.stringify({"invalid":_motion_invalid,"phases":_motion_phases.size()}))
	if not _motion_invalid.is_empty(): quit(7)
