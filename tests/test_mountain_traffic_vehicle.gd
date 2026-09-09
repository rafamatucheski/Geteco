extends SceneTree
var failures: Array[String] = []
func _initialize() -> void: _run.call_deferred()
func check(ok: bool, message: String) -> void:
	print(("PASS " if ok else "FAIL ")+message)
	if not ok: failures.append(message)
func _run() -> void:
	create_timer(60).timeout.connect(func(): quit(2))
	root.get_node("CampaignState").set_campaign_flag(&"harbor_delivery_complete",true)
	change_scene_to_file("res://district/mountain_pass/MountainPass.tscn")
	for i in 12: await physics_frame
	var scene := current_scene
	var traffic: Node = scene.get_node("MountainTraffic")
	var first: Node2D = traffic.vehicles[0]
	var follow := first.get_parent() as PathFollow2D
	var before := follow.progress
	await create_timer(1.5).timeout
	check(follow.progress > before+15,"ambient mountain traffic advances along road")
	var car := ModernTrafficFactory.spawn_parked_vehicle(scene,"WinterTrafficSave",Vector2(6050,650),0,"arctic_jeep",0,Color("3b7896"))
	check(car.spinners.size()==4 and car.spinners[0].get_child_count()>0,"authored wheels are attached to actual spinning hubs")
	car.repaint_vehicle(Color("974baa"))
	check(car.visual.modulate==Color.WHITE and car.body_model.paint.albedo_color==Color("974baa"),"paint changes body material without tinting glass/lights")
	var player: Node2D = scene.player_instance
	car.enter_vehicle(player)
	car.health = 89
	car.nitro_amount = 37
	car.has_puncture_proof_tires = true
	var travel := root.get_node("RegionTravel")
	var data: Dictionary = JSON.parse_string(JSON.stringify(travel.snapshot_world()))
	check(data.vehicle.paint==Color("974baa").to_html(),"traffic paint captured in save")
	car.exit_vehicle()
	car.queue_free()
	await process_frame
	travel.pending_world = data
	travel.finish_arrival(scene)
	var restored: Node2D = travel.controlled_car()
	check(restored != null and restored.health==89 and restored.nitro_amount==37 and restored.has_puncture_proof_tires,"traffic car upgrades and condition restored")
	check(restored.body_model.paint.albedo_color==Color("974baa"),"traffic paint restored")
	check(travel.request("harbor",restored),"stolen traffic car can travel")
	for i in 25: await physics_frame
	check(travel.controlled_car()==restored and current_scene.scene_file_path.ends_with("HarborGame.tscn"),"traffic car and driver arrive intact in Harbor")
	print("TRAFFIC VEHICLE FAILURES: ",failures)
	current_scene.queue_free()
	for i in 4: await process_frame
	quit(0 if failures.is_empty() else 1)
