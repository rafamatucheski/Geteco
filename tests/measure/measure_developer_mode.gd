extends "res://tests/measure/measure_session_diagnostics.gd"
## Same real stationary scene, with optional developer flight at the same location.
func run() -> void:
	await super.run()
	if "--dev-flight" in OS.get_cmdline_user_args() and is_instance_valid(world):
		var tools = world.pause_panel.developer_panel.tools
		if not tools.set_active(true) or not tools.begin_flight():
			push_error("Developer flight setup failed")
			quit(5)

func finish() -> void:
	# Capture only after the sample ends, never inside the performance window.
	world.pause_panel.pause_game()
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://evidence/"+label+"-pause.png")
	world.pause_panel.resume_game()
	await super.finish()
