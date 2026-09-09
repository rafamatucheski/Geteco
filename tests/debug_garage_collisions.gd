extends SceneTree

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var proposal_scene = load("res://prototypes/garage/GarageVisualProposal.tscn")
	var garage = proposal_scene.instantiate()
	root.add_child(garage)

	for i in range(10):
		await physics_frame

	var veh := CharacterBody2D.new()
	veh.name = "TestRealVehicle"
	veh.collision_layer = 2
	veh.collision_mask = 1

	var col := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(72, 34)
	col.shape = rect
	veh.add_child(col)
	garage.add_child(veh)

	veh.position = Vector2(0, 215)
	veh.rotation = -PI * 0.5 # Norte

	print("STARTING VEHICLE AT: ", veh.position)
	var waypoints = [Vector2(0, 95), Vector2(65, 30), Vector2(140, -20)]
	for i in range(waypoints.size()):
		var target: Vector2 = waypoints[i]
		print("--- Navigating to waypoint ", i, ": ", target)
		var reached := false
		for f in range(150):
			var diff := target - veh.position
			if diff.length() <= 15.0:
				reached = true
				print("  Reached waypoint ", i, " at frame ", f, " pos: ", veh.position)
				break
			var dir := diff.normalized()
			veh.rotation = lerp_angle(veh.rotation, dir.angle(), 0.15)
			veh.velocity = dir * 180.0
			veh.move_and_slide()
			await physics_frame

		print("  End of wp ", i, " pos: ", veh.position, " reached: ", reached)

	quit(0)
