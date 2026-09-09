extends SceneTree

const GAME := preload("res://world/harbor/HarborGame.tscn")
var failures: Array[String] = []
var world: Node2D
var player: CharacterBody2D

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error("BOSS_REWARD: " + message)

func frames(count: int) -> void:
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
	root.size = Vector2i(1280, 720)
	seed(9007)
	root.get_node("SaveManager").clear_pending_save()
	var campaign := root.get_node("CampaignState")
	campaign.reset_campaign()
	for flag in ["harbor_arrival_seen", "harbor_arrival_call_complete", "harbor_maciota_met", "harbor_delivery_complete"]:
		campaign.set_campaign_flag(StringName(flag), true)
	world = GAME.instantiate()
	root.add_child(world)
	current_scene = world
	await frames(8)
	player = world.get_node("Player")
	var bridge := world.get_node("CobraCampaign")
	var ledger: RefCounted = bridge.ledger
	# Reward QA checkpoint excludes the separately tested post-boss phone shot.
	ledger.data.aftermath = {"call_complete": true, "works_complete": true}
	var adapter := world.get_node_or_null("CobraBossReward")
	check(adapter != null, "Production HarborGame integrates reward adapter")
	if adapter == null:
		await finish()
		return
	check(adapter.reward_car == null, "No reward before winning")
	ledger.data.defeated = true
	adapter.sync_reward()
	check(adapter.reward_car == null, "Defeated flag alone cannot grant reward")
	ledger.data.defeated = false
	# Segmented campaign-completion fixture through real ledger APIs, not boss combat QA.
	for id in ledger.MISSION_IDS:
		ledger.rest_until_next_day(false)
		check(ledger.start_mission(id), "Can start fixture " + id)
		check(ledger.complete_mission(id), "Complete fixture " + id)
	# Explicit pre-existing collectible ownership fixture: non-empty namespace.
	var secret: CharacterBody2D = world.find_child("CobraVehicles", true, false).secret_car
	secret.repaint_vehicle(Color("287341"))
	secret.health = 77
	ledger.data.secret_owned["ashbend_coupe"] = {"owned": true}
	bridge.get_node("CobraDiscovery").capture_snapshot()
	var secret_before: Dictionary = ledger.data.secret_owned.duplicate(true)
	adapter.sync_reward()
	await frames(3)
	var car: CharacterBody2D = adapter.reward_car
	check(is_instance_valid(car), "Victory produces physical reward in actual garage")
	if not is_instance_valid(car):
		await finish()
		return
	var original_id := car.get_instance_id()
	var garage: Node2D = world.get_node("Interiors").garage_interior
	check(car.global_position.distance_to(garage.to_global(adapter.BAY)) < 2, "Reward uses actual interior bay")
	check(adapter._pose_clear(car.global_transform), "Reward body does not overlap walls, board, Maciota or props")
	adapter.configure(world, ledger)
	adapter.sync_reward()
	check(adapter.reward_car.get_instance_id() == original_id, "Reconfigure does not clone reward")
	car.repaint_vehicle(Color("284e6a"))
	car.health = 63
	adapter.capture_snapshot()
	var json: Dictionary = JSON.parse_string(JSON.stringify(campaign.to_save_data()))
	car.repaint_vehicle(Color.RED)
	car.health = 12
	campaign.restore_from_save(json)
	await frames(3)
	check(car.get_instance_id() == original_id and car.health == 63, "JSON reload restores same car and health")
	check(car.paint_color.is_equal_approx(Color("284e6a")), "JSON reload preserves paint")
	check(ledger.data.secret_owned == secret_before, "Boss reward never overwrites secret coupe namespace")
	check(not adapter.recover_to_garage(), "Cannot tow remotely outside garage")
	# Fixture places actor only; boarding and exit below are native input.
	player.global_position = car.global_position + Vector2(0, 58)
	await create_timer(0.3).timeout
	print("BOSS_BOARD before pos=", player.global_position, " car=", car.global_position, " disabled=", player.is_control_disabled, " dialogue=", player.is_in_dialogue, " processing=", player.is_physics_processing())
	await key(KEY_E)
	await create_timer(0.15).timeout
	check(car.is_driven_by_player, "Native E boards Ironback")
	check(not adapter.recover_to_garage(), "Cannot tow a driven car")
	if car.is_driven_by_player:
		check(await drive_to(car, garage.to_global(Vector2(-40, 130))), "Native drive leaves bay through garage corridor")
		check(await drive_to(car, garage.to_global(Vector2(0, 220))), "Native drive reaches garage exit")
		await key(KEY_E)
		await create_timer(1.0).timeout
		check(car.global_position.distance_to(garage.global_position) > 1000, "Entrance E actually returns car outdoors")
		if car.is_driven_by_player:
			await key(KEY_F)
			await create_timer(0.2).timeout
	# Recovery is a real button and never repairs the damage.
	player.global_position = garage.to_global(adapter.BAY + Vector2(0, 65))
	await create_timer(0.3).timeout
	check(adapter.recovery_panel.visible, "Recovery UI appears near bay on foot")
	var previous_locale := TranslationServer.get_locale()
	TranslationServer.set_locale("en")
	await frames(3)
	check(adapter.recovery_button.text == "Tow to bay (does not repair)" and adapter.repair_button.text == "Repair Ironback in bay", "Reward actions switch to English without saving settings")
	TranslationServer.set_locale(previous_locale)
	await frames(3)
	if car.global_position.distance_to(garage.to_global(adapter.BAY)) > 150:
		var blocker := StaticBody2D.new()
		blocker.collision_layer = 1
		var collision := CollisionShape2D.new()
		collision.shape = RectangleShape2D.new()
		collision.shape.size = Vector2(30, 30)
		blocker.add_child(collision)
		world.add_child(blocker)
		blocker.global_position = garage.to_global(adapter.BAY)
		await frames(3)
		var before_tow := car.global_position
		check(not adapter.recover_to_garage() and car.global_position == before_tow, "Occupied bay refuses tow without moving car")
		blocker.queue_free()
		await frames(3)
	var hp: int = car.health
	var ammo_before: Dictionary = player.weapon_ammo.duplicate(true)
	var button: Button = adapter.recovery_button
	var mouse := InputEventMouseMotion.new()
	mouse.position = button.get_global_rect().get_center()
	mouse.global_position = mouse.position
	Input.warp_mouse(mouse.position)
	Input.parse_input_event(mouse)
	await frames(2)
	for down in [true, false]:
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.position = mouse.position
		click.global_position = mouse.position
		click.pressed = down
		Input.parse_input_event(click)
		await frames(2)
	await create_timer(0.15).timeout
	print("BOSS_TOW position=", car.global_position, " ui=", adapter._feedback.text, " button=", button.get_global_rect())
	check(car.global_position.distance_to(garage.to_global(adapter.BAY)) < 3, "Mouse button tows reward to actual bay")
	print("BOSS_TOW health before=", hp, " after=", car.health)
	check(car.health == hp, "Tow preserves exact damage")
	check(player.weapon_ammo == ammo_before, "Armed tow button never fires through UI")
	car.health = 0
	car.is_broken = true
	car.is_exploded = true
	adapter.capture_snapshot()
	var wreck_save: Dictionary = JSON.parse_string(JSON.stringify(campaign.to_save_data()))
	car.repair_vehicle()
	campaign.restore_from_save(wreck_save)
	await create_timer(0.15).timeout
	check(car.health == 0 and car.is_broken, "Reload cannot resurrect a wreck")
	check(adapter.recover_to_garage() and car.health == 0, "Explicit tow keeps wreck damaged")
	var repair: Button = adapter.repair_button
	for down in [true, false]:
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.position = repair.get_global_rect().get_center()
		click.global_position = click.position
		click.pressed = down
		Input.parse_input_event(click)
		await frames(3)
	await create_timer(0.15).timeout
	check(car.health == car.max_health and car.max_speed == 560 and not car.is_broken, "Explicit repair mouse button restores health and drivability")
	check(player.weapon_ammo == ammo_before, "Armed repair button never fires through UI")
	print("BOSS_REWARD instance=%s hp=%s secret_preserved=%s" % [original_id, car.health, ledger.data.secret_owned == secret_before])
	if OS.get_cmdline_user_args().has("--capture") and DisplayServer.get_name() != "headless":
		world.get_node("Interiors")._frame_interior_camera(player, garage.get_camera_rect())
		await frames(5)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("D:/geteco/harbor-stage4-boss-recovery.png")
	adapter.capture_snapshot()
	var fresh_save: Dictionary = JSON.parse_string(JSON.stringify(campaign.to_save_data()))
	world.queue_free()
	await frames(4)
	campaign.restore_from_save(fresh_save)
	world = GAME.instantiate()
	root.add_child(world)
	current_scene = world
	await create_timer(0.3).timeout
	adapter = world.get_node("CobraBossReward")
	check(is_instance_valid(adapter.reward_car), "Fresh world restores reward from JSON")
	if is_instance_valid(adapter.reward_car):
		var count := 0
		for vehicle in get_nodes_in_group("vehicle"):
			if str(vehicle.get_meta("campaign_reward_id", "")) == adapter.REWARD_ID:
				count += 1
		check(count == 1 and adapter.reward_car.get_instance_id() != original_id, "Fresh scene has exactly one new reward instance, no orphan clone")
		check(adapter.reward_car.paint_color.is_equal_approx(Color("284e6a")), "Fresh scene retains paint")
		check(adapter.reward_car.health == 100, "Fresh scene retains saved repaired health")
		check(world.get_node("CobraCampaign").ledger.data.secret_owned == secret_before, "Fresh scene preserves separate non-empty secret ownership")
	await finish()

