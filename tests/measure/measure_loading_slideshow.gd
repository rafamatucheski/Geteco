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
	Engine.max_fps = 60
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
	var curtain = load("res://runtime/StartupCurtain.gd").new()
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
	# Match the menu's threaded loading path, not change_scene_to_file's blocking IO.
	ResourceLoader.load_threaded_request("res://Main.tscn")
	var scene_requested := false
	while Time.get_ticks_usec()-began < 180000000:
		await process_frame
		if not scene_requested and ResourceLoader.load_threaded_get_status("res://Main.tscn") == ResourceLoader.THREAD_LOAD_LOADED:
			scene_requested = true
			change_scene_to_packed(ResourceLoader.load_threaded_get("res://Main.tscn"))
		var now := Time.get_ticks_usec()
		var ms := (now-last)/1000.0
		last = now
		if is_instance_valid(curtain):
			startup.append(ms)
			stages[curtain.stage_message] = true
			if now-began > (captures*6500000+1000000) and captures < 4:
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png(out.trim_suffix(".json")+"-%d.png" % captures)
				captures += 1
		else:
			if release == 0: release = now
			play.append(ms)
			if now-release >= 30000000: break
	var report := {"loading_ms":(release-began)/1000.0 if release else -1,"startup":stats(startup) if not startup.is_empty() else {},"play":stats(play) if not play.is_empty() else {},"startup_ms":startup,"play_ms":play,"stages":stages.keys(),"captures":captures,"gpu":RenderingServer.get_video_adapter_name(),"engine":Engine.get_version_info().string,"renderer":RenderingServer.get_current_rendering_method(),"resolution":str(root.size),"max_fps":Engine.max_fps,"vsync":DisplayServer.window_get_vsync_mode()}
	FileAccess.open(out,FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("LOADING_SLIDESHOW ",JSON.stringify({"loading_ms":report.loading_ms,"startup":report.startup,"play":report.play}))
	quit(0 if release > 0 else 3)

func _process(_delta: float) -> bool:
	return false
