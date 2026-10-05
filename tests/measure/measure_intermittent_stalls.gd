extends "res://tests/measure/measure_physics_boundaries.gd"
## Finite rendered production capture. Inputs traverse Foundry Avenue in both
## directions; no callback substitution, runtime teleport or director disabling.
const PRE_USEC := 3000000
const POST_USEC := 3000000
const RING_LIMIT := 4096
const DETAIL_LIMIT := 30000
const CAPTURE_MS := 25.0
const PHASE_SECONDS := 30.0
var capture_frames: Array[Dictionary] = []
var capture_ring: Array[Dictionary] = []
var capture_kept: Array[Dictionary] = []
var capture_events: Array[Dictionary] = []
var capture_phase := "first_pass"
var capture_start := 0
var capture_until := 0
var capture_last_kept := -1
var capture_last_row: Dictionary = {}
var capture_created := 0
var capture_removed := 0
var capture_entities: Array[Dictionary] = []
var capture_signal_usec := 0
var capture_context_usec := 0
var capture_context_calls := 0
var capture_dropped := 0
var capture_ring_dropped := 0
var capture_input_usec := 0
var capture_mode := "on"
var capture_focus := 0
var capture_valid := ""
var capture_route_max_x := 107.0
var capture_route_min_return_x := 180.0
var capture_logger: Node
var capture_previous_physics := 0
var capture_probe_on := true
var capture_last_reload := 0
var capture_route_frames := 0
var capture_startup_usec := 0
var capture_pin_blood := false
var capture_cause_samples: Array[Dictionary] = []
var capture_cause_dropped := 0
const CAUSE_SAMPLE_LIMIT := 512
const CAPTURE_WORK := preload("res://runtime/StallWorkTrace.gd")

func capture_arm() -> bool:
	if not capture_probe_on: return true
	var source := load("res://tests/measure/ThreadCpuProbe.cs") as Script
	if source == null or not source.can_instantiate(): return false
	boundary_probe = source.new()
	var sample := _boundary_sample()
	if sample.size() != 7 or sample[5] != 1: return false
	boundary_thread_id = sample[1]
	_start_boundaries()
	capture_logger = root.get_node_or_null("StallLog")
	if capture_logger == null or not capture_logger.get("_enabled"): return false
	capture_logger.interval_observed.connect(capture_work)
	capture_logger.observe_intervals = true
	node_added.connect(func(node): _capture_entity(node,true))
	node_removed.connect(func(node): _capture_entity(node,false))
	return true

func _export_boundaries() -> void:
	# This subclass exports its own clock and selected circular windows.
	pass

func _audit_callback_order() -> bool:
	# Probes are already armed during loading; exclude only those two owned nodes.
	var pending: Array[Node] = [root]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		if node in boundary_nodes: continue
		var physics_priority := node.process_physics_priority
		var process_priority := node.process_priority
		var thread_group := node.process_thread_group
		if physics_priority != 0 or process_priority != 0 or thread_group != Node.PROCESS_THREAD_GROUP_INHERIT:
			if boundary_priority_rows.size() >= MAX_PRIORITY_ROWS:
				boundary_error = "priority_audit_overflow"
				return false
			boundary_priority_rows.append({"path":str(node.get_path()), "physics_priority":physics_priority,
				"process_priority":process_priority, "thread_group":thread_group})
		if absi(physics_priority) >= BOUNDARY_PRIORITY or process_priority >= BOUNDARY_PRIORITY or thread_group == Node.PROCESS_THREAD_GROUP_SUB_THREAD:
			boundary_error = "callback_order_not_bracketed: "+str(node.get_path())
			return false
		for child in node.get_children(): pending.append(child)
	return true

func capture_event(kind: String, details: Dictionary = {}) -> void:
	capture_events.append({"kind":kind, "engine_usec":Time.get_ticks_usec(),
		"frame":Engine.get_process_frames(), "phase":capture_phase, "details":details})

