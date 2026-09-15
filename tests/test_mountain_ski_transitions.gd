extends SceneTree

var failures := 0

class Rider extends CharacterBody2D:
	var is_dead := false
	var is_control_disabled := false
	var is_in_dialogue := false
	var is_recovering := false
	var current_vehicle: Node
	var is_skiing := false
	var ski_equipment_ready := false
	func _show_weapon_notice(_text: String) -> void: pass
	func stop_skiing() -> void: is_skiing = false
	func start_skiing(_direction: Vector2) -> void: is_skiing = true

func _initialize() -> void: run.call_deferred()

func check(condition: bool, message: String) -> void:
	print(("PASS " if condition else "FAIL ") + message)
	if not condition: failures += 1

func run() -> void:
	create_timer(30).timeout.connect(func(): quit(2))
	var world := Node2D.new()
	world.position = Vector2(4300, -4960)
	root.add_child(world)
	for angle in [-0.6, 0.0, 0.8]:
		var gate := preload("res://world/mountain_pass/MountainSkiGate.gd").new()
		gate.ground_angle = angle
		world.add_child(gate)
		var foot := gate.project_point(Vector3(1.15, 0, 0))
		var top := gate.project_point(Vector3(1.15, 1.9, 0))
		check(absf(top.x - foot.x) < 0.01 and top.y < foot.y, "Gate posts stay upright on curve %.1f" % angle)
		var across := gate.project_floor(Vector2(1.15, 0)) - gate.project_floor(Vector2(-1.15, 0))
		check(absf(angle_difference(across.angle(), angle)) < 0.01, "Gate follows the course direction %.1f" % angle)
		var post: CollisionPolygon2D = gate.get_node("RightGatePost").get_child(0)
		check(Geometry2D.is_point_in_polygon(foot, post.polygon), "Gate collision matches the rendered post %.1f" % angle)
	var rider := Rider.new()
	world.add_child(rider)
	var skis := preload("res://scripts/player/PlayerSkiController.gd").new()
	world.add_child(skis)
	skis.configure(rider)
	skis._ensure_trails()
	skis._update_trails(0.06)
	rider.position += Vector2(0, -20)
	skis._update_trails(0.06)
	check(skis.trail_left.get_point_count() == 2 and skis.trail_right.get_point_count() == 2, "Continuous movement preserves both ski tracks in the offset world")
	check(skis.trail_left.to_global(skis.trail_left.get_point_position(1)).distance_to(rider.global_position) < 4, "Tracks follow the player's feet in world coordinates")
	for i in 2:
		rider.position += Vector2(0, -22.75)
		skis._update_trails(0.05)
	check(skis.trail_left.get_point_count() == 3, "Full-speed skiing preserves tracks at a lower frame rate")
	rider.position += Vector2(0, -1700)
	skis._update_trails(0.06)
	check(skis.trail_left.get_point_count() == 1 and skis.trail_right.get_point_count() == 1, "Teleport breaks tracks instead of drawing across the mountain")
	skis._clear_trails()
	check(skis.trail_left.get_point_count() == 0 and skis.trail_right.get_point_count() == 0, "New ski session starts without old tracks")
	var lift := preload("res://world/mountain_pass/MountainSkiLift.gd").new()
	lift.is_base_station = true
	world.add_child(lift)
	lift.set_process(false)
	rider.position = lift.position
	check(lift._can_board(rider), "Free player at the station can board")
	for property in ["is_dead", "is_control_disabled", "is_in_dialogue", "is_recovering"]:
		rider.set(property, true)
		check(not lift._can_board(rider), "Lift rejects " + property)
		rider.set(property, false)
	rider.current_vehicle = world
	check(not lift._can_board(rider), "Lift cannot separate a driver from their vehicle")
	rider.current_vehicle = null
	rider.position += Vector2(500, 0)
	check(not lift._can_board(rider), "Lift requires proximity")
	rider.position = lift.position
	Input.action_press("interact")
	lift._return_to_summit(rider)
	check(lift._travelling and rider.is_control_disabled and not lift._can_board(rider), "Boarding locks controls and prevents a duplicate ride")
	await create_timer(0.15).timeout
	check(lift._travelling, "Boarding input does not skip the ride")
	Input.action_release("interact")
	await create_timer(6.1).timeout
	var summit := preload("res://world/mountain_pass/MountainSkiLayout.gd").LIFT_SUMMIT
	check(rider.global_position.distance_to(world.to_global(summit)) < 0.1 and not rider.is_control_disabled, "Ride reaches the summit using the region offset and restores controls")
	rider.position = lift.position
	lift._return_to_summit(rider)
	rider.position = Vector2(300, 600)
	var respawn := rider.global_position
	await create_timer(1.35).timeout
	check(rider.global_position == respawn and not lift._travelling and not rider.is_control_disabled, "Respawn during the ride preserves the recovery destination")
	rider.position = lift.position
	lift._return_to_summit(rider)
	rider.is_dead = true
	await process_frame
	await process_frame
	check(not lift._travelling and not rider.is_control_disabled and not rider.has_meta("mountain_lift_riding"), "Death releases the lift input lock for subsequent hospital recovery")
	# Exercise the production rig as well as the logic-only rider above.
	var dante := preload("res://characters/Player.gd").new()
	var camera := Camera2D.new()
	camera.name = "Camera"
	dante.add_child(camera)
	world.add_child(dante)
	var rig: Node3D = dante.model_root
	var home := rig.get_parent()
	var rest := rig.transform
	var leg_rest: Transform3D = dante.left_upper_leg.transform
	var presentation := preload("res://world/mountain_pass/MountainLiftRiderPresentation.gd").new()
	presentation.begin(dante,world,PackedVector2Array([Vector2.ZERO,Vector2(100,100)]))
	check(rig.get_parent()==presentation.chair.model.chair_root and not dante.sprite_3d_display.visible,"Production Dante rides inside the chair's 3D scene")
	check(not dante.is_physics_processing() and not dante.left_upper_leg.transform.is_equal_approx(leg_rest),"The seated pose locks movement during transport")
	presentation.restore()
	check(rig.get_parent()==home and rig.transform.is_equal_approx(rest) and dante.left_upper_leg.transform.is_equal_approx(leg_rest),"Disembarking restores the original rig and articulated pose")
	check(dante.is_physics_processing() and dante.sprite_3d_display.visible,"Disembarking restores Dante's physics and display")
	var station_view := Node3D.new()
	world.add_child(station_view)
	rig.reparent(station_view,false)
	presentation.restore()
	check(rig.get_parent()==station_view,"Repeated cleanup cannot steal Dante from the next station presentation")
	rig.reparent(home,false)
	world.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)
