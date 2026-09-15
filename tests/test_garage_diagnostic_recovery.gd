extends SceneTree

var failures: Array[String] = []

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	print("PASS " if ok else "FAIL ", label)
	if not ok: failures.append(label)

func run() -> void:
	create_timer(120).timeout.connect(func(): quit(2))
	root.get_node("SaveManager").set("_save_dir", OS.get_temp_dir().path_join("garage_repair_%d" % Time.get_ticks_usec()) + "/")
	root.get_node("SaveManager").set("_save_directory_ready", false)
	root.get_node("CampaignState").reset_campaign()
	root.get_node("SaveManager").clear_pending_save()
	for flag in [&"harbor_arrival_seen", &"harbor_arrival_call_complete", &"harbor_maciota_met", &"harbor_delivery_complete"]:
		root.get_node("CampaignState").set_campaign_flag(flag, true)
	var scene: Node = load("res://world/harbor/HarborGame.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	while not scene.gameplay_ready: await process_frame
	var manager: Node = scene.get_node("PersonalCarManager")
	var garage: Node = manager.garage
	var player: Node2D = manager.player
	player.set_physics_process(false)
	player.global_position = garage.diagnostic_area.global_position
	var car: Node2D = manager.car
	car.set_physics_process(false)
	var identity := car.get_instance_id()
	var equipment: Dictionary = player.personal_loadout.duplicate(true)
	player.money = 200
	garage._run_diagnostic()
	check(garage.diagnostic_dialog.visible and not garage.diagnostic_recover.visible, "Terminal opens with the car present and no unnecessary recovery")
	check(garage.diagnostic_repair.visible and garage.diagnostic_repair.disabled, "Healthy car shows repair disabled")
	var parked_position := car.global_position
	var parked_rotation := car.rotation
	var healthy_speed: float = car.max_speed
	car.health = 70
	car.puncture_tires()
	garage._refresh_diagnostic()
	check(not garage.diagnostic_repair.disabled, "Damage enables the repair button")
	garage.diagnostic_repair.pressed.emit()
	check(car.health == car.max_health and not car.has_punctured_tires and is_equal_approx(car.max_speed, healthy_speed), "Repair restores full condition, tires and handling")
	check(car.global_position == parked_position and car.rotation == parked_rotation and car.get_instance_id() == identity and player.personal_loadout == equipment, "Repair preserves parking, identity and equipment")
	check(player.money == 150 and player.personal_car_state.health == car.max_health, "Repair charges the displayed fee and updates saved vehicle state")
	garage._repair_from_diagnostic()
	check(player.money == 150 and garage.diagnostic_repair.disabled, "Repeated repair does not charge a healthy car")
	car.health = 80
	player.money = 49
	garage._refresh_diagnostic()
	check(garage.diagnostic_repair.disabled, "Insufficient funds disables repair")
	garage._repair_from_diagnostic()
	check(player.money == 49 and car.health == 80, "Rejected repair changes neither condition nor balance")
	player.money = 200
	car.global_position = Vector2(1000, 1000)
	check(not manager.repair(), "Repair cannot remotely fix a car outside the workshop")
	for state in ["parked", "impounded", "broken"]:
		car.global_position = Vector2(1000, 1000)
		manager.impounded = state == "impounded"
		car.is_broken = state == "broken"
		manager._sync_availability()
		garage._refresh_diagnostic()
		check(garage.diagnostic_recover.visible and not garage.diagnostic_recover.disabled, state + " offers recovery")
		var cash: int = player.money
		garage.diagnostic_recover.pressed.emit()
		check(car.global_position.is_equal_approx(manager.bay_position()) and car.visible and not car.is_broken, state + " returns a working car to the bay")
		check(player.money == cash - 50 and car.get_instance_id() == identity and player.personal_loadout == equipment, state + " charges once and preserves car identity and equipment")
		garage._recover_from_diagnostic()
		check(player.money == cash - 50 and not garage.diagnostic_recover.visible, "Repeated recovery cannot charge again")
	car.global_position = Vector2(1000, 1000)
	player.money = 49
	garage._refresh_diagnostic()
	check(garage.diagnostic_recover.visible and garage.diagnostic_recover.disabled, "Insufficient funds disables recovery")
	garage._recover_from_diagnostic()
	check(player.money == 49 and car.global_position == Vector2(1000, 1000), "Rejected recovery preserves money and car position")
	car.unlocked = false
	garage._refresh_diagnostic()
	check(not garage.diagnostic_recover.visible, "Locked reward cannot be recovered early")
	print("GARAGE_DIAGNOSTIC_RECOVERY failures=", failures)
	scene.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