func drive_to(car: CharacterBody2D, target: Vector2) -> bool:
	var elapsed := 0.0
	while elapsed < 12.0 and car.is_driven_by_player:
		for action in ["ui_up", "ui_down", "ui_left", "ui_right"]:
			Input.action_release(action)
		var delta := target - car.global_position
		if delta.length() < 28.0:
			await frames(30)
			return true
		var forward := Vector2.RIGHT.rotated(car.global_rotation)
		var direction := delta.normalized()
		var cross := forward.cross(direction)
		var speed := car.velocity.length()
		if forward.dot(direction) >= -0.2:
			Input.action_press("ui_right" if cross > 0 else "ui_left", clampf(absf(cross) * 2.5, 0.4, 1.0))
			if speed < (40.0 if delta.length() < 60 else 85.0):
				Input.action_press("ui_up", 0.35)
		else:
			Input.action_press("ui_left" if cross > 0 else "ui_right", clampf(absf(cross) * 2.0, 0.4, 1.0))
			if speed < 40:
				Input.action_press("ui_down", 0.35)
		await physics_frame
		elapsed += 1.0 / 60.0
	for action in ["ui_up", "ui_down", "ui_left", "ui_right"]:
		Input.action_release(action)
	print("BOSS_DRIVE timeout position=", car.global_position, " target=", target)
	return false

func finish() -> void:
	world.queue_free()
	await frames(3)
	print("BOSS_REWARD failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
