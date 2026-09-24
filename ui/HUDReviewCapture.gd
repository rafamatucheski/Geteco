extends SceneTree

var failures: Array[String] = []
var world: Node
var hud: CanvasLayer

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, description: String) -> void:
	if condition: return
	failures.append(description)
	push_error(description)

func _run() -> void:
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	world.set_meta("skip_dispatch", true)
	world.set_meta("skip_traffic_yield", true)
	root.add_child(world)
	for frame in 900:
		await physics_frame
		if world.session != null and world.session.ready_for_play: break
	_check(world.session != null and world.session.ready_for_play, "production session reaches playable no-save state")
	_check(world.production != null and world.production.no_save, "capture never reads or writes a personal save")
	if not failures.is_empty():
		_finish()
		return
	hud = world.hud
	for frame in 12: await process_frame
	_check(hud.get_node_or_null("GameplayHUDRoot") != null, "World mounts the production GameplayHUD adapter")
	_check(is_instance_valid(world.session.stats) and is_instance_valid(world.session.objective) and is_instance_valid(world.session.prompt) and is_instance_valid(world.session.notice), "FullSession compatibility references remain valid")
	_check(is_instance_valid(world.camera.scope_reticle) and world.camera.scope_reticle.get_parent() == hud, "scope reticle remains attached to the active HUD")

	await _resize(Vector2i(1280, 720))
	world.player.teleport(world.maciota_place.entry_position + Vector3(0, 0, .25))
	for frame in 20: await physics_frame
	_check("Entrar" in hud.action_value.text, "on-foot nearby action is sourced from the real interaction query")
	_check(not hud.objective_value.text.is_empty(), "objective channel presents the real progression objective")
	_check(not hud.objective_panel.get_global_rect().intersects(hud.status_panel.get_global_rect()), "objective does not overlap status at 1280x720")
	_check(not hud.action_panel.get_global_rect().intersects(hud.speed_panel.get_global_rect()), "action channel reserves the vehicle-speed corner")
	await _shot("hud-01-on-foot-objective-interaction-1280x720.png")

	var state = world.session.state
	state.grant_weapon("pistol")
	state.add_ammo("pistol", 47)
	_check(state.equip_weapon("pistol"), "armed fixture equips through authoritative GameState")
	state.economy.grant_reward("hud_review_capture", 2450)
	world.gameplay.health = 73
	world.gameplay.armor = 48
	world.gameplay.stars = 2
	world.session.show_message("Munição recarregada.")
	for frame in 12: await process_frame
	_check("PENTE" in hud.ammo_value.text and "RESERVA" in hud.ammo_value.text, "armed HUD separates magazine and reserve")
	_check(hud.health_value.text == "73" and hud.armor_value.text == "48", "health and armor mirror authoritative combat state")
	_check("★★" in hud.wanted_value.text, "wanted level mirrors authoritative stars")
	_check(hud.feedback_panel.visible and "Munição" in hud.feedback_value.text, "temporary feedback has its own channel")
	await _shot("hud-02-armed-wanted-message-1280x720.png")

	var controls := root.get_node("GameInput")
	var original_bindings: Dictionary = controls.export_bindings()
	var remap := InputEventKey.new()
	remap.physical_keycode = KEY_K
	remap.keycode = KEY_K
	_check(controls.rebind("interact", remap).is_empty(), "temporary interaction remap is accepted")
	for frame in 4: await process_frame
	_check(hud.action_value.text.begins_with("K"), "nearby action follows the remapped keyboard binding")
	controls.using_gamepad = true
	controls.device_changed.emit()
	for frame in 4: await process_frame
	_check(hud.action_value.text.begins_with("X"), "nearby action follows the active generic controller glyph")
	controls.using_gamepad = false
	controls.import_bindings(original_bindings)
	for frame in 4: await process_frame

	var car: CharacterBody3D = world.driving.car
	var entered := false
	for side in [-1.0, 1.0]:
		world.player.teleport(car.to_global(Vector3(side * (car.half_width + .55), 0, .15)))
		for frame in 5: await physics_frame
		if world.driving.interact(true):
			entered = true
			break
	_check(entered and world.driving.occupied, "driving capture enters through the real Driving operation")
	for frame in 12: await process_frame
	_check("Sair do carro" in hud.action_value.text, "driving action uses the exit binding in the shared action channel")
	_check(hud.speed_panel.visible, "driving speed is visible in its reserved corner")
	await _shot("hud-03-driving-1280x720.png")

	await _resize(Vector2i(1024, 768))
	for frame in 6: await process_frame
	_check(not hud.objective_panel.get_global_rect().intersects(hud.status_panel.get_global_rect()), "objective stacks below status at 1024x768")
	_check(not hud.action_panel.get_global_rect().intersects(hud.speed_panel.get_global_rect()), "action and speed remain separate at 1024x768")
	_check(hud.status_panel.get_global_rect().end.x <= 1024.5 and hud.action_panel.get_global_rect().end.y <= 768.5, "HUD respects the 1024x768 safe margins")
	await _shot("hud-04-driving-responsive-1024x768.png")

	_finish()

func _resize(dimensions: Vector2i) -> void:
	root.content_scale_size = dimensions
	root.size = dimensions
	if DisplayServer.get_name() != "headless": DisplayServer.window_set_size(dimensions)
	for frame in 6: await process_frame

func _shot(file_name: String) -> void:
	for frame in 3: await process_frame
	await RenderingServer.frame_post_draw
	var result := root.get_texture().get_image().save_png("res://evidence/" + file_name)
	_check(result == OK, "capture written: " + file_name)

func _finish() -> void:
	print("HUD_REVIEW_CAPTURE ", "PASS" if failures.is_empty() else "FAIL", " failures=", failures)
	quit(0 if failures.is_empty() else 1)
