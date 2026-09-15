extends SceneTree
func _initialize() -> void: run.call_deferred()
func run() -> void:
	create_timer(30).timeout.connect(func(): quit(2))
	for flag in [&"harbor_arrival_seen", &"harbor_arrival_call_complete", &"harbor_maciota_met"]:
		root.get_node("CampaignState").set_campaign_flag(flag,true)
	change_scene_to_file("res://world/harbor/HarborGame.tscn")
	for i in 30: await process_frame
	var p: Node2D = current_scene.get_node("Player")
	var g: Node = current_scene.get_node("Interiors").garage_interior
	# Desde 13/09 o WorldPerimeter devolve ao último ponto seguro quem está fora
	# do mapa sem a marca de interior. Entrar pela porta real, como o jogador.
	current_scene.get_node("Interiors")._on_exterior_destination_requested(current_scene.get_node("District/Garage/Entrance"), p, &"", null, &"", g, g.spawn_point)
	for i in 3: await physics_frame
	p.global_position = g.mission_board.global_position
	p.velocity = Vector2.ZERO
	for i in 8: await physics_frame
	print("BOARD PROBE position=",g.to_local(p.global_position)," distance=",p.global_position.distance_to(g.mission_board.global_position)," diagnostic=",g.diagnostic_active," enabled=",g.mission_board.interaction_enabled)
	for pressed in [true,false]:
		var key := InputEventKey.new()
		key.keycode = KEY_E
		key.physical_keycode = KEY_E
		key.pressed = pressed
		Input.parse_input_event(key)
		for i in 3: await physics_frame
	print("BOARD OPEN=",g.mission_board.is_ui_open," npc=",g.jager_npc.is_talking," diagnostic=",g.diagnostic_dialog.visible)
	var passed: bool = g.mission_board.is_ui_open
	# Closing a scene with its board open must not refresh a detached campaign node.
	current_scene.queue_free()
	await process_frame
	quit(0 if passed else 1)
