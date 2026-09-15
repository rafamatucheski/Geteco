extends SceneTree
## Production scene, keyboard/board/modal and day-gate integration.
## Travel is fixture-positioned; physical driving/combat have separate tests.
var failures: Array[String] = []
var world: Node2D
var bridge: CanvasLayer
var player: CharacterBody2D

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)

func frames(count: int = 4) -> void:
	for i in count:
		await physics_frame

func key(code: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = pressed
		Input.parse_input_event(event)
		await frames(3)

func _run() -> void:
	create_timer(160,true,false,true).timeout.connect(func(): printerr("CAMPAIGN_UI_TIMEOUT"); quit(2))
	var campaign := root.get_node("CampaignState")
	campaign.reset_campaign()
	root.get_node("SaveManager").clear_pending_save()
	for flag in ["harbor_arrival_seen", "harbor_arrival_call_complete", "harbor_maciota_met", "harbor_delivery_started", "harbor_delivery_complete"]:
		campaign.set_campaign_flag(StringName(flag), true)
	world = load("res://world/harbor/HarborGame.tscn").instantiate()
	root.add_child(world)
	current_scene = world
	while not world.gameplay_ready: await process_frame
	await frames(20)
	bridge = world.get_node("CobraCampaign")
	player = world.get_node("Player")
	var garage: Node2D = bridge.garage
	var board: Node2D = bridge.board
	check(not paused, "Completed arrival fixture does not reopen CGI")
	check(board.campaign_missions.size() == 7, "Seven fixed campaign rows, no generated jobs")
	check(bridge.ledger.get_status("cobra_contact").available, "First follow-up available immediately")
	check(not bridge.rest(), "Cannot rest remotely in the street")
	bridge._selected("cobra_contact")
	check(bridge.runtime.active_id.is_empty(), "Remote selection cannot start mission")
	var garage_door: Node2D = world.get_node("District/Garage/Entrance")
	player.global_position = garage_door.get_node("OutsideReturn").global_position
	await frames(8)
	check(garage_door.request_interaction(player), "UI fixture enters garage through real door")
	await create_timer(1.1).timeout
	check(garage.contains_point(player.global_position), "Garage transition finishes before journal interactions")
	player.global_position = garage.jager_npc.global_position + Vector2(0, 45)
	await frames(5)
	await key(KEY_J)
	check(bridge._journal.visible and player.is_control_disabled, "J opens journal and locks movement")
	if "--capture" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png("D:/geteco/cobra-campaign-journal.png") == OK, "Rendered journal capture saved")
	check(bridge.can_rest(), "Rest available near Maciota with no pursuit: "+bridge._rest_block_reason())
	bridge._rest_button.pressed.emit()
	await create_timer(1.5).timeout
	check(int(bridge.ledger.data.day) == 2, "Rest advances one game day")
	check(not player.is_control_disabled and not bridge._fade.visible, "Rest fade returns controls")
	check(bridge.runtime.active_id.is_empty(), "Rest never auto-starts mission")
	player.global_position = board.global_position
	await frames(8)
	check(player.global_position.distance_to(board.global_position) < board.interaction_radius, "Player stands at authored board interaction point")
	await key(KEY_E)
	check(board.is_ui_open, "Native E opens existing fixed board")
	var button: Button
	for child in board.orders_vbox.get_children():
		if child is Button and not child.disabled and not child.is_queued_for_deletion():
			button = child
			break
	check(button != null, "Contact has enabled board row on day two")
	if button != null:
		button.pressed.emit()
	await create_timer(.9).timeout
	check(bridge.runtime.active_id == "cobra_contact", "Real board selection reaches Cobra controller")
	check(bridge._dialog.visible and player.is_control_disabled, "Briefing is a modal dialogue")
	await key(KEY_ENTER)
	check(not bridge._dialog.visible and not player.is_control_disabled, "Enter dismisses briefing safely")
	check(not bridge.can_rest(), "Cannot skip day during active mission")
	player.global_position = bridge.runtime.WORKSHOP + Vector2(0, 40)
	await frames()
	var cash: int = player.money
	await key(KEY_E)
	check(bridge._dialog.visible and bridge.runtime.stage == 1, "Native E at Ferrugem opens contact conversation")
	await key(KEY_ENTER)
	# A second E would legitimately enter a nearby vehicle once the contact
	# has no conversation pending. Check the contact API, without boarding.
	check(not bridge.runtime.interact(), "Second contact interaction waits for the physical recovery")
	check(not bool(bridge.ledger.data.completed.get("cobra_contact", false)), "Talking twice cannot bypass the real recovery")
	check(player.money == cash, "Contact does not pay before recovering the customer car")
	while bridge._dialog.visible:
		await key(KEY_ENTER)
	# Remaining cases exercise journal/rest/race UI with a declared completed
	# prerequisite. Real recovery, payment and loaded save/restore are exercised
	# by test_first_favors.gd with the production flatbed and its physics.
	bridge.runtime.fail_mission("UI fixture ends recovery; its physical flow has a dedicated integration test.")
	while bridge._dialog.visible: await key(KEY_ENTER)
	check(bridge.ledger.begin("cobra_contact") and bridge.ledger.complete(), "UI fixture installs completed contact prerequisite")
	bridge._refresh()
	check(bridge.ledger.get_status("cobra_race").available, "Race UI recognizes completed prerequisite")
	check(player.money == cash, "UI prerequisite fixture does not invent payment")
	await key(KEY_J)
	check(bridge._journal.visible and bridge._entries.text.contains("[s]"), "Journal strikes completed missions")
	var locale := TranslationServer.get_locale()
	TranslationServer.set_locale("en")
	bridge._refresh()
	check(bridge._entries.text.contains("CHAPTER ONE") and bridge._rest_button.text == "Rest until tomorrow · optional", "Journal and optional rest expose English text")
	TranslationServer.set_locale(locale)
	await key(KEY_ESCAPE)
	check(not player.is_control_disabled, "Journal close restores movement")
	check(not paused, "Escape closes only the journal, not the global pause menu")
	player.global_position = garage_door.get_node("OutsideReturn").global_position
	await frames(8)
	check(garage_door.request_interaction(player), "UI fixture returns through garage door before second rest")
	await create_timer(1.1).timeout
	player.global_position = garage.jager_npc.global_position + Vector2(0, 45)
	await frames()
	check(bridge.rest(), "Second rest remains available after mission completion")
	await create_timer(1.5).timeout
	player.global_position = board.global_position
	bridge._selected("cobra_race")
	await create_timer(.9).timeout
	await key(KEY_ENTER)
	var car: CharacterBody2D = world.get_node("PlayerCar")
	car.global_position = bridge.runtime.RACE_START
	car.global_rotation = -PI/2
	car.velocity = Vector2.ZERO
	player.global_position = car.global_position + Vector2(-45, 0)
	car.enter_vehicle(player)
	while car.has_meta("vehicle_boarding"): await process_frame
	await frames()
	await key(KEY_R)
	# The authorized street closure must drain real traffic before counting down.
	# UI proves the request and explanation; the physical race test proves drain
	# and full lap. Neither condition may silently remove the driver.
	var traffic: Node = bridge.runtime._race_traffic
	var waiting_for_traffic: bool = is_instance_valid(traffic) and traffic.remaining > 0 and bridge.runtime.get_status().message.contains(str(traffic.remaining))
	check(car.is_driven_by_player and (bridge.runtime._race_started or waiting_for_traffic), "R preserves driver and starts or explicitly explains traffic preparation: "+str(bridge.runtime.get_status()))
	check(bridge._dialog.visible, "Race preparation or rules open in production dialogue")
	var stopped := car.global_position
	Input.action_press("ui_up")
	await frames(20)
	Input.action_release("ui_up")
	check(car.global_position.distance_to(stopped) < 0.1, "Dialogue also suspends real vehicle controller")
	await key(KEY_ENTER)
	bridge.runtime.fail_mission("Fixture ends the race; driving has a separate real-input test.")
	await key(KEY_ENTER)
	car.exit_vehicle()
	while car.has_meta("vehicle_boarding"): await process_frame
	await create_timer(.9).timeout
	var snapshot: Dictionary = JSON.parse_string(JSON.stringify(campaign.to_save_data()))
	campaign.restore_from_save(snapshot)
	await frames()
	check(bool(bridge.ledger.data.completed.get("cobra_contact", false)), "Integrated ledger follows restored save namespace")
	await key(KEY_J)
	check(paused and bridge._journal.visible, "Journal pauses existing projectiles as well as controls")
	world.queue_free()
	await frames(5)
	check(not paused, "Leaving scene with a modal cannot leave the next scene paused")
	print("COBRA CAMPAIGN GAMEPLAY: %d failure(s)" % failures.size())
	quit(0 if failures.is_empty() else 1)
