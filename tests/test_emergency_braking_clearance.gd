extends SceneTree
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var world := Node2D.new()
	root.add_child(world)
	current_scene = world
	var failures := 0
	for kind in [0,1,2,3]:
		var unit := preload("res://emergency/EmergencyVehicle.tscn").instantiate()
		unit.type = kind
		world.add_child(unit)
		unit.activate()
		unit.set_physics_process(false)
		var wall := StaticBody2D.new()
		var shape := CollisionShape2D.new()
		shape.shape = RectangleShape2D.new()
		shape.shape.size = Vector2(4,200)
		wall.add_child(shape)
		world.add_child(wall)
		wall.position.x = unit.get_node("CollisionShape2D").shape.get_rect().end.x+60
		await physics_frame
		var distance: float = unit._forward_clearance()
		if distance < 50 or distance > 60: failures += 1
		print("BRAKING type=",kind," clearance=",distance)
		wall.position.x = 0
		await physics_frame
		if unit._forward_clearance() != 0: failures += 1
		wall.queue_free()
		unit.queue_free()
		await process_frame
	world.queue_free()
	await process_frame
	print("BRAKING_CLEARANCE failures=",failures)
	quit(0 if failures==0 else 1)
