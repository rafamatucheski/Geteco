extends SceneTree
const MOTION := preload("res://cars/VehicleMotionSafety.gd")
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	var manager := root.get_node("TrafficLightManager")
	manager.register_intersection(&"fragile_test", Vector2(4000,4000), 100)
	var signal_post = manager._visual_sets[&"fragile_test"].get_child(0)
	var lamp = load("res://StreetLamp.gd").new()
	lamp.position = Vector2(4300,4000)
	root.add_child(lamp)
	for post in [lamp, signal_post]:
		var center: Vector2 = post.global_position + (Vector2(0,9) if post == signal_post else Vector2.ZERO)
		var body := CharacterBody2D.new()
		body.collision_layer = 2
		body.collision_mask = 1
		var shape := CollisionShape2D.new()
		shape.shape = CircleShape2D.new()
		shape.shape.radius = 10
		body.add_child(shape)
		root.add_child(body)
		body.global_position = center - Vector2(35,0)
		MOTION.configure(body)
		for i in 25:
			await physics_frame
			body.velocity = Vector2(160,0)
			body.move_and_slide()
		assert(not post.broken and body.global_position.x < center.x - 10, "Walking cannot topple or cross a post")
		post.receive_vehicle_impact(0, Vector2.RIGHT)
		post.receive_vehicle_impact(25, Vector2.RIGHT)
		await create_timer(.16).timeout
		assert(not post.broken, "Parking contact only wobbles")
		body.global_position = center - Vector2(35,0)
		var retained := false
		for i in 40:
			await physics_frame
			body.velocity = Vector2(80,0)
			MOTION.move(body)
			if post.broken and body.velocity.x > 75: retained = true
		assert(post.broken and retained, "Modest impact topples pole without wall stop, even during wobble cooldown")
		assert(body.global_position.x > center.x + 10, "Car crosses released base")
		await create_timer(.8).timeout
		assert(post.collision_layer == 0)
		if post == signal_post:
			manager._advance_phase()
			assert(post.get_node("SignalBox/Red").color == Color("202428"), "Cycle cannot relight fallen signal")
			assert(absf(post.rotation) > 1.4)
		else:
			assert(post.model.quaternion.get_angle() > 1.4)
		post.restore_world_prop()
		await physics_frame
		assert(not post.broken and post.collision_layer == 1, "Renewal restores solid pole")
		body.queue_free()
	manager.unregister_intersection(&"fragile_test")
	lamp.queue_free()
	await process_frame
	print("FRAGILE_ROAD_POSTS PASS: walking, parking, modest collision, passage, lights, renewal")
	quit()
