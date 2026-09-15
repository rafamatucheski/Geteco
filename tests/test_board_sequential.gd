extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	root.size = Vector2i(1280, 720)
	var board = load("res://CarChalkboard.gd").new()
	board.use_legacy_position = false
	root.add_child(board)
	var missions: Array[Dictionary] = [
		{"id": "one", "title": "Primeiro giro", "description": "Busque a encomenda e volte para falar com Maciota.", "enabled": true},
		{"id": "two", "title": "SEGREDO FUTURO", "enabled": true},
		{"id": "three", "title": "OUTRO SEGREDO", "enabled": false}]
	board.configure_missions(missions)
	board.open_chalkboard()
	await create_timer(0.3).timeout
	assert(board.orders_vbox.find_children("*", "Button", true, false).size() == 1)
	assert(not contains_text(board.orders_vbox, "SEGREDO"))
	assert(root.gui_get_focus_owner().get_meta("mission_id") == "one")
	missions[0]["completed"] = true
	board.configure_missions(missions)
	assert(root.gui_get_focus_owner().get_meta("mission_id") == "two")
	var struck := false
	for child in board.orders_vbox.get_children():
		if child.get_meta("board_row_state", "") == "completed":
			struck = child.get_child(1).text.contains("[s]")
	assert(struck)
	missions[1]["enabled"] = false
	missions[1]["requirement"] = "Em andamento"
	board.configure_missions(missions)
	assert(board.orders_vbox.find_children("*", "Button", true, false).is_empty())
	assert(root.gui_get_focus_owner() == board._close_btn)
	assert(not contains_text(board.orders_vbox, "OUTRO SEGREDO"))
	missions[1]["title"] = "Uma entrega para Maciota"
	missions[1]["description"] = "Leve a encomenda até a oficina."
	missions[1]["enabled"] = true
	board.configure_missions(missions)
	await create_timer(0.3).timeout
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("D:/geteco/artifacts/board-sequential/board.png")
	print("PASS: sequential reveal, completed strike-through, active blocking, focus and hidden spoilers")
	board.close_chalkboard()
	await create_timer(0.2).timeout
	board.queue_free()
	await process_frame
	quit()

func contains_text(node: Node, value: String) -> bool:
	if node is Label and node.text.contains(value):
		return true
	for child in node.get_children():
		if contains_text(child, value):
			return true
	return false
