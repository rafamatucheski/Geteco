extends "res://tests/capture/capture_drag_start_camera.gd"
## Rendered real Main/.NET flow, isolated save; only pedals/shifts are supplied.
var failures: Array[String]=[]
var recording := false
var stamp := 0
var samples: Array[float]=[]
var timeline: Array[Dictionary]=[]
var next_probe := 0.0

func check(ok: bool, label: String) -> void:
	print("RETURN_MAIN ","PASS " if ok else "FAIL ",label)
	if not ok: failures.append(label); push_error(label)

func _process(_delta: float) -> bool:
	var now := Time.get_ticks_usec()
	if recording and stamp>0: samples.append(float(now-stamp)/1000.0)
	stamp=now
	return false

func shot(label: String) -> void:
	var previous := recording
	recording=false
	await capture(label)
	stamp=Time.get_ticks_usec()
	recording=previous

func review(race) -> void:
	Engine.max_fps=0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var session=world.session
	var car=world.driving.car
	var ladder: Dictionary=race.snapshot().duplicate(true)
	var old_camera=root.get_camera_3d()
	var old_listener=root.get_audio_listener_3d()
	check(race.perform("board"),"board opens through ordinary action")
	await shot("return-board")
	var board=race.board_controller.board
	board.select_rival("rauhz")
	check(board.return_button.disabled,"locked rival cannot enter return race")
	board.select_rival("digo")
	board.return_button.pressed.emit()
	check(race.active and race._return_attempt,"board button starts two-car return race")
	if not race.active: quit(1); return
	await shot("return-staging")
	var paused_turn := false
	var saw_out := false
	var saw_turn := false
	var saw_back := false
	var other_car=race.racers[1].car
	stamp=Time.get_ticks_usec()
	recording=true
	while race.active and race.elapsed<119:
		race._throttle_override=.54 if race.phase=="staging" else 1.0
		if race.phase=="racing" and race.racers[0].drive.rpm>=race.racers[0].drive.ideal_shift_rpm: race.request_shift()
		var entry: Dictionary=race.racers[0]
		if race.elapsed>=next_probe:
			next_probe=race.elapsed+.1
			timeline.append({"time":race.elapsed,"phase":race.phase,"gate":entry.return_gate,"progress":entry.return_progress,"speed":car.speed,"position":[car.global_position.x,car.global_position.y,car.global_position.z],"heading":[-car.global_basis.z.x,-car.global_basis.z.z],"rival_gate":race.racers[1].return_gate})
		if not saw_out and entry.return_progress>600:
			saw_out=true
			await shot("return-approach")
		if not saw_turn and entry.return_gate==1 and entry.return_angle>1.2:
			saw_turn=true
			await shot("return-barrel")
		if saw_turn and not paused_turn:
			paused_turn=true
			var pose: Transform3D=car.global_transform
			var time: float=race.elapsed
			var progress: float=entry.return_progress
			session._menu("Pausa")
			recording=false
			await create_timer(.3).timeout
			check(car.global_transform.is_equal_approx(pose) and is_equal_approx(race.elapsed,time) and is_equal_approx(entry.return_progress,progress),"pause freezes physical turn and race clock")
			session.close_menu()
			stamp=Time.get_ticks_usec()
			recording=true
		if not saw_back and entry.return_gate==2 and entry.return_progress>900:
			saw_back=true
			check((-car.global_basis.z).dot(race.direction)<-.95,"car really faces back toward start")
			await shot("return-sprint")
		await physics_frame
	recording=false
	check(not race.active and race.last_result.get("finished",false) and race.last_result.get("return_mode",false),"physical race completes after barrel and return crossing")
	check(saw_out and saw_turn and saw_back and paused_turn,"outbound turn pause and return all exercised")
	check(race.snapshot()==ladder,"return victory does not change ranked campaign progress")
	await process_frame
	check(not is_instance_valid(other_car) and session.modal and car.input_locked,"result owns modal until dismissal")
	await shot("return-result")
	check(root.get_camera_3d()==old_camera and root.get_audio_listener_3d()==old_listener,"finish restores previous camera and audio listener")
	var result: Dictionary=race.last_result.duplicate(true)
	var evidence := {"result":result,"timeline":timeline,"failures":failures,"environment":{"engine":Engine.get_version_info().string,"gpu":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),"resolution":[1280,720],"vsync":DisplayServer.window_get_vsync_mode(),"max_fps":Engine.max_fps},"frame_times_ms":samples}
	if not samples.is_empty():
		var ordered := samples.duplicate()
		ordered.sort()
		var total := 0.0
		var over33 := 0
		var over66 := 0
		for ms in samples:
			total+=ms
			if ms>33.3: over33+=1
			if ms>66.7: over66+=1
		evidence.metrics={"seconds":total/1000,"frames":samples.size(),"fps":samples.size()*1000/total,"p50":ordered[int(ordered.size()*.5)],"p95":ordered[int(ordered.size()*.95)],"p99":ordered[int(ordered.size()*.99)],"max":ordered.back(),"over33":over33,"over66":over66}
		print("RETURN_METRICS ",JSON.stringify(evidence.metrics))
	# Result UI must preserve this mode on rematch, then Q must clean all owners.
	for i in 3: await process_frame
	if session.modal:
		await race.board_controller._result_action("rematch")
		check(race.active and race._return_attempt,"result rematch retains return mode")
		if race.active:
			for pressed in [true,false]:
				var event := InputEventKey.new()
				event.physical_keycode=KEY_Q
				event.keycode=KEY_Q
				event.pressed=pressed
				Input.parse_input_event(event)
				Input.flush_buffered_events()
			for i in 3: await process_frame
			check(not is_instance_valid(race.return_course) and not car.input_locked and car.is_physics_processing(),"abandon removes barrel and restores ordinary driving")
	check(race.snapshot()==ladder,"rematch and abandonment never award ladder rewards")
	evidence.failures=failures.duplicate()
	var file := FileAccess.open(output.path_join("return-validation.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(evidence,"\t"))
	file.close()
	print("RETURN_MAIN_DONE ",ProjectSettings.globalize_path(output)," failures=",failures.size())
	if not failures.is_empty():
		quit(1)
		await process_frame
