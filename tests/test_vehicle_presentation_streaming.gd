extends SceneTree

func _initialize() -> void:
	call_deferred("run_test")

func run_test() -> void:
	var world := Node2D.new()
	root.add_child(world)
	current_scene = world
	var budget = root.get_node("PresentationBudget")
	budget.set_process(false)
	await process_frame
	var pool = root.get_node("EmergencyPool")
	for service in ["police", "ambulance", "fire", "coroner"]:
		var unit = pool.get_vehicle(service)
		assert(unit != null and unit.body_model != null)
		assert(unit.get_node("CollisionShape2D").shape.size.x > 0)
		pool.return_vehicle(unit)
		var again = pool.get_vehicle(service)
		assert(again == unit)
		pool.return_vehicle(again)
	var car = preload("res://world/shared/emergency/ModernTrafficFactory.gd").spawn_parked_vehicle(world, "Teste", Vector2(100000, 100000), 0, "summit_suv", 0, Color.BLUE)
	assert(car.body_viewport == null)
	var size: Vector2 = car.collision.shape.size
	car.repaint_vehicle(Color.RED)
	budget._process(0.016)
	assert(car.body_viewport == null)
	car.position = Vector2(100, 100)
	budget._process(0.016)
	assert(car.body_viewport != null)
	assert(car.body_model.paint.albedo_color == Color.RED)
	assert(car.collision.shape.size.is_equal_approx(size))
	car.ensure_presentation()
	world.free()
	budget._process(0.016)
	print("VEHICLE_STREAMING: cor, colisão, proximidade e troca de cena aprovadas")
	quit(0)
