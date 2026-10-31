extends "res://tests/test_claude_arsenal_ui_state.gd"
## Mantém intactas as checagens de comportamento do Claude, mas deixa o Main terminar a cortina
## de carregamento antes de fotografar a UI. Capturas não são benchmark de desempenho.
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
