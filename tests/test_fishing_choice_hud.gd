extends SceneTree
## Rendered, standalone interaction/layout test for the production fishing HUD.
## Uses viewport input dispatch, not direct pressed.emit() or HUD private callbacks.
const HUD := preload("res://activities/fishing/FishingHUD.gd")
var checks := 0
var failures: Array[String] = []
var received: Array[String] = []
var hud
var folder := ""

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	print("FISHING_CHOICE_HUD ", "PASS " if ok else "FAIL ", label)
	if not ok: failures.append(label)

func capture(label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(folder.path_join(label + ".png"))

func click_at(point: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	root.push_input(motion, true)
	await process_frame
	for down in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.global_position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
		event.pressed = down
		root.push_input(event, true)
		await process_frame

func tap_at(point: Vector2) -> void:
	for down in [true, false]:
		var event := InputEventScreenTouch.new()
		event.index = 23
		event.position = point
		event.pressed = down
		root.push_input(event, true)
		await process_frame

func key(code: Key) -> void:
	for down in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = down
		root.push_input(event, true)
		await process_frame

func check_layout(keep: Button, release_button: Button, extent: Vector2i, label: String) -> void:
	var bounds := Rect2(Vector2.ZERO, Vector2(extent))
	for button in [keep, release_button]:
		var rect: Rect2 = button.get_global_rect()
		check(rect.size.x >= 44 and rect.size.y >= 44, label + " " + button.name + " has a usable 44px target")
		check(bounds.encloses(rect), label + " " + button.name + " stays fully inside the viewport")
	check(not keep.get_global_rect().intersects(release_button.get_global_rect()), label + " choices do not overlap each other")

func expect_signal(action: String, label: String) -> void:
	check(received == [action], label + " emits exactly one " + action + " choice")
	received.clear()

func run_case(extent: Vector2i, touch: bool) -> void:
	if DisplayServer.get_name() != "headless": DisplayServer.window_set_size(extent)
	root.size = extent
	await process_frame
	await process_frame
	var label := "%dx%d-%s" % [extent.x, extent.y, "touch" if touch else "desktop"]
	check(root.get_visible_rect().size.is_equal_approx(Vector2(extent)), label + " uses actual unscaled viewport dimensions")
	Input.emulate_mouse_from_touch = false
	Input.emulate_touch_from_mouse = false
	hud = HUD.new()
	root.add_child(hud)
	hud.catch_choice.connect(func(action: String): received.append(action))
	var data := {"phase":"caught", "touch":touch, "title":"Pesca livre", "catch_name":"Pirarara", "catch_grams":14000, "catch_record":true, "best":14000, "catches":1, "action_key":"E", "release_key":"R", "cancel":"F sair · Esc pausa"}
	received.clear()
	hud.update_state(data)
	await create_timer(.35).timeout
	var keep := hud.get_node_or_null("KeepFish") as Button
	var release_button := hud.get_node_or_null("ReleaseFish") as Button
	check(is_instance_valid(keep) and is_instance_valid(release_button), label + " exposes real choice buttons")
	if not is_instance_valid(keep) or not is_instance_valid(release_button):
		hud.queue_free()
		await process_frame
		return
	check(keep.is_visible_in_tree() and release_button.is_visible_in_tree() and not keep.disabled and not release_button.disabled, label + " caught waits with both choices available")
	check(received.is_empty(), label + " entering caught does not choose automatically")
	check_layout(keep, release_button, extent, label)
	await capture(label + "-caught")
	if touch:
		check(not Input.emulate_mouse_from_touch, label + " tests native touch without mouse emulation")
		await tap_at(keep.get_global_rect().get_center())
		expect_signal("keep", label + " tapping Guardar")
		await tap_at(release_button.get_global_rect().get_center())
		expect_signal("release", label + " tapping Soltar")
	else:
		check(root.gui_get_focus_owner() == keep, label + " initial choice is focused without activation")
		await key(KEY_RIGHT)
		check(root.gui_get_focus_owner() == release_button, label + " right arrow focuses Soltar")
		hud.activate_focused_choice()
		expect_signal("release", label + " controller acceptance respects focused Soltar")
		await key(KEY_ENTER)
		expect_signal("release", label + " Enter activates focused Soltar")
		await key(KEY_LEFT)
		check(root.gui_get_focus_owner() == keep, label + " left arrow returns focus to Guardar")
		hud.activate_focused_choice()
		expect_signal("keep", label + " controller acceptance respects focused Guardar")
		await key(KEY_SPACE)
		expect_signal("keep", label + " Space activates focused Guardar")
		await click_at(keep.get_global_rect().get_center())
		expect_signal("keep", label + " clicking Guardar")
		await click_at(release_button.get_global_rect().get_center())
		expect_signal("release", label + " clicking Soltar")
	check(keep.visible and release_button.visible, label + " signals leave the decision lifecycle with the parent")

	keep.grab_focus()
	data.keep_enabled = false
	data.choice_message = "Sem espaço na mochila. Libere espaço ou solte o peixe."
	hud.update_state(data)
	await process_frame
	check(keep.disabled and not release_button.disabled, label + " a full inventory disables only Guardar")
	check(root.gui_get_focus_owner() == release_button, label + " disabled Guardar moves focus to the available action")
	check_layout(keep, release_button, extent, label + " with capacity message")
	await capture(label + "-capacity")
	if touch: await tap_at(keep.get_global_rect().get_center())
	else: await click_at(keep.get_global_rect().get_center())
	check(received.is_empty(), label + " disabled Guardar cannot emit a choice")
	if touch: await tap_at(release_button.get_global_rect().get_center())
	else: await click_at(release_button.get_global_rect().get_center())
	expect_signal("release", label + " Soltar remains available with no capacity")
	var former_keep := keep.get_global_rect().get_center()
	var former_release := release_button.get_global_rect().get_center()
	for phase in ["storing", "releasing"]:
		data.phase = phase
		data.choice_message = ""
		hud.update_state(data)
		await process_frame
		check(not keep.is_visible_in_tree() and not release_button.is_visible_in_tree(), label + " " + phase + " hides choice actions")
		check(root.gui_get_focus_owner() != keep and root.gui_get_focus_owner() != release_button, label + " " + phase + " releases choice focus")
		await click_at(former_keep)
		await tap_at(former_release)
		await key(KEY_ENTER)
		hud.activate_focused_choice()
		check(received.is_empty(), label + " " + phase + " cannot emit another choice")
		await capture(label + "-" + phase)
	hud.queue_free()
	await process_frame
	await process_frame

func run() -> void:
	if DisplayServer.get_name() == "headless" and "--functional-only" not in OS.get_cmdline_user_args():
		push_error("test_fishing_choice_hud requires a rendered window")
		quit(2)
		return
	folder = "res://evidence/fishing-choice-hud-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	await process_frame
	root.get_node("V2Settings").text_language = "pt_BR"
	TranslationServer.set_locale("pt_BR")
	if DisplayServer.get_name() != "headless": DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_size = Vector2i.ZERO
	var old_mouse_emulation := Input.emulate_mouse_from_touch
	var old_touch_emulation := Input.emulate_touch_from_mouse
	for width in [640, 1280]:
		for touch in [false, true]: await run_case(Vector2i(width, 720), touch)
	Input.emulate_mouse_from_touch = old_mouse_emulation
	Input.emulate_touch_from_mouse = old_touch_emulation
	FileAccess.open(folder.path_join("result.json"), FileAccess.WRITE).store_string(JSON.stringify({"checks":checks, "failures":failures, "rendered":DisplayServer.get_name() != "headless", "scope":"production HUD only; mouse, native touch and keyboard focus dispatch; headless functional mode omits image captures; no gameplay or FPS certification"}, "\t"))
	print("FISHING_CHOICE_HUD_RESULT ", folder, " checks=", checks, " failures=", failures)
	for frame in 4: await process_frame
	if DisplayServer.get_name() != "headless": await RenderingServer.frame_post_draw
	quit(0 if failures.is_empty() else 1)
