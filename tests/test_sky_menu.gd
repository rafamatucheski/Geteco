extends SceneTree
## Real menu -> restored Main -> flight -> gameplay, using isolated fixture slots.
const FOLDER := "res://evidence/sky-menu-fixes-20260925/functional"
class InputBlocker extends Node:
	func _input(_event: InputEvent) -> void:
		get_viewport().set_input_as_handled()
class IsolatedLaunch extends "res://runtime/SessionLaunch.gd":
	var folder := ""
	func slot_path(id: String) -> String:
		return folder.path_join(id + ".json") if id in ["progress"] + SLOT_IDS else ""
var checks := 0
var failures: Array[String] = []
var launch: Node
var saved_car: Dictionary = {}

func _initialize() -> void: run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		push_error(label)

func capture(label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(FOLDER.path_join(label + ".png"))

func ready_menu(menu: Control) -> bool:
	var deadline := Time.get_ticks_msec() + 90000
	while is_instance_valid(menu) and not menu.sky.is_ready and not menu.sky.failed and Time.get_ticks_msec() < deadline:
		await process_frame
	return is_instance_valid(menu) and menu.sky.is_ready

func run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args():
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(FOLDER)
	var blocker := InputBlocker.new()
	blocker.process_mode = Node.PROCESS_MODE_ALWAYS
	root.add_child(blocker)
	for action in InputMap.get_actions(): InputMap.action_erase_events(action)
	var original := root.get_node("V2Launch")
	root.remove_child(original)
	original.free()
	launch = IsolatedLaunch.new()
	launch.name = "V2Launch"
	launch.folder = FOLDER.path_join("slots_%d" % Time.get_ticks_usec())
	launch.direct_start_consumed = true
	root.add_child(launch)
	var menu = load("res://ui/MainMenu.tscn").instantiate()
	root.add_child(menu)
	current_scene = menu
	check(not menu.btn_continue.visible and not menu.sky.loading, "No-save menu stays static and has no Continue")
	menu.free()
	for scenario in ["harbor", "driving-night", "mountain", "garage", "garage-driver"]:
		var state = load("res://runtime/GameState.gd").new()
		state.world_state.time = .45
		state.economy.grant_reward("sky_fixture", 321)
		state.grant_weapon("pistol")
		state.equip_weapon("pistol")
		state.set_location("mountain" if scenario == "mountain" else "harbor", "maciota" if scenario.begins_with("garage") else "")
		if scenario == "garage-driver":
			state.world_state.garage_rewards = {"version": 1, "port_status": "parked", "alarm_remaining": -1.0, "police_called": false, "vehicles": {"garage_guest_1": {"archetype": "sport_coupe", "region_id": "harbor", "place_id": "maciota", "position": [0.0, 0.08, 1.2], "yaw": 0.0, "health": 80.0, "paint": "ffffffff", "was_driven": true}}}
		if scenario == "driving-night":
			state.world_state.vehicles = [saved_car]
			state.world_state.time = .85
			state.world_state.weather = 1
		var store = load("res://runtime/SaveStore.gd").new()
		store.path = launch.slot_path("slot_01")
		check(store.save(state) == OK, scenario + " fixture saved")
		var hash_before := FileAccess.get_sha256(store.path)
		menu = load("res://ui/MainMenu.tscn").instantiate()
		root.add_child(menu)
		current_scene = menu
		menu.sky.boot_path(store.path)
		check(await ready_menu(menu), scenario + " real world ready")
		if not menu.sky.is_ready:
			quit(1)
			return
		var world = menu.sky.world
		var original_world_id: int = world.get_instance_id()
		var position: Vector3 = world.player.position
		var health: float = world.gameplay.health
		var clock_before: float = world.session.weather.time_of_day
		var camera_transform: Transform3D = world.camera.global_transform
		var camera_size: float = world.camera.size
		check(paused and world.production.no_save and not world.hud.visible, scenario + " preview paused, read-only, HUD hidden")
		check(world.session.arrival.presentation == null, scenario + " preview cannot launch CGI")
		Input.action_press("move_up")
		Input.action_press("fire")
		Input.action_press("pause_game")
		await create_timer(1.5, true).timeout
		Input.action_release("move_up")
		Input.action_release("fire")
		Input.action_release("pause_game")
		check(world.player.position.is_equal_approx(position) and world.gameplay.health == health, scenario + " input cannot move or damage player in menu")
		check(world.session.weather.time_of_day == clock_before, scenario + " world clock frozen")
		check(FileAccess.get_sha256(store.path) == hash_before, scenario + " preview preserves save bytes")
		check(world.production.region.is_streaming_idle(), scenario + " visible neighbourhood fully built")
		check(not menu.sky._vehicle_restore_pending(), scenario + " vehicle admission finished before sky reveal")
		if scenario == "garage-driver":
			check(world.driving.occupied and world.driving.car.vehicle_id == "garage_guest_1", "Saved garage driver already seated in the menu")
		menu._open_settings()
		check(menu.settings.visible, scenario + " settings open while paused")
		menu.settings.close()
		check(paused, scenario + " closing settings keeps preview frozen")
		await capture(scenario + "-sky")
		var air_basis: Basis = menu.sky.camera.basis
		menu._start("slot_01", false)
		await create_timer(0.6, true).timeout
		if not scenario.begins_with("garage"):
			check(menu.sky.camera.basis.is_equal_approx(air_basis), scenario + " no camera turn while clouds remain")
		await create_timer(0.9, true).timeout
		if not scenario.begins_with("garage"):
			check(is_equal_approx(menu.sky.material.get_shader_parameter("descent"), 1.0), scenario + " clouds gone before turn")
		await capture(scenario + "-descent")
		check(paused and not world.hud.visible, scenario + " flight still locks gameplay and HUD")
		var deadline := Time.get_ticks_msec() + 10000
		while is_instance_valid(menu) and Time.get_ticks_msec() < deadline: await process_frame
		check(not is_instance_valid(menu), scenario + " menu released")
		check(current_scene == world and world.get_instance_id() == original_world_id, scenario + " same Main instance promoted")
		check(not paused and root.get_camera_3d() == world.camera, scenario + " gameplay camera current and controls released")
		check(world.camera.global_transform.is_equal_approx(camera_transform) and is_equal_approx(world.camera.size, camera_size), scenario + " exact camera handoff")
		check(world.player.position.distance_to(position) < 0.1, scenario + " save position preserved")
		check(world.hud.visible and world.production.no_save, scenario + " HUD returns, test cannot save")
		check(FileAccess.get_sha256(store.path) == hash_before, scenario + " Continue preserves isolated save")
		if scenario == "harbor":
			saved_car = load("res://runtime/FleetState.gd").capture(world.driving.car, "harbor")
			saved_car.was_driven = true
		if scenario == "driving-night":
			check(world.driving.occupied and world.camera.target == world.driving.car, "Saved driver keeps vehicle and camera target")
		if scenario.begins_with("garage"):
			check(world.camera.locked and world.session.state.place_id == "maciota", "Garage authored camera preserved")
			check(not world.session.state.can_attack() and world.session.state.equipped_weapon == "fists" and world.session.state.owns_weapon("pistol"), "Garage weapon lock and inventory preserved")
			if not world.driving.occupied: check(world.session.position_clear(world.player.position), "Garage restored on free floor")
		await capture(scenario + "-gameplay")
		world.queue_free()
		await process_frame
		await process_frame
	# New game after an existing preview must discard that world and start CGI.
	menu = load("res://ui/MainMenu.tscn").instantiate()
	root.add_child(menu)
	current_scene = menu
	menu.sky.boot_path(launch.slot_path("slot_01"))
	check(await ready_menu(menu), "Preview ready before New Game")
	var discarded = weakref(menu.sky.world)
	menu._start("slot_02", true)
	var finish := Time.get_ticks_msec() + 90000
	while Time.get_ticks_msec() < finish:
		await process_frame
		if current_scene != menu and current_scene != null and current_scene.get("session") != null:
			if current_scene.session.arrival.phase == "opening": break
	check(discarded.get_ref() == null, "New Game disposes preview world")
	check(current_scene != null and current_scene.get("session") != null and current_scene.session.arrival.phase == "opening", "New Game starts original CGI")
	check(not FileAccess.file_exists(launch.slot_path("slot_02")), "Test New Game writes no save")
	await capture("new-game-opening")
	if is_instance_valid(current_scene): current_scene.queue_free()
	await process_frame
	await process_frame
	print("SKY_MENU ", checks, " checks failures=", failures)
	quit(0 if failures.is_empty() else 1)
