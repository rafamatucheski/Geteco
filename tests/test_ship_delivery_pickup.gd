extends SceneTree
var failures: Array[String] = []
func _initialize() -> void: _run.call_deferred()
func check(ok: bool, label: String) -> void:
	print(("PASS " if ok else "FAIL ")+label)
	if not ok: failures.append(label)
func _run() -> void:
	create_timer(60).timeout.connect(func(): quit(2))
	for flag in [&"harbor_arrival_seen", &"harbor_arrival_call_complete", &"harbor_maciota_met", &"harbor_delivery_started"]:
		root.get_node("CampaignState").set_campaign_flag(flag,true)
	change_scene_to_file("res://world/harbor/HarborGame.tscn")
	for i in 25: await process_frame
	var world := current_scene
	var player: CharacterBody2D = world.get_node("Player")
	player.set_physics_process(false)
	var mission: Node = world.campaign_controller
	var parcel: Node2D = world.get_node("FirstDeliveryParcel")
	var waterfront: Node2D = world.get_node("Waterfront")
	check(Geometry2D.is_point_in_polygon(waterfront.to_local(parcel.global_position),waterfront.get_ship_access_data().deck_polygon),"parcel is aboard ship")
	check(mission.target == parcel.global_position and parcel.visible,"objective and visible parcel agree")
	player.global_position = parcel.global_position+Vector2(0,45)
	var camera := Camera2D.new()
	world.add_child(camera)
	camera.position = parcel.global_position+Vector2(0,-20)
	camera.zoom = Vector2.ONE*2.2
	camera.make_current()
	for i in 8: await process_frame
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = player.get_node("Collision").shape
	query.transform = Transform2D(0,parcel.global_position)
	query.collision_mask = 1
	query.exclude = [player.get_rid()]
	check(world.get_world_2d().direct_space_state.intersect_shape(query).is_empty(),"real player capsule fits at pickup")
	if DisplayServer.get_name() != "headless":
		var angle: float = parcel.model.rotation.y
		for i in 20: await process_frame
		check(parcel.model.rotation.y != angle,"visible model rotates")
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("D:/geteco/ship-delivery-pickup.png")
	check(mission.interact_with_objective(),"package can be collected on deck")
	check(not parcel.visible and not parcel.is_processing(),"collected package stops drawing and processing")
	check(mission.phase == "delivery_return","return to Maciota remains next objective")
	check(not mission.interact_with_objective(),"cannot deliver remotely or collect twice")
	print("SHIP DELIVERY FAILURES ",failures)
	quit(0 if failures.is_empty() else 1)
