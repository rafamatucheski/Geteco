extends SceneTree

var failures := 0
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
func _init() -> void: call_deferred("run")
func run() -> void:
	var scene = load("res://world/harbor/HarborPreview.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	for i in 8: await physics_frame
	var car = scene.get_node("PlayerCar")
	var player = scene.get_node("Player")
	check(car.max_speed == 450,"Must preserve Harbor speed preset")
	check(car.get_node("Collision").shape.size == Vector2(72,31),"Wrong physical size")
	check(car.spinners.size() == 4,"Missing animated wheels")
	scene._drive()
	await create_timer(0.5).timeout
	check(car.is_driven_by_player and not player.visible,"Boarding contract failed")
	var beam_key := InputEventKey.new()
	beam_key.physical_keycode = KEY_K
	beam_key.pressed = true
	car._unhandled_key_input(beam_key)
	check(car.high_beam and is_equal_approx(car.second_headlight.texture_scale,0.9),"High beam control failed")
	var start: Vector2 = car.global_position
	var angle: float = car.spinners[0].rotation.x
	var updates_before: int = car.appearance_updates
	Input.action_press("ui_up")
	for i in 24: await physics_frame
	Input.action_release("ui_up")
	check(car.global_position.distance_to(start) > 5,"Existing controller did not move coupe")
	check(absf(car.spinners[0].rotation.x-angle) > 0.1,"Wheels did not spin")
	check(car.appearance_updates - updates_before >= 22,"Driven car must refresh its moving pose at physics cadence, not half rate")
	# A real 2D barrier tests move_and_slide -> inherited impact -> 3D mesh.
	var test_garage: Node2D = scene.get_node("Interiors").garage_interior
	car.global_position = test_garage.global_position + Vector2(0,150)
	car.rotation = -PI/2
	car.velocity = Vector2.ZERO
	var wall := StaticBody2D.new()
	wall.position = test_garage.global_position + Vector2(0,-70)
	var shape := CollisionShape2D.new()
	var box := RectangleShape2D.new()
	box.size = Vector2(100,20)
	shape.shape = box
	wall.add_child(shape)
	scene.add_child(wall)
	await physics_frame
	Input.action_press("ui_up")
	for i in 100:
		await physics_frame
		if car.body_model.impact_count > 0: break
	Input.action_release("ui_up")
	print("COUPE_WALL position=%s velocity=%s driven=%s health=%d" % [car.global_position,car.velocity,car.is_driven_by_player,car.health])
	check(car.body_model.impact_count > 0,"Physical 2D wall did not trigger mesh damage")
	check(car.global_position.y > wall.position.y+10,"Car passed through physical wall")
	car.repair_vehicle()
	wall.queue_free()
	car.global_position = start
	car._visual_damage_cooldown = 0
	car.velocity = Vector2.ZERO
	car._apply_crash_deformation(-car.global_transform.x,200,car.to_global(Vector2(32,-11)))
	check(car.body_model.max_deformation() > 0,"2D collision failed to deform 3D body")
	check(car.body_model.broken_lamps[0] and not car.body_model.broken_lamps[1],"Wrong headlight broken")
	check(not car.headlight.visible and car.second_headlight.visible,"2D damaged lamp mismatch")
	var garage = scene.get_node("Interiors").garage_interior
	var bay = garage.get_node("PaintAndSpray")
	check(not bay.eligible(car),"Remote car may not repaint")
	# Place inside bay to isolate color selection contract. Existing gameplay
	# suite separately drives through the actual garage entrance and exit.
	car.global_position = garage.global_position + Vector2(0,100)
	car.velocity = Vector2.ZERO
	for i in 20: await physics_frame
	check(bay.eligible(car) and bay.panel.visible,"Paint bay did not detect stopped driver")
	bay.paint_car(1)
	check(bay.busy and not car.is_physics_processing(),"Painting must lock driving temporarily")
	await create_timer(1.0).timeout
	check(bay.paints_completed == 1 and car.paint_color == bay.COLORS[1],"Selected paint did not apply")
	check(car.body_model.paint.albedo_color == bay.COLORS[1],"Paint altered wrong material")
	check(car.sprite.modulate == Color.WHITE,"Repaint must not tint windows and wheels")
	check(car.body_model.max_deformation() == 0 and car.health == car.max_health,"Paint service did not repair")
	check(car.headlight.visible and car.second_headlight.visible,"Repair did not restore 2D lights")
	check(car.is_physics_processing(),"Painting left controls locked")
	car.exit_vehicle()
	await create_timer(0.5).timeout
	check(player.visible and not car.is_driven_by_player,"Exit contract failed")
	print("HARBOR_COUPE_RESULT failures=%d paint_jobs=%d updates=%d" % [failures,bay.paints_completed,car.appearance_updates])
	scene.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)
