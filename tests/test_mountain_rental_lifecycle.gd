extends SceneTree
var failures := 0

func _initialize() -> void: run.call_deferred()

func check(ok: bool, message: String) -> void:
	print(("PASS " if ok else "FAIL ") + message)
	if not ok: failures += 1

func run() -> void:
	root.get_node("SaveManager")._save_dir = "D:/geteco/artifacts/mountain-review-0913/saves/"
	root.get_node("SaveManager")._save_directory_ready = false
	var player := preload("res://Player.gd").new()
	var camera := Camera2D.new()
	camera.name = "Camera"
	player.add_child(camera)
	root.add_child(player)
	player.set_physics_process(false)
	player.money = 1000
	var original_outfit := player.current_outfit_id
	player.start_skiing()
	check(not player.is_skiing, "Starting without rental does not enter ski physics")
	player.take_ski_equipment()
	check(not player.ski_equipment_ready, "Equipment requires an active rental")
	check(not player.begin_ski_rental(-250) and player.money == 1000, "Invalid price cannot credit money")
	check(player.begin_ski_rental(250), "Valid rental succeeds")
	check(not player.begin_ski_rental(250) and player.money == 750, "Duplicate rental neither charges nor overwrites previous clothes")
	player.take_ski_equipment()
	player.start_skiing()
	check(player.is_skiing and player.ski_controller.visual_root.visible, "Valid skier has controller and equipment")
	await physics_frame
	var start := player.position
	player._physics_process(1.0 / 60.0)
	check((player.position - start).is_equal_approx(player.get_position_delta()), "Ski controller moves the actor exactly once per physics step")
	for speed_factor in [0.0,.5,1.0]:
		player.ski_controller._apply_pose(speed_factor,.6)
		for upper in [player.left_upper_leg,player.right_upper_leg]:
			var lower: Node3D = player.left_lower_leg if upper==player.left_upper_leg else player.right_lower_leg
			var sole: Vector3 = upper.transform*lower.transform*Vector3(0,-.33,0)
			check(absf(sole.y-.08)<.002 and absf(sole.z)<.002,"Dante keeps both boots on the bindings at speed %s"%speed_factor)
	check(player.ski_controller.poles.size()==2 and player.ski_controller.poles[0].get_parent()==player.left_lower_arm,"Dante poles follow his hands")
	player.ski_controller._update_trails(0.1)
	player.return_ski_rental()
	check(not player.is_skiing and not player.ski_controller.visual_root.visible and player.ski_controller.trail_left.get_point_count() == 0, "Returning equipment stops physics, hides skis and clears tracks")
	check(player.current_outfit_id == original_outfit and not player.ski_rental_active, "Original clothes restored after repeated rental attempt")
	player.return_ski_rental()
	check(player.current_outfit_id == original_outfit, "Repeated return is harmless")
	player.queue_free()
	await process_frame
	quit(failures)
