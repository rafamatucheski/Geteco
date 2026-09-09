extends SceneTree

## Integration, not string inspection: production scene, real door sensor/input,
## finite Maciota conversation, delivery proximity, and deferred save restoration.
## Saves stay in memory; this test never overwrites the player's slots.
var failures: Array[String] = []
var world: Node2D
var player: CharacterBody2D
var mission: Node


func _initialize() -> void:
	call_deferred("_run")


func _check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)


func _frames(count: int = 4) -> void:
	for _i in count:
		await physics_frame


func _key(code: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = pressed
		Input.parse_input_event(event)
		Input.flush_buffered_events()
		await process_frame
		await _frames(3)


func _phase() -> String:
	return String(mission.get_campaign_status().get("phase", ""))


func _body_clear_at(position: Vector2) -> bool:
	var collision := player.get_node("Collision") as CollisionShape2D
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = collision.shape
	query.transform = Transform2D(player.global_rotation, position) * collision.transform
	query.collision_mask = 1
	query.exclude = [player.get_rid()]
	return world.get_world_2d().direct_space_state.intersect_shape(query).is_empty()


func _load_world() -> bool:
	var packed := load("res://world/harbor/HarborGame.tscn") as PackedScene
	if packed == null:
		_check(false, "Production HarborGame scene must load")
		return false
	world = packed.instantiate()
	root.add_child(world)
	current_scene = world
	await _frames(12)
	player = world.get_node("Player") as CharacterBody2D
	mission = null
	for node in world.find_children("*", "", true, false):
		if node.has_method("get_campaign_status") and node.has_method("skip_cinematic"):
			mission = node
			break
	_check(mission != null, "Production scene must wire the arrival mission controller")
	return mission != null


func _run() -> void:
	var campaign := root.get_node("CampaignState")
	var saves := root.get_node("SaveManager")
	campaign.reset_campaign()
	saves.clear_pending_save()
	if not await _load_world():
		quit(1)
		return
	print("CAMPAIGN: arrival and phone")
	_check(_phase() == "arrival", "New game starts with arrival, not overview or a completed mission")
	_check(player.global_position.distance_to(world.get_node("ArrivalSpawn").global_position) < 12.0, "New player starts at the bus terminal marker")
	_check(_body_clear_at(player.global_position), "Arrival fits the actual player capsule without solid overlap")
	_check(bool(mission.get_campaign_status().get("controls_locked", false)), "Arrival locks gameplay controls")
	_check(not mission.accept_mission("primeiro_giro"), "Contract cannot be accepted before the contact")
	_check(paused, "Photographic opening pauses traffic and pedestrians")
	await _key(KEY_ESCAPE)
	_check(mission._opening._skip_dialog.visible, "Escape asks before skipping")
	mission._opening._skip_dialog.get_cancel_button().pressed.emit()
	await _frames(2)
	_check(_phase() == "arrival", "Cancel keeps CGI playing")
	await _key(KEY_ESCAPE)
	mission._opening._skip_dialog.get_ok_button().pressed.emit()
	# The real opening closes through a fade and its skipped signal.
	var skip_deadline := Time.get_ticks_msec() + 20000
	while _phase() in ["arrival", "disembark", "arrival_wait"] and Time.get_ticks_msec() < skip_deadline:
		await process_frame
	_check(_phase() == "phone", "Skipping arrival leads to the phone, never skips the mission")
	_check(mission._phone_wait >= 7.0, "Phone waits seven seconds after disembark")
	_check(player.global_position.distance_to(world.get_node("ArrivalSpawn").global_position) < 3.0, "Terminal passengers do not push Dante out of his arrival spot during the phone wait")
	_check(not mission._phone_answered and mission._phone_audio.playing, "Phone actually rings before answer")
	await _key(KEY_ENTER)
	_check(mission._phone_answered, "Enter answers incoming call")
	_check(not paused, "Skip releases the world pause before the phone")
	_check(campaign.completed_beats.has(&"prologue_call"), "Shown or skipped original prologue advances only its real beat")
	var before := player.global_position
	Input.action_press("ui_right")
	await _frames(8)
	Input.action_release("ui_right")
	_check(player.global_position.distance_to(before) < 1.0, "Player cannot walk through the telephone dialogue")
	for _line in 16:
		if _phase() != "phone":
			break
		mission.advance_dialogue()
		await _frames(1)
	_check(_phase() == "meet_maciota", "Phone finishes into the garage objective")
	_check(not player.is_control_disabled, "Phone releases player controls")
	_check(not campaign.completed_beats.has(&"trap_and_arrest"), "Harbor introduction must not fabricate the legacy arrest beat")
	before = player.global_position
	Input.action_press("ui_down")
	await _frames(24)
	Input.action_release("ui_down")
	_check(player.global_position.y - before.y > 20.0, "Terminal arrival has a physically walkable route toward Market Street")

	print("CAMPAIGN: physical garage entrance and finite conversation")
	var garage: Node2D = world.get_node("Interiors").garage_interior
	var door := world.get_node("District/Garage/Entrance")
	player.global_position = door.get_node("OutsideReturn").global_position
	player.velocity = Vector2.ZERO
	await _frames(8)
	_check(door.is_actor_in_range(player), "Real garage sensor detects the arriving player")
	await _key(KEY_E)
	await create_timer(0.8).timeout
	_check(player.global_position.distance_to(garage.spawn_point.global_position) < 30.0, "Native E traverses the animated garage entrance")
	var npc: Node2D = garage.jager_npc
	player.global_position = npc.interact_area.global_position
	await _frames(8)
	await _key(KEY_E)
	_check(npc.is_talking, "Native E opens Maciota's conversation")
	await _key(KEY_ESCAPE)
	_check(not npc.is_talking, "Escape closes Maciota dialogue, rather than opening the pause menu")
	_check(not paused, "Cancelling a conversation must not pause the whole world")
	_check(_phase() == "meet_maciota", "Cancelling conversation does not complete the contact")
	_check(not garage.mission_board.interaction_enabled, "Cancelling does not unlock the board")
	await _key(KEY_E)
	var arm: Node3D = npc.left_upper_arm
	var initial_arm := arm.rotation
	await _frames(10)
	_check(arm.rotation.distance_to(initial_arm) > 0.001, "Maciota's 3D arm gestures while speaking")
	for _line in 12:
		if not npc.is_talking:
			break
		await _key(KEY_SPACE)
	_check(not npc.is_talking, "Contact conversation has an actual end")
	_check(_phase() == "board", "Completing Maciota dialogue enables the board objective")
	_check(garage.mission_board.interaction_enabled, "Board unlocks only after completed contact")
	_check(not player.is_control_disabled, "Maciota releases controls after his last line")

	print("CAMPAIGN: contract guards, pickup, delivery and one-time reward")
	player.global_position = garage.mission_board.global_position
	await _frames(6)
	await _key(KEY_E)
	print("CAMPAIGN BOARD INPUT position=",garage.to_local(player.global_position)," board_distance=",player.global_position.distance_to(garage.mission_board.global_position)," enabled=",garage.mission_board.interaction_enabled," npc_near=",npc.is_player_nearby," talking=",npc.is_talking," diagnostic=",garage.diagnostic_dialog.visible)
	_check(garage.mission_board.is_ui_open, "Native E opens the newly available mission board")
	var available_button: Button = null
	for child in garage.mission_board.orders_vbox.get_children():
		if child is Button and not child.disabled and not child.is_queued_for_deletion():
			available_button = child
			break
	_check(available_button != null, "Authored mission board contains an enabled selection button")
	_check(available_button != null and available_button.has_focus(), "Opening the board grabs keyboard focus on the available contract, ready for ui_accept/ui_up/ui_down")
	if available_button == null:
		quit(1)
		return
	available_button.pressed.emit()
	await _frames(2)
	_check(not garage.mission_board.is_ui_open, "Selecting the board button closes its modal")
	_check(_phase() == "delivery_pickup", "Accepted contract directs player to the dock pickup")
	_check(not mission.interact_with_objective(), "Pickup refuses an actor still inside the garage")
	player.global_position = world.get_node("FirstDeliveryPickup").global_position
	player.velocity = Vector2.ZERO
	await _frames(4)
	var query := PhysicsPointQueryParameters2D.new()
	query.position = player.global_position
	query.collision_mask = 1
	query.exclude = [player.get_rid()]
	_check(world.get_world_2d().direct_space_state.intersect_point(query).is_empty(), "Dock pickup marker is not embedded inside a solid building or seawall")
	_check(_body_clear_at(player.global_position), "Dock pickup fits the actual player capsule")
	_check(mission.interact_with_objective(), "Pickup succeeds at the actual authored dock marker")
	_check(_has_feedback(ProceduralAudio.get_powerup_stream()), "Pickup starts its audible feedback")
	_check(_phase() == "delivery_return", "Pickup creates the return objective")
	_check(not mission.interact_with_objective(), "Delivery cannot be completed remotely at the dock")
	var money_before: int = player.money
	player.global_position = npc.global_position + Vector2(0, 30)
	await _frames(4)
	_check(mission.interact_with_objective(), "Returning to Maciota completes the delivery")
	_check(_has_feedback(ProceduralAudio.get_mission_passed_stream()), "Delivery starts its distinct completion sound")
	_check(_phase() == "complete", "First mission reaches a completed state")
	_check(player.money > money_before, "Completed delivery pays the player")
	var paid: int = player.money
	mission.interact_with_objective()
	_check(player.money == paid, "Repeated interaction cannot pay the reward twice")

	var bridge := world.get_node("CobraCampaign")
	_check(bridge._dialog.visible, "Delivery reveals the promised brother clue")
	while bridge._dialog.visible:
		await _key(KEY_ENTER)
	_check(bridge.ledger.get_status("cobra_contact").available, "Next job is immediately available")
	print("CAMPAIGN: completed contract shows struck-through on the board")
	player.global_position = garage.mission_board.global_position
	await _frames(6)
	await _key(KEY_E)
	_check(garage.mission_board.is_ui_open, "Native E reopens the board after completion")
	var found_completed_row := false
	var found_selectable_button := false
	for child in garage.mission_board.orders_vbox.get_children():
		if child is Button:
			found_selectable_button = true
		elif child.has_meta("board_row_state") and child.get_meta("board_row_state") == "completed":
			found_completed_row = true
			var rich := child.find_children("*", "RichTextLabel", true, false)[0] as RichTextLabel
			_check(rich != null and rich.text.contains("[s]"), "Completed row actually uses strikethrough bbcode")
	_check(found_completed_row, "Completed contract renders struck-through instead of disappearing")
	_check(found_selectable_button, "Next job renders an enabled button beside the completed contract")
	await _key(KEY_ESCAPE)
	_check(not garage.mission_board.is_ui_open, "Escape still closes the enlarged board")
	_check(not player.is_control_disabled, "Closing the board returns control to the player")

	print("CAMPAIGN: hospital respawn and deferred save resume")
	player.global_position = world.get_node("ArrivalSpawn").global_position
	player.call("_respawn_at_hospital")
	var hospital := player.call("_get_nearest_hospital_spawn") as Node2D
	_check(hospital != null and world.is_ancestor_of(hospital), "Hospital spawn belongs to Harbor rather than the old map")
	if hospital != null:
		_check(player.global_position.distance_to(hospital.global_position) < 1.0, "Respawn uses the authored Harbor hospital marker")
		_check(_body_clear_at(player.global_position), "Hospital respawn fits the actual player capsule")
	var saved_position := player.global_position
	var snapshot := {"campaign": campaign.to_save_data(), "player": player.serialize()}
	var route := load("res://world/harbor/HarborSceneRoute.gd")
	_check(route.for_save(snapshot) == "res://world/harbor/HarborGame.tscn", "Harbor saves route back to the new map")
	_check(route.for_save({"campaign": {"campaign_flags": {}}}) == "res://legacy/Main.tscn", "Legacy saves retain their original map")
	world.queue_free()
	await _frames(4)
	campaign.reset_campaign()
	saves.set("_pending_save_data", snapshot)
	if await _load_world():
		_check(not saves.has_pending_save(), "Deferred Player restore consumes the pending save")
		_check(player.global_position.distance_to(saved_position) < 2.0, "Loading preserves position instead of forcing another terminal arrival")
		_check(player.money == paid, "Loading preserves money after the one-time reward")
		_check(_phase() == "complete", "Campaign flags restore completion without replaying the intro")
		_check(not player.is_control_disabled, "Loaded completed mission does not leave controls locked")
		_check(is_instance_valid(world.get_node("Interiors").garage_interior.mission_board), "Loading after meeting Maciota retains his mission board")
		garage = world.get_node("Interiors").garage_interior
		player.global_position = garage.spawn_point.global_position
		await create_timer(0.3).timeout
		snapshot = {"campaign": campaign.to_save_data(), "player": player.serialize()}
		world.queue_free()
		await _frames(4)
		saves.set("_pending_save_data", snapshot)
		if await _load_world():
			garage = world.get_node("Interiors").garage_interior
			_check(garage.get_camera_rect().has_point(player.global_position), "Interior save resumes inside the correct garage")
			var restored_camera := player.get_node("Camera") as Camera2D
			_check(restored_camera.get_meta("compact_interior", Rect2()) == garage.get_camera_rect(), "Interior save restores compact workshop framing")
			player.global_position = garage.exit_door.global_position
			await _frames(8)
			await _key(KEY_E)
			await create_timer(0.9).timeout
			_check(player.global_position.distance_to(world.get_node("District/Garage/Entrance/OutsideReturn").global_position) < 25.0, "Reloaded interior still has a working native E exit to Harbor")
	player.global_position = Vector2(4300, -6200)
	await player.arrest_and_respawn()
	var station := world.get_node("District/Police/Entrance/OutsideReturn") as Node2D
	_check(player.global_position.distance_to(station.global_position) < 30.0, "Arrest in mountains returns to Harbor police station")
	_check(not player.is_arrested and not player.is_recovering, "Arrest restores player control")
	world.queue_free()
	await _frames(4)
	print("HARBOR CAMPAIGN FLOW: %d failure(s)" % failures.size())
	quit(0 if failures.is_empty() else 1)

func _has_feedback(stream: AudioStream) -> bool:
	for child in mission.get_children():
		if child is AudioStreamPlayer and child.stream == stream and child.playing:
			return true
	return false
