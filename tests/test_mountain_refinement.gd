extends SceneTree
var failures := 0
func _init() -> void:
	call_deferred("run")
func check(value: bool, text: String) -> void:
	print(("PASS " if value else "FAIL ") + text)
	if not value:
		failures += 1
func run() -> void:
	var scene = load("res://world/mountain_pass/MountainPass.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await physics_frame
	await physics_frame
	var actor = scene.player_instance
	actor.set_physics_process(false)
	check(scene.has_node("HarborReturnCrossing"), "official Harbor return")
	actor.global_position = Vector2(5350, 400)
	await process_frame
	await process_frame
	check(scene.storm_manager.sheltered and not scene.storm_manager.visible, "tunnel blocks precipitation")
	check(scene.main_camera.get_meta("mountain_zoom", 0) == 2.5, "tunnel close camera")
	var query := PhysicsRayQueryParameters2D.create(Vector2(5350, 400), Vector2(5350, 550), 1)
	query.exclude = [actor.get_rid()]
	check(not scene.get_world_2d().direct_space_state.intersect_ray(query).is_empty(), "physical tunnel wall blocks lateral escape")
	actor.set_meta("mountain_interior", true)
	actor.global_position = Vector2(22500, 20000)
	await process_frame
	await process_frame
	check(scene.storm_manager.sheltered and not scene.cold_controller.is_in_cold_zone(), "cabin shelter across room")
	actor.remove_meta("mountain_interior")
	actor.global_position = Vector2(5980, 600)
	await process_frame
	await process_frame
	check(scene.storm_manager.visible, "snow returns outside")
	var door = scene.get_node("MountainExpedition/SnowOutfitters/OutfittersEntrance")
	actor.global_position = door.global_position + Vector2(0,24)
	for i in 4: await physics_frame
	check(door.request_interaction(actor), "native outfitters entrance accepts player")
	await create_timer(.8).timeout
	var room = scene.interior_manager._interiors[&"mountain_outfitters"]
	check(room.contains_point(actor.global_position), "single mountain door reaches clothing shop")
	check(not room._at_counter(actor), "arrival and exit do not open the clothing menu")
	actor.money = 5000
	actor.global_position = room.global_position
	var key := InputEventAction.new()
	key.action = "interact"
	key.pressed = true
	room._unhandled_input(key)
	check(room.shop.is_active and actor.is_in_dialogue, "counter opens shop and holds movement")
	room.shop._on_action_pressed()
	check(actor.money == 3200 and actor.mountain_thermal_coat, "coat purchase exact catalog charge")
	room.shop._on_action_pressed()
	check(actor.money == 3200, "coat cannot charge twice")
	await process_frame
	check(not scene.cold_hud._panel.visible, "cold HUD stays behind clothing modal")
	room.shop.close_store()
	check(not actor.is_in_dialogue, "closing store releases movement")
	actor.global_position=room.exit_door.global_position+Vector2(0,-20)
	for i in 4: await physics_frame
	check(room.exit_door.request_interaction(actor), "native shop exit accepts player")
	await create_timer(.8).timeout
	check(not actor.has_meta("mountain_interior"), "shop exit clears shelter identity")
	var saved: Dictionary = actor.serialize()
	actor.mountain_thermal_coat = false
	actor.restore(saved)
	check(actor.mountain_thermal_coat, "coat survives serialization roundtrip")
	actor.health = 100
	actor.armor = 100
	actor.take_environment_damage(5)
	check(actor.health == 95 and actor.armor == 100, "cold damages health bypassing armor")
	for angle in [0.0, PI / 2, PI, -PI / 2]:
		scene.suv_instance.rotation = angle
		scene.suv_instance._physics_process(0.016)
		check(scene.suv_instance.headlight.global_position.is_finite(), "projected lamp heading " + str(angle))
	scene.queue_free()
	await process_frame
	print("MOUNTAIN REFINEMENT FAILURES: ", failures)
	quit(failures)
