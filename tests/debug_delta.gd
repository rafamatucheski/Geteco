extends SceneTree

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var veh := CharacterBody2D.new()
	var col := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(72, 34)
	col.shape = rect
	veh.add_child(col)
	root.add_child(veh)

	veh.position = Vector2(0, 180)
	print("delta time in process_frame: ", veh.get_physics_process_delta_time())
	print("process delta time: ", veh.get_process_delta_time())

	veh.velocity = Vector2(0, -150)
	for i in 5:
		var before = veh.position
		veh.move_and_slide()
		print("frame ", i, " moved: ", veh.position - before, " dt: ", veh.get_physics_process_delta_time())
		await process_frame

	for i in 5:
		var before = veh.position
		veh.move_and_slide()
		print("physics frame ", i, " moved: ", veh.position - before, " dt: ", veh.get_physics_process_delta_time())
		await physics_frame

	quit(0)