func _capture_entity(node: Node, added: bool) -> void:
	var began := Time.get_ticks_usec()
	if added: capture_created += 1
	else: capture_removed += 1
	if node is CharacterBody3D and capture_entities.size() < 64:
		capture_entities.append({"kind":"created" if added else "removed", "engine_usec":began,
			"frame":Engine.get_process_frames(), "id":str(node.get_instance_id()), "name":str(node.name),
			"class":node.get_class(), "position":str(node.global_position) if node.is_inside_tree() else "detached"})
	capture_signal_usec += Time.get_ticks_usec()-began

func capture_work(_now: int, work: Array, removed: int, roots: Array) -> void:
	var began := Time.get_ticks_usec()
	if not capture_last_row.is_empty():
		capture_last_row["work"] = work
		capture_last_row["logger_removed"] = removed
		capture_last_row["logger_removed_roots"] = roots.duplicate()
	if capture_pin_blood:
		for event in work:
			if event.get("label","") != "ground_blood.allocate": continue
			if capture_cause_samples.size() >= CAUSE_SAMPLE_LIMIT:
				capture_cause_dropped += 1
				continue
			capture_cause_samples.append({"sequence":capture_cause_samples.size(),"observed_frame":Engine.get_process_frames(),"work":event})
			capture_until = maxi(capture_until,_now+POST_USEC)
			for prior in capture_ring: capture_keep(prior)
	capture_signal_usec += Time.get_ticks_usec()-began

func capture_context() -> Dictionary:
	if not is_instance_valid(world) or not is_instance_valid(world.production) or not is_instance_valid(world.player) or world.session == null or not is_instance_valid(world.dispatch) or world.dispatch.router == null or not is_instance_valid(world.gameplay):
		return {"position":"loading", "nodes":Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
			"objects":Performance.get_monitor(Performance.OBJECT_COUNT)}
	var queues := {}
	var chunks := {}
	for key in world.production.regions:
		var region: Variant = world.production.regions[key]
		if not is_instance_valid(region): continue
		queues[key] = {"build_jobs":region.build_jobs.size(), "pending":region.pending.size(),
			"retiring":region._retiring.size(), "retire_stack":region._retire_stack.size()}
		chunks[key] = region.chunks.size()
	return {"position":str(world.player.global_position), "people":world.people.size(),
		"router_native":world.dispatch.router.get("_native") != null,
		"vehicles":world.production.vehicles.size(), "units":world.dispatch.units.size(),
		"stars":world.gameplay.stars, "health":world.gameplay.health,
		"queues":queues, "chunks":chunks, "nodes":Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		"objects":Performance.get_monitor(Performance.OBJECT_COUNT),
		"active_physics":Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS),
		"collision_pairs":Performance.get_monitor(Performance.PHYSICS_3D_COLLISION_PAIRS),
		"memory_bytes":Performance.get_monitor(Performance.MEMORY_STATIC)}

func capture_interval(now: int, previous: int) -> void:
	var began := Time.get_ticks_usec()
	var physics_now := Engine.get_physics_frames()
	var ms := float(now-previous)/1000.0
	var focused_now := DisplayServer.window_is_focused()
	if capture_phase in ["first_pass","return","event","recovery"]:
		capture_route_frames += 1
		if focused_now: capture_focus += 1
	capture_frames.append({"start_usec":previous,"end_usec":now,"ms":ms,"phase":capture_phase,
		"frame":Engine.get_process_frames(),"physics_steps":physics_now-capture_previous_physics,
		"focused":focused_now})
	capture_previous_physics = physics_now
	if not capture_probe_on: return
	_capture_boundaries(now)
	var row: Dictionary = boundary_rows.back()
	# The inherited collector is bounded; retain only our circular/pinned windows.
	boundary_rows.clear()
	row["frame"] = Engine.get_process_frames()
	row["phase"] = capture_phase
	row["ms"] = ms
	row["context"] = capture_context()
	row["created_nodes"] = capture_created
	row["removed_nodes"] = capture_removed
	row["entity_events"] = capture_entities
	row["signal_observer_usec"] = capture_signal_usec
	capture_entities = []
	capture_created = 0
	capture_removed = 0
	capture_signal_usec = 0
	capture_last_row = row
	capture_ring.append(row)
	# A long interval must keep context before its START, not just its end.
	var ring_cutoff := previous-PRE_USEC if ms >= CAPTURE_MS else now-PRE_USEC
	while not capture_ring.is_empty() and int(capture_ring[0].end_usec) < ring_cutoff:
		capture_ring.pop_front()
	if capture_ring.size() > RING_LIMIT:
		capture_ring.pop_front()
		capture_ring_dropped += 1
	if ms >= CAPTURE_MS:
		capture_until = now+POST_USEC
		for prior in capture_ring: capture_keep(prior)
	elif now <= capture_until: capture_keep(row)
	capture_context_usec += Time.get_ticks_usec()-began
	capture_context_calls += 1

