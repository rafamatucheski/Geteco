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
	var expedition = scene.get_node("MountainExpedition")
	var key := InputEventKey.new()
	key.physical_keycode = KEY_F
	key.pressed = true
	actor.money = 1000
	expedition._unhandled_key_input(key)
	check(actor.money == 350 and actor.mountain_thermal_coat, "coat purchase exact charge")
	expedition._unhandled_key_input(key)
	check(actor.money == 350, "coat cannot charge twice")
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
