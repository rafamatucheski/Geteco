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
	while not scene.region_ready or not scene.interior_manager.region_ready: await process_frame
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
	actor.global_position = scene.interior_manager.cabin_interior.spawn_point.global_position
	await process_frame
	await process_frame
	check(scene.storm_manager.sheltered and not scene.cold_controller.is_in_cold_zone(), "physical cabin shelters from cold")
	actor.global_position = Vector2(5980, 600)
	await process_frame
	await process_frame
	check(scene.storm_manager.visible, "snow returns outside")
	var door := scene.get_node("MountainExpedition/SnowOutfitters/OutfittersEntrance") as BuildingEntrance
	var room: Node2D = scene.interior_manager.get_interior(&"mountain_outfitters")
	var outside := door.global_position + Vector2(0, 24)
	actor.global_position = outside
	for i in 8: await physics_frame
	check(await walk_to(actor, room.to_global(room.project_floor(Vector2(0, 0.5)))), "walk into the clothing shop through its door")
	for i in 5: await process_frame
	check(room.contains_point(actor.global_position) and room._inline_occupied, "clothing shop opens at its physical facade")
	check(not room.shop.is_active and not actor.is_in_dialogue, "arrival does not open the clothing menu")
	actor.money = 5000
	check(await walk_to(actor, room.to_global(room._counter_point)), "counter is reachable on foot")
	var key := InputEventAction.new()
	key.action = "interact"
	key.pressed = true
	room._unhandled_input(key)
	check(room.shop.is_active and actor.is_in_dialogue, "counter opens shop and holds movement")
	room.shop._on_action_pressed()
	check(actor.money == 3200 and actor.mountain_thermal_coat, "coat purchase exact catalog charge")
	room.shop._on_action_pressed()
	check(actor.money == 3200, "coat cannot charge twice")
	for i in 3: await process_frame
	check(room.shop.is_active and actor.is_in_dialogue and not scene.cold_hud._panel.is_visible_in_tree(), "cold HUD stays behind clothing modal")
	room.shop.close_store()
	check(not actor.is_in_dialogue, "closing store releases movement")
	check(await walk_to(actor, room.to_global(room.project_floor(Vector2(0, 0.5)))), "leave the counter through the clear aisle")
	check(await walk_to(actor, outside), "walk back out through the shop door")
	for i in 5: await process_frame
	check(not actor.has_meta("mountain_interior") and not room._inline_occupied, "walking out clears shop shelter identity")
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

func walk_to(actor: CharacterBody2D, target: Vector2) -> bool:
	for _step in 300:
		var motion := target - actor.global_position
		if motion.length() < 2.0: return true
		if actor.move_and_collide(motion.limit_length(2.5)) != null: return false
		await physics_frame
	return false
