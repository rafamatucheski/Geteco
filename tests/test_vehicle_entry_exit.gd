extends SceneTree

func _init():
	call_deferred("_run_test")

func _run_test():
	await process_frame

	var player = get_first_node_in_group("player")
	var vehicle = get_first_node_in_group("vehicle")

	if not player or not vehicle:
		print("ERROR: Player or vehicle not found")
		quit(1)
		return

	print("Initial state:")
	print("  Player physics_process: ", player.is_physics_processing())
	print("  Player is_control_disabled: ", player.is_control_disabled)
	print("  Player visible: ", player.visible)

	# Enter vehicle
	print("\n=== ENTERING VEHICLE ===")
	vehicle.enter_vehicle(player)

	await create_timer(2.5).timeout

	print("\nAfter boarding animation:")
	print("  Player physics_process: ", player.is_physics_processing())
	print("  Player is_control_disabled: ", player.is_control_disabled)
	print("  Player visible: ", player.visible)
	print("  Vehicle is_driven_by_player: ", vehicle.is_driven_by_player)

	# Exit vehicle
	print("\n=== EXITING VEHICLE ===")
	vehicle.exit_vehicle()

	await create_timer(1.0).timeout

	print("\nAfter exit:")
	print("  Player physics_process: ", player.is_physics_processing())
	print("  Player is_control_disabled: ", player.is_control_disabled)
	print("  Player visible: ", player.visible)
	print("  Vehicle is_driven_by_player: ", vehicle.is_driven_by_player)

	# Check final state
	print("\n=== FINAL STATE CHECK ===")
	var is_physics_ok = player.is_physics_processing()
	var is_control_ok = not player.is_control_disabled
	var is_visible_ok = player.visible

	print("Player can receive input: ", is_control_ok)
	print("Player physics enabled: ", is_physics_ok)
	print("Player visible: ", is_visible_ok)

	if is_physics_ok and is_control_ok and is_visible_ok:
		print("\nSUCCESS: Player is in correct state to move after exiting vehicle")
		quit(0)
	else:
		print("\nFAILURE: Player state is invalid:")
		print("  physics_process: ", is_physics_ok)
		print("  is_control_disabled: ", not is_control_ok)
		print("  visible: ", is_visible_ok)
		quit(1)