func capture_keep(row: Dictionary) -> void:
	if int(row.frame) <= capture_last_kept: return
	if capture_kept.size() >= DETAIL_LIMIT:
		capture_dropped += 1
		return
	capture_kept.append(row)
	capture_last_kept = int(row.frame)

func capture_inputs(t: float) -> void:
	var began := Time.get_ticks_usec()
	var next_phase: String = ["first_pass","return","event","recovery"][mini(3,int(t/PHASE_SECONDS))]
	if next_phase != capture_phase:
		capture_phase = next_phase
		capture_event("phase_changed",capture_context())
		if next_phase == "event":
			world.gameplay.activate_arsenal_cheat()
			world.session.state.equip_weapon("ak47")
			capture_event("arsenal_fixture",{"godmode":world.gameplay.god_mode})
		elif next_phase == "recovery":
			Input.action_release("fire")
			Input.action_release("aim")
			capture_event("stimuli_stopped")
	var target := Vector3(180,.1,23) if capture_phase == "first_pass" else Vector3(107,.1,23)
	var point: Vector3 = world.player.global_position
	capture_route_max_x = maxf(capture_route_max_x,point.x)
	if capture_phase == "return": capture_route_min_return_x = minf(capture_route_min_return_x,point.x)
	var direction := target-point
	direction.y = 0
	var controls := root.get_node("GameInput")
	if capture_phase in ["first_pass","return"] and direction.length() > 1.0:
		var right: Vector3 = world.camera.global_basis.x
		var down: Vector3 = world.camera.global_basis.z
		right.y = 0
		down.y = 0
		var flat := direction.normalized()
		controls.touch_move = Vector2(flat.dot(right.normalized()),flat.dot(down.normalized()))
	else: controls.touch_move = Vector2.ZERO
	if capture_phase == "event":
		Input.action_press("aim")
		Input.action_press("fire")
		if world.session.state.get_ammo("ak47").magazine == 0 and began-capture_last_reload > 2000000:
			capture_last_reload = began
			var action := InputEventAction.new()
			action.action = "reload"
			action.pressed = true
			Input.parse_input_event(action)
			capture_event("reload_input")
	capture_input_usec += Time.get_ticks_usec()-began

