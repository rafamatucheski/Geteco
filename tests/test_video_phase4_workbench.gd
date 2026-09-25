extends SceneTree
## Real shop, expanded parts, controller input and rendered layout at two sizes.
var world
var checks := 0
var failures: Array[String] = []
var output_dir := ""
var label := "before"
var capture_enabled := false

func _initialize() -> void: run.call_deferred()
func check(ok: bool, text: String) -> void:
	checks += 1
	print("VIDEO_BENCH ", "PASS " if ok else "FAIL ", text)
	if not ok: failures.append(text)
func frames(count: int) -> void:
	for i in count: await process_frame
func joy(button: JoyButton) -> void:
	var event := InputEventJoypadButton.new()
	event.device = 0
	event.button_index = button
	event.pressed = true
	Input.parse_input_event(event)
	await frames(2)
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)
	await frames(2)
func photo(id: String) -> void:
	if not capture_enabled: return
	await RenderingServer.frame_post_draw
	var result := root.get_texture().get_image().save_png(output_dir.path_join(label + "-" + id + ".png"))
	check(result == OK, "PNG " + id)

func layout(bench, id: String) -> void:
	var visible: Rect2 = root.get_visible_rect()
	check(visible.grow(1).encloses(bench.get_global_rect()), id + " panel fits viewport")
	check(bench.get_global_rect().grow(1).encloses(bench.apply_button.get_global_rect()), id + " action remains inside panel")
	check(bench.get_global_rect().grow(1).encloses(bench.status.get_global_rect()) and bench.get_global_rect().grow(1).encloses(bench.detail.get_global_rect()), id + " status and stats fit panel")
	var scroll: ScrollContainer = bench.options.get_parent()
	var fit := true
	for button in bench.options.get_children():
		if button.size.x > scroll.size.x + 1.0: fit = false
	check(fit, id + " option text fits scroll width")

func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output-dir="): output_dir = arg.trim_prefix("--output-dir=")
		if arg.begins_with("--label="): label = arg.trim_prefix("--label=")
	capture_enabled = "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless"
	if "--no-save" not in OS.get_cmdline_user_args() or output_dir.is_empty(): quit(2); return
	create_timer(150).timeout.connect(func(): push_error("VIDEO_BENCH timeout"); quit(3))
	DirAccess.make_dir_recursive_absolute(output_dir)
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	world.set_meta("skip_dispatch", true)
	root.add_child(world)
	for i in 2400:
		await physics_frame
		if world.session != null and world.session.ready_for_play: break
	check(world.session != null and world.session.ready_for_play, "Main ready")
	if not failures.is_empty(): quit(1); return
	for i in 600:
		var loading := false
		for node in world.get_children():
			if node.get_script() == preload("res://runtime/StartupCurtain.gd"): loading = true
		if not loading: break
		await process_frame
	world.gameplay.dispatch_owned = true
	world.gameplay.emergency.dispatch_owned = true
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	world.session.weather.weather_state = 0
	world.session.weather.weather_timer = 99999
	world.session.weather.time_of_day = .45
	var session = world.session
	check(world.production.no_save, "personal save disabled")
	check(await session.enter_place("harbor_ammunation", false), "actual weapon shop admitted")
	if not failures.is_empty(): quit(1); return
	world.player.teleport(session.room.interaction_points.service + Vector3.UP * .05)
	for i in 15: await physics_frame
	check(session.interact() and session.modal and session.storefronts.is_open(), "real counter opens catalog")
	if not failures.is_empty(): quit(1); return
	var catalog = session.storefronts.ammunation
	var bench = catalog.workbench
	for id in ["pistol", "smg", "knife", "knuckles", "m4a1", "flamethrower"]: session.state.grant_weapon(id)
	session.state.economy.grant_reward("phase4_bench_fixture", 10000)
	var cases := [["pistol", "barrel_long"], ["smg", "drum"], ["knife", "serrated"], ["knuckles", "push_blade"], ["m4a1", "compensator"], ["flamethrower", "big_tank"]]
	for resolution in [Vector2i(1280, 720), Vector2i(1920, 1080)]:
		if DisplayServer.get_name() != "headless":
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_size(resolution)
		root.size = resolution
		await frames(5)
		catalog.selection = catalog.stock.find("pistol")
		catalog.change_selection(0)
		await frames(3)
		if resolution.x == 1280: await photo("catalog-pistol-1280")
		for spec in cases:
			catalog.selection = catalog.stock.find(spec[0])
			catalog.change_selection(0)
			catalog.open_workbench()
			bench.select_slot(bench.CUSTOM.PARTS[spec[1]].slot)
			bench.select_candidate(spec[1])
			await frames(5)
			layout(bench, str(resolution.x) + " " + spec[0] + " " + spec[1])
			if resolution.x == 1280 or spec[0] == "m4a1": await photo(str(resolution.x) + "-" + spec[0] + "-" + spec[1])
			bench.close()
	# Physical controller events pass through FullSession, catalog and GUI focus.
	catalog.selection = catalog.stock.find("pistol")
	catalog.change_selection(0)
	catalog.workbench_button.grab_focus()
	await joy(JOY_BUTTON_A)
	check(bench.visible and not catalog.panel.visible, "controller A opens workbench")
	bench.select_slot("muzzle")
	bench.options.get_child(0).grab_focus()
	await joy(JOY_BUTTON_DPAD_DOWN)
	check(root.gui_get_focus_owner() == bench.options.get_child(1), "controller down moves option focus")
	await joy(JOY_BUTTON_A)
	check(bench.candidate == "suppressor", "controller A selects focused part")
	bench.select_slot("finish")
	bench.options.get_child(0).grab_focus()
	for i in bench.options.get_child_count() - 1: await joy(JOY_BUTTON_DPAD_DOWN)
	var focused: Control = root.gui_get_focus_owner()
	var last: Control = bench.options.get_child(bench.options.get_child_count() - 1)
	var scroll: ScrollContainer = bench.options.get_parent()
	check(focused == last, "controller reaches last finish")
	check(scroll.get_global_rect().grow(1).encloses(last.get_global_rect()), "controller scroll keeps focused finish fully visible")
	await photo("controller-last-finish")
	await joy(JOY_BUTTON_B)
	check(not bench.visible and catalog.panel.visible and root.gui_get_focus_owner() == catalog.workbench_button, "controller B returns focus to catalog")
	await joy(JOY_BUTTON_B)
	check(not session.modal and not session.storefronts.is_open(), "controller B closes store")
	world.queue_free()
	await frames(6)
	print("VIDEO_BENCH checks=", checks, " failures=", failures.size(), " details=", failures)
	quit(0 if failures.is_empty() else 1)
