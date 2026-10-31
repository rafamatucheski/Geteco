extends "res://tests/measure/measure.gd"
## Rendered startup + 30 seconds after release; never touches personal saves.
func run() -> void:
	if DisplayServer.get_name() == "headless" or "--no-save" not in OS.get_cmdline_user_args():
		quit(2)
		return
	var out := "res://evidence/loading-slideshow/after.json"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--report="): out = arg.trim_prefix("--report=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out.get_base_dir()))
	root.size = Vector2i(1280,720)
	DisplayServer.window_move_to_foreground()
	Engine.max_fps = 60
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
	# Settings aplica o modo de tela cheia salvo de forma adiada no início.
	await process_frame
	await process_frame
	DisplayServer.window_move_to_foreground()
	# Sem primeiro plano, o apresentador nativo de propósito não pinta. Zero
	# quadros nunca pode ser reportado como amostra bem-sucedida de desempenho de carregamento.
	var focus_deadline := Time.get_ticks_msec()+30000
	while not root.has_focus() and Time.get_ticks_msec()<focus_deadline:
		await process_frame
	if not root.has_focus():
		push_error("Loading measurement needs the game window in foreground")
		quit(3)
		return
	var curtain = load("res://runtime/StartupCurtain.gd").new()
	var presentation := {}
	curtain.presentation_finished.connect(func(report: Dictionary): presentation.assign(report))
	root.add_child(curtain)
	curtain.set_stage(.04,"Carregando…")
	await process_frame
	var began := Time.get_ticks_usec()
	var last := began
	var startup: Array[float] = []
	var play: Array[float] = []
	var release := 0
	var captures := 0
	var stages := {}
	var intervals: Array[Dictionary] = []
	var previous_stage := "Carregando…"
	# Segue o caminho de carregamento em thread do menu, não a E/S bloqueante de change_scene_to_file.
	ResourceLoader.load_threaded_request("res://Main.tscn")
	var scene_requested := false
	while release > 0 or Time.get_ticks_usec()-began < 180000000:
		await process_frame
		if not scene_requested and ResourceLoader.load_threaded_get_status("res://Main.tscn") == ResourceLoader.THREAD_LOAD_LOADED:
			scene_requested = true
			change_scene_to_packed(ResourceLoader.load_threaded_get("res://Main.tscn"))
		var now := Time.get_ticks_usec()
		var ms := (now-last)/1000.0
		last = now
		if is_instance_valid(curtain):
			startup.append(ms)
			intervals.append({"ms":ms,"stage":previous_stage,"end_stage":curtain.stage_message,"frame":Engine.get_process_frames()})
			previous_stage = curtain.stage_message
			stages[curtain.stage_message] = true
			if "--no-captures" not in OS.get_cmdline_user_args() and now-began > (captures*6500000+1000000) and captures < 4:
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png(out.trim_suffix(".json")+"-%d.png" % captures)
				captures += 1
		else:
			if release == 0: release = now
			play.append(ms)
			if now-release >= 30000000: break
	var report := {"loading_ms":(release-began)/1000.0 if release else -1,"startup":stats(startup) if not startup.is_empty() else {},"play":stats(play) if not play.is_empty() else {},"startup_ms":startup,"play_ms":play,"stages":stages.keys(),"captures":captures,"gpu":RenderingServer.get_video_adapter_name(),"engine":Engine.get_version_info().string,"renderer":RenderingServer.get_current_rendering_method(),"resolution":str(root.size),"max_fps":Engine.max_fps,"vsync":DisplayServer.window_get_vsync_mode()}
	report["startup_intervals"] = intervals
	report["presentation"] = presentation
	FileAccess.open(out,FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("LOADING_SLIDESHOW ",JSON.stringify({"loading_ms":report.loading_ms,"startup":report.startup,"play":report.play}))
	var presentation_measured := not presentation.is_empty() and int(presentation.get("frames",0)) > 0
	quit(0 if release > 0 and presentation_measured else 3)

func _process(_delta: float) -> bool:
	return false
