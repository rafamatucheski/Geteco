extends "res://tests/test_bank_heist_flow.gd"

func capture(label: String) -> void:
	if label == "05_cerco":
		var lamp_found := false
		for lamp in get_nodes_in_group("street_lamp"):
			if lamp.global_position.distance_to(Vector2(790,285)) < 1:
				lamp_found = true
				check(not lamp.broken and not lamp._falling, "Poste lateral permanece em pé após chegada do cerco")
		check(lamp_found, "Poste está na lateral da calçada, fora do eixo da entrada")
	if DisplayServer.get_name() == "headless" or label not in ["02_advertencia", "05_cerco"]: return
	var path := "res://docs/measurements/npc-presentation-0910/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path))
	for i in 8: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path + label + ".png")