func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--label="): label = arg.trim_prefix("--label=")
		elif arg.begins_with("--out="): output = arg.trim_prefix("--out=")
		elif arg.begins_with("--observer="): capture_mode = arg.trim_prefix("--observer=")
		elif arg == "--pin-ground-blood": capture_pin_blood = true
	capture_probe_on = capture_mode == "on"
	if output.is_empty() or DisplayServer.get_name() == "headless" or "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	if not ClassDB.class_exists(&"CSharpScript") or not OS.get_environment("HARBOR_NO_CSHARP").is_empty(): quit(3); return
	create_timer(240.0).timeout.connect(func(): push_error("STALL_CAPTURE_TIMEOUT"); quit(4))
	# Arm before Main's first productive frame. Loading stays a separate phase,
	# supplying predecessor context for the first gameplay/physics burst.
	if not capture_arm(): push_error("STALL_CAPTURE_ARM_FAILED"); quit(6); return
	capture_phase = "loading"
	capture_startup_usec = Time.get_ticks_usec()
	var previous := capture_startup_usec
	capture_previous_physics = Engine.get_physics_frames()
	capture_event("loading_start",{"clock_anchor":boundary_probe.ClockAnchor() if capture_probe_on else []})
	# Request focus before admitting the world. Never refocus during gameplay or
	# move an initial gameplay callback into a post-loading settling window.
	DisplayServer.window_move_to_foreground()
	var focus_deadline := Time.get_ticks_usec()+2000000
	while not DisplayServer.window_is_focused() and Time.get_ticks_usec() < focus_deadline:
		await process_frame
		var focus_now := Time.get_ticks_usec()
		capture_interval(focus_now,previous)
		previous = focus_now
	if not DisplayServer.window_is_focused():
		DirAccess.make_dir_recursive_absolute(output)
		FileAccess.open(output.path_join("focus-preflight.json"),FileAccess.WRITE).store_string(JSON.stringify({"validity":"focus_preflight_failed","frames":capture_frames,"events":capture_events,"world_admitted":false}))
		push_error("STALL_CAPTURE_FOCUS_PREFLIGHT_FAILED")
		quit(7); return
	var scene_began := CAPTURE_WORK.begin()
	var main_scene := load("res://Main.tscn") as PackedScene
	if scene_began != 0: CAPTURE_WORK.finish("capture.main_resource_load",scene_began)
	var instantiate_began := CAPTURE_WORK.begin()
	world = main_scene.instantiate()
	if instantiate_began != 0: CAPTURE_WORK.finish("capture.main_instantiate",instantiate_began)
	world.set_meta("skip_arrival",true)
	var admit_began := CAPTURE_WORK.begin()
	root.add_child(world)
	if admit_began != 0: CAPTURE_WORK.finish("capture.main_add_child_ready",admit_began)
	current_scene = world
	while world.session == null or not world.session.ready_for_play or world.production == null or not world.production.ready_for_play or root.has_node("LoadingCurtain") or world.has_node("LoadingCurtain"):
		await process_frame
		var loading_now := Time.get_ticks_usec()
		capture_interval(loading_now,previous)
		previous = loading_now
	world.session.state.intro.stage = "complete"
	world.player.controlled_automatically = false
	world.player.teleport(Vector3(107,.1,23)) # Setup only, never in measured route.
	world.camera.initialized = false
	world.camera.set_process_unhandled_input(false)
	var controls := root.get_node("GameInput")
	controls.set_process_input(false)
	controls._clear_camera_motion()
	controls.touch_aim = Vector2(5.0,3.0).normalized()
	world.session.weather.time_of_day = .4
	world.session.weather.weather_state = 0
	world.session.weather.weather_timer = 99999.0
	world.session.weather._update()
	world.gameplay.toggle_god_mode() # Isolated survival fixture, events remain active.
	if not world.production.no_save or not world.dispatch.router.use_native:
		push_error("STALL_CAPTURE_REQUIRES_NO_SAVE_AND_NATIVE_ROUTER_ENABLED"); quit(5); return
	# Keep the productive router's lazy C# graph initialization inside the capture.
	world.dispatch.dispatch_event.connect(func(kind, details):
		capture_event("dispatch."+kind,{"unit":str(details.get("unit","")),"stars":world.gameplay.stars}))
	if capture_probe_on:
		if not _audit_callback_order(): push_error(boundary_error); quit(6); return
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(),true)
	capture_start = Time.get_ticks_usec()
	capture_phase = "first_pass"
	capture_event("start",{"pid":OS.get_process_id(),"unix_seconds":Time.get_unix_time_from_system(),
		"clock_anchor":boundary_probe.ClockAnchor() if capture_probe_on else [],
		"thread_sample":_boundary_sample() if capture_probe_on else [],"no_save":world.production.no_save,
		"user_dir":OS.get_user_data_dir(),"router_native":world.dispatch.router.get("_native") != null,
		"router_native_enabled":world.dispatch.router.use_native})
	print("STALL_CAPTURE_READY ",label," ",JSON.stringify(capture_events[-1]))
	while true:
		await process_frame
		var now := Time.get_ticks_usec()
		capture_interval(now,previous)
		previous = now
		var t := float(now-capture_start)/1000000.0
		capture_inputs(t)
		if world.session.modal or not world.session.state.place_id.is_empty() or world.gameplay.health <= 0:
			capture_valid = "player_interrupted"
			break
		if t >= PHASE_SECONDS*4.0: break
	controls.touch_move = Vector2.ZERO
	for action in ["fire","aim","reload"]: Input.action_release(action)
	var gameplay_end_usec := previous
	capture_event("route_end",capture_context())
	# A fixed tail supplies three seconds after every peak in the measured route.
	# Peaks newly occurring in this tail may themselves have a truncated window.
	capture_phase = "tail"
	var tail_until := previous+POST_USEC
	while Time.get_ticks_usec() < tail_until:
		await process_frame
		var tail_now := Time.get_ticks_usec()
		capture_interval(tail_now,previous)
		previous = tail_now
	if capture_logger != null and capture_logger.interval_observed.is_connected(capture_work):
		capture_logger.observe_intervals = false
		capture_logger.interval_observed.disconnect(capture_work)
	_stop_boundaries()
	if capture_focus != capture_route_frames: capture_valid = "lost_focus"
	if capture_route_max_x < 175 or capture_route_min_return_x > 112: capture_valid = "route_incomplete"
	if world.dispatch.router.get("_native") == null: capture_valid = "native_router_not_exercised"
	if capture_dropped > 0 or capture_ring_dropped > 0 or capture_cause_dropped > 0 or boundary_tick_mismatches > 0 or boundary_invalid_cpu > 0:
		capture_valid = "observer_data_loss"
	var end_details := capture_context()
	end_details["clock_anchor"] = boundary_probe.ClockAnchor() if capture_probe_on else []
	capture_event("end",end_details)
	var report := {"label":label,"validity":capture_valid,"frames":capture_frames,"intervals":capture_kept,
		"cause_samples":capture_cause_samples,"cause_sample_limit":CAUSE_SAMPLE_LIMIT,"cause_samples_dropped":capture_cause_dropped,
		"events":capture_events,"clock":{"startup_start_usec":capture_startup_usec,"start_usec":capture_start,"gameplay_end_usec":gameplay_end_usec,"end_usec":previous},
		"config":{"godot":Engine.get_version_info().string,"cpu":OS.get_processor_name(),
			"gpu":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),
			"resolution":str(root.size),"msaa":root.msaa_3d,"scale":root.scaling_3d_scale,
			"vsync":DisplayServer.window_get_vsync_mode(),"max_fps":Engine.max_fps,
			"max_physics_steps":Engine.max_physics_steps_per_frame,"physics_hz":Engine.physics_ticks_per_second,
			"seed":21092026,"observer":capture_mode,"population":world.production.requested_population},
		"observer":{"context_capture_usec":capture_context_usec,"context_calls":capture_context_calls,
			"input_driver_usec":capture_input_usec,"dropped_details":capture_dropped,"ring_overflow":capture_ring_dropped,
			"tick_mismatches":boundary_tick_mismatches,"invalid_cpu":boundary_invalid_cpu,
			"ring_limit":RING_LIMIT,"detail_limit":DETAIL_LIMIT,"pre_usec":PRE_USEC,"post_usec":POST_USEC,
			"threshold_ms":CAPTURE_MS,"scope":"Self timing is a lower bound; dispatch and work hooks excluded; no subtraction from FPS."},
		"route":{"max_x":capture_route_max_x,"return_min_x":capture_route_min_return_x,"setup_teleport":true,
			"teleports_during_capture":0,"phases_seconds":PHASE_SECONDS},
		"scope":"Rendered Main; real input movement/fire, live normal directors. Godmode/arsenal isolated survival fixture. Loading and initial route retained separately; no warmup discard. Fixed 3s tail after 120s route supplies post-context for route peaks. New tail peaks may be truncated. 3s circular before/after >=25ms; all frame metrics retained. Inclusive durations, residual NOT exclusive solver/GPU/wait. Focus validity covers route; loading/tail focus recorded separately."}
	DirAccess.make_dir_recursive_absolute(output)
	FileAccess.open(output.path_join(label+".json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(label+".png"))
	print("STALL_CAPTURE_FINISHED ",label," validity=",capture_valid," frames=",capture_frames.size()," windows=",capture_kept.size())
	quit(0 if capture_valid.is_empty() else 1)
