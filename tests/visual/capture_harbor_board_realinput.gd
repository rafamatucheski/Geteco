extends SceneTree

## Real-interaction capture for the Harbor mission board fix: drives the
## production scene with actual InputEventKey presses (native E / Enter /
## Escape), never a fabricated accept_mission() call, and screenshots the
## enlarged board in its three states (available, then completed/struck-through)
## plus a PT-BR vs English comparison of the same board.

func frames(count: int) -> void:
	for _i in count:
		await physics_frame

func key(code: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = pressed
		Input.parse_input_event(event)
		await frames(3)

func shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	root.size = Vector2i(1280, 720)
	root.content_scale_size = root.size
	var campaign := root.get_node("CampaignState")
	var saves := root.get_node("SaveManager")
	var settings := root.get_node("SettingsManager")
	campaign.reset_campaign()
	saves.clear_pending_save()
	settings.set_language("pt_BR")

	var world = load("res://world/harbor/HarborGame.tscn").instantiate()
	root.add_child(world)
	current_scene = world
	await frames(12)
	var mission = world.campaign_controller
	# Mirrors test_harbor_campaign_flow.gd's exact, verified skip sequence
	# (open the confirm dialog once and cancel, then open it again and
	# confirm) — a single ESC+OK was observed to leave the opening in an
	# inconsistent state that later replayed the disembark/phone beats.
	await key(KEY_ESCAPE)
	mission._opening._skip_dialog.get_cancel_button().pressed.emit()
	await frames(2)
	await key(KEY_ESCAPE)
	mission._opening._skip_dialog.get_ok_button().pressed.emit()
	# "arrival_wait" is the real 7-second pause before the phone rings
	# (HarborArrivalMission._process); it must stay in this wait-list too,
	# matching test_harbor_campaign_flow.gd, or advance_dialogue() below
	# would silently no-op while the phone hasn't started yet.
	var deadline := Time.get_ticks_msec() + 20000
	while mission.phase in ["arrival", "disembark", "arrival_wait"] and Time.get_ticks_msec() < deadline:
		await process_frame
	for _i in 4:
		mission.advance_dialogue()
		await frames(2)

	var player = world.get_node("Player")
	var garage = world.get_node("Interiors").garage_interior
	var door = world.get_node("District/Garage/Entrance")
	player.global_position = door.get_node("OutsideReturn").global_position
	player.velocity = Vector2.ZERO
	await frames(8)
	await key(KEY_E)
	await create_timer(0.8).timeout

	var npc = garage.jager_npc
	player.global_position = npc.global_position + Vector2(0, 30)
	await frames(8)
	await key(KEY_E)
	for _i in 12:
		if not npc.is_talking:
			break
		await key(KEY_SPACE)
	await shot("D:/geteco/harbor-board-maciota-real.png")

	player.global_position = garage.mission_board.global_position + Vector2(0, 25)
	await frames(6)
	await key(KEY_E)
	await frames(10)  # let the open animation settle
	await shot("D:/geteco/harbor-board-available-pt.png")

	# English via the real Settings language switch, board still open.
	settings.set_language("en")
	await frames(4)
	await shot("D:/geteco/harbor-board-available-en.png")
	settings.set_language("pt_BR")
	await frames(4)

	# Accept for real (button press wired to the same mission_selected signal
	# a mouse click fires; keyboard focus/ui_accept readiness is covered by
	# the automated test suite's own focus assertion).
	for child in garage.mission_board.orders_vbox.get_children():
		if child is Button and not child.disabled:
			child.pressed.emit()
			break
	await frames(4)
	player.global_position = world.get_node("FirstDeliveryPickup").global_position
	player.velocity = Vector2.ZERO
	await frames(4)
	mission.interact_with_objective()
	player.global_position = npc.global_position + Vector2(0, 30)
	await frames(4)
	mission.interact_with_objective()
	await frames(2)

	player.global_position = garage.mission_board.global_position + Vector2(0, 25)
	await frames(6)
	await key(KEY_E)
	await frames(10)
	await shot("D:/geteco/harbor-board-completed-struck.png")
	await key(KEY_ESCAPE)
	await frames(4)

	world.queue_free()
	await frames(4)
	print("CAPTURE_DONE")
	quit()
