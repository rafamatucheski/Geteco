extends SceneTree
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	root.get_node("CampaignState").set_campaign_flag(&"harbor_delivery_complete",true)
	change_scene_to_file("res://district/harbor_preview/HarborGame.tscn")
	for i in 15: await physics_frame
	var player = get_first_node_in_group("player")
	var car = get_first_node_in_group("modern_traffic")
	player.global_position = car.global_position + Vector2(0,-45)
	print("BEFORE ",car.name," pos=",car.global_position," basis=",car.global_transform," vel=",car.velocity)
	Input.action_press("interact")
	car.enter_vehicle(player)
	for i in 5:
		await physics_frame
		print("ENTER FRAME ",i," driven=",car.is_driven_by_player," pos=",car.global_position," vel=",car.velocity," health=",car.health," player=",player.global_position," visible=",player.visible)
	Input.action_release("interact")
	for i in 90: await physics_frame
	print("REST pos=",car.global_position," vel=",car.velocity," health=",car.health)
	Input.action_press("ui_up")
	for i in 90: await physics_frame
	Input.action_release("ui_up")
	print("DRIVE pos=",car.global_position," vel=",car.velocity," health=",car.health)
	quit()
