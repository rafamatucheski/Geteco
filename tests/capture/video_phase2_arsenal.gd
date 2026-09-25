extends "res://tests/test_claude_arsenal_ui_state.gd"
## Keep Claude's behavior checks intact, but let Main finish its loading curtain
## before photographing the UI. Captures are not a performance benchmark.
func capture(label: String) -> void:
	if "--capture" not in OS.get_cmdline_user_args() or DisplayServer.get_name() == "headless": return
	for frame in 600:
		var loading := false
		for child in world.get_children():
			if child.get_script() == preload("res://runtime/StartupCurtain.gd"): loading = true
		if not loading:
			await super.capture(label)
			return
		await process_frame
	check(false, "loading curtain ended before UI photograph")
