extends "res://tests/measure/measure_session_diagnostics.gd"
## Mesma cena parada real, com voo de desenvolvedor opcional no mesmo lugar.
func run() -> void:
	await super.run()
	if "--dev-flight" in OS.get_cmdline_user_args() and is_instance_valid(world):
		var tools = world.pause_panel.developer_panel.tools
		if not tools.set_active(true) or not tools.begin_flight():
			push_error("Developer flight setup failed")
			quit(5)

func finish() -> void:
	# Captura só depois de a amostra terminar, nunca dentro da janela de desempenho.
	world.pause_panel.pause_game()
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://evidence/"+label+"-pause.png")
	world.pause_panel.resume_game()
	await super.finish()
