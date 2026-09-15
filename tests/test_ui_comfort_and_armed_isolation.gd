extends SceneTree

var failures: Array[String] = []

class TestBoardingVehicle extends Node2D:
	var enter_called := false
	var is_driven_by_player := false
	func _init() -> void:
		name = "TestBoardingVehicle"
	func _ready() -> void:
		add_to_group("vehicle")
	func enter_vehicle(_p: Node2D) -> void:
		enter_called = true
		is_driven_by_player = true

func _check(ok: bool, msg: String) -> void:
	if not ok:
		failures.append(msg)
		push_error("FAIL: " + msg)
	print(("PASS: " if ok else "FAIL: ") + msg)

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
		await _frames(3)

func _click_at(pos: Vector2) -> void:
	Input.warp_mouse(pos)
	var motion := InputEventMouseMotion.new()
	motion.position = pos
	motion.global_position = pos
	Input.parse_input_event(motion)
	await _frames(3)
	var down := InputEventMouseButton.new()
	down.position = pos
	down.global_position = pos
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	Input.parse_input_event(down)
	await _frames(2)
	var up := InputEventMouseButton.new()
	up.position = pos
	up.global_position = pos
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	Input.parse_input_event(up)
	await _frames(3)

func _shot(path: String) -> void:
	var bridge := current_scene.get_node_or_null("CobraCampaign")
	if bridge and not root.get_node("CampaignState").has_campaign_flag(&"harbor_delivery_complete"):
		var card: Control = bridge.get("_objective_card")
		_check(card != null and not card.is_visible_in_tree(), "Cobra objective card stays hidden before onboarding completes")
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png(path)
	print("Saved screenshot: ", path)

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var settings := root.get_node("SettingsManager")
	var temp_dir := OS.get_temp_dir().path_join("geteco_ui_test_%d" % OS.get_process_id())
	DirAccess.make_dir_recursive_absolute(temp_dir)
	settings.set("_settings_path", temp_dir.path_join("settings.cfg"))

	var target_res := Vector2i(1280, 720)
	var all_args := OS.get_cmdline_user_args()
	all_args.append_array(OS.get_cmdline_args())
	for a in all_args:
		if "--1080p" in a or "--1920" in a:
			target_res = Vector2i(1920, 1080)

	root.size = target_res
	root.content_scale_size = target_res
	print("Testing UI Comfort and Armed Isolation at: ", target_res)

	var campaign := root.get_node("CampaignState")
	var saves := root.get_node("SaveManager")
	campaign.reset_campaign()
	saves.clear_pending_save()
	campaign.set_campaign_flag(&"harbor_arrival_seen", true)
	campaign.set_campaign_flag(&"harbor_arrival_call_complete", true)

	settings.set_language("pt_BR")

	var world: Node2D = (load("res://world/harbor/HarborGame.tscn") as PackedScene).instantiate()
	root.add_child(world)
	current_scene = world
	await _frames(20)

	var player: CharacterBody2D = world.get_node("Player")
	player.show()
	player.set_physics_process(true)
	player.set_dialogue_active(false)
	var garage: Node2D = world.get_node("Interiors").garage_interior
	var npc: Node2D = garage.jager_npc
	var board = garage.mission_board
	var bridge = world.get_node_or_null("CobraCampaign")
	var arrival_ctrl = world.campaign_controller
	var arrival_card: Control = arrival_ctrl.get("_obj_card") as Control

	# Spawn test boarding vehicle next to player
	var test_car := TestBoardingVehicle.new()
	world.add_child(test_car)
	test_car.global_position = player.global_position + Vector2(20, 0)

	# Arm Dante
	player.active_weapon_id = "pistol"
	player.weapon_inventory["pistol"] = true
	player.weapon_inventory["fists"] = true
	player.weapon_inventory["knife"] = true
	var ammo_dict: Dictionary = player.weapon_ammo
	ammo_dict["pistol"] = {"clip": 12, "reserve": 60}
	player.weapon_ammo = ammo_dict
	var initial_ammo: int = player.weapon_ammo["pistol"]["clip"]
	var initial_health: int = player.health
	print("ARMED CHECK: Initial weapon=", player.active_weapon_id, " ammo clip=", initial_ammo, " health=", initial_health)

	var res_tag := "%dx%d" % [target_res.x, target_res.y]

	# TEST 1: MACIOTA DIALOGUE, BILINGUAL STRINGS & HUD ABSENCE
	print("\n--- TEST 1: MACIOTA DIALOGUE, BILINGUAL STRINGS & HUD ABSENCE ---")
	player.global_position = npc.global_position + Vector2(0, 30)
	test_car.global_position = player.global_position + Vector2(25, 0)
	await _frames(8)
	await _key(KEY_E)
	_check(npc.is_talking, "Maciota dialogue opens")
	_check(npc.dialogue_box.visible, "Dialogue box is visible")
	_check(player.is_control_disabled, "Player controls disabled during dialogue")
	_check(player.is_in_dialogue, "Player is_in_dialogue is true")

	await _frames(2)
	_check(arrival_card != null and not arrival_card.visible, "Arrival objective card is COMPLETELY HIDDEN during Maciota dialogue")

	_check(npc.name_label.text.contains("O REI DA NOITE"), "Speaker title is PT-BR: " + npc.name_label.text)
	_check(npc.text_label.text.begins_with("Dante! A viagem foi longa?"), "Dialogue body in PT-BR matches localization: " + npc.text_label.text.left(35))
	_check(npc.continue_hint.text.contains("Continuar"), "Continue hint in PT-BR: " + npc.continue_hint.text)
	await _shot("d:/geteco/game/tests/visual/ui_dialogue_maciota_pt_%s.png" % res_tag)

	settings.set_language("en")
	await _frames(6)
	_check(npc.name_label.text.contains("KING OF THE NIGHT"), "Speaker title translates to EN: " + npc.name_label.text)
	_check(npc.text_label.text.begins_with("Dante! Long trip?"), "Dialogue body translates to EN: " + npc.text_label.text.left(35))
	_check(npc.continue_hint.text.contains("Continue"), "Continue hint translates to EN: " + npc.continue_hint.text)
	await _shot("d:/geteco/game/tests/visual/ui_dialogue_maciota_en_%s.png" % res_tag)

	settings.set_language("pt_BR")
	await _frames(4)

	var box_center: Vector2 = npc.dialogue_box.get_global_rect().get_center()
	await _click_at(box_center)
	_check(player.weapon_ammo["pistol"]["clip"] == initial_ammo, "Clicking dialogue does NOT fire pistol (ammo: %d)" % player.weapon_ammo["pistol"]["clip"])
	_check(player.health == initial_health, "Health unaffected during dialogue click")

	player.active_weapon_id = "fists"
	await _click_at(box_center)
	_check(player.get("_melee_swing_timer") <= 0.0, "Clicking dialogue with fists does NOT swing punch")

	player.active_weapon_id = "knife"
	await _click_at(box_center)
	_check(player.get("_melee_swing_timer") <= 0.0, "Clicking dialogue with knife does NOT swing knife")

	player.active_weapon_id = "pistol"

	test_car.enter_called = false
	for _line in 8:
		if not npc.is_talking:
			break
		await _key(KEY_SPACE)

	_check(not npc.is_talking, "Dialogue completes cleanly")
	_check(not test_car.enter_called, "Dialogue interaction does NOT enter adjacent vehicle")
	_check(player.visible, "Player remains on foot (not inside car)")
	await _frames(4)
	_check(not player.is_control_disabled, "Player controls restored after dialogue")
	_check(player.weapon_ammo["pistol"]["clip"] == initial_ammo, "Ammo completely untouched after full conversation")

	# TEST 2: CHALKBOARD VIEWPORT BOUNDS, SCROLLING & HUD ABSENCE
	print("\n--- TEST 2: CHALKBOARD VIEWPORT BOUNDS, SCROLLING & HUD ABSENCE ---")
	player.global_position = board.global_position + Vector2(0, 25)
	test_car.global_position = player.global_position + Vector2(25, 0)
	await _frames(8)
	await _key(KEY_E)
	await _frames(8)
	_check(board.is_ui_open, "Board opens with native E")
	_check(player.is_control_disabled, "Player control disabled while board is open")

	_check(not arrival_card.visible, "Arrival objective card is COMPLETELY HIDDEN during chalkboard")

	var board_rect: Rect2 = board.panel.get_global_rect()
	var close_rect: Rect2 = board._close_btn.get_global_rect()
	print("BOARD RECT: ", board_rect, " VIEWPORT: ", target_res)
	print("CLOSE BTN RECT: ", close_rect)
	_check(board_rect.position.y >= 0.0, "Board panel top is inside viewport (%f >= 0)" % board_rect.position.y)
	_check(board_rect.end.y <= float(target_res.y), "Board panel bottom is inside viewport (%f <= %d)" % [board_rect.end.y, target_res.y])
	_check(board_rect.position.x >= 0.0, "Board panel left is inside viewport (%f >= 0)" % board_rect.position.x)
	_check(board_rect.end.x <= float(target_res.x), "Board panel right is inside viewport (%f <= %d)" % [board_rect.end.x, target_res.x])
	_check(close_rect.end.y <= float(target_res.y) - 10.0, "Board close button is strictly within viewport with margin (%f <= %d)" % [close_rect.end.y, target_res.y - 10])

	_check(board.orders_scroll != null and board.orders_scroll.visible, "Board uses ScrollContainer for orders list")
	var btn_count := 0
	for child in board.orders_vbox.get_children():
		if child is Button:
			btn_count += 1
	_check(btn_count >= 1, "Board contains authored contract buttons (%d found)" % btn_count)

	for _s in range(btn_count):
		await _key(KEY_DOWN)
		await _frames(2)
	_check(board._close_btn.get_global_rect().end.y <= float(target_res.y), "Close button remains within viewport after scrolling")

	_check(board.nav_hint_label.text.contains("Escolher") and board.nav_hint_label.text.contains("Fechar"), "Board navigation hint in PT-BR: " + board.nav_hint_label.text)
	_check(board._close_btn.text.begins_with("FECHAR"), "Board close button in PT-BR: " + board._close_btn.text)

	await _click_at(board_rect.get_center())
	_check(player.weapon_ammo["pistol"]["clip"] == initial_ammo, "Clicking board does NOT fire pistol")

	await _shot("d:/geteco/game/tests/visual/ui_board_pt_%s.png" % res_tag)

	settings.set_language("en")
	await _frames(6)
	_check(board.nav_hint_label.text.contains("Choose") and board.nav_hint_label.text.contains("Close"), "Board navigation hint in EN: " + board.nav_hint_label.text)
	_check(board._close_btn.text.begins_with("CLOSE"), "Board close button in EN: " + board._close_btn.text)
	await _shot("d:/geteco/game/tests/visual/ui_board_en_%s.png" % res_tag)

	settings.set_language("pt_BR")
	await _frames(4)

	test_car.enter_called = false
	board._focus_first_selectable()
	await _frames(2)

	await _key(KEY_ENTER)
	await _frames(6)
	_check(not board.is_ui_open, "Contract accepted and board closed")
	_check(not player.is_control_disabled, "Player control returned after board accept")
	_check(player.weapon_ammo["pistol"]["clip"] == initial_ammo, "Ammo preserved after contract accept")
	_check(not test_car.enter_called, "Car was not entered while accepting contract")

	# TEST 3: COMPACT OBJECTIVE HUD & NON-OVERLAPPING
	print("\n--- TEST 3: COMPACT OBJECTIVE HUD & NON-OVERLAPPING ---")
	_check(arrival_card != null and not arrival_card.visible, "Persistent objective prose stays hidden in gameplay")
	var hud = null
	for h in root.find_children("*", "CanvasLayer", true, false):
		if h.is_in_group("hud"):
			hud = h
			break
	_check(hud != null, "HUD CanvasLayer found")
	if hud != null:
		var top_left = hud.health_bar as Control
		var top_right = hud.get_node("RootMargin/TopRightPanel") as Control
		var weather = top_right.get_node_or_null("WeatherReadout")
		print("HUD: TopLeft rect=", top_left.get_global_rect(), " TopRight rect=", top_right.get_global_rect())
		print("HUD: Objective Card rect=", arrival_card.get_global_rect())
		_check(arrival_card.get_global_rect().position.y >= top_left.get_global_rect().end.y - 5, "Objective card is safely below Health/Armor/Weapon")
		_check(not arrival_card.get_global_rect().intersects(top_right.get_global_rect()), "Objective card does NOT overlap Money/Stars/Weather")
		_check(weather != null and weather.visible, "Weather/Clock readout is mounted and preserved in TopRightPanel")

	var arrival_tag: Label = arrival_ctrl.get("_obj_tag") as Label
	_check(arrival_tag != null and arrival_tag.text == "🎯 OBJETIVO ATUAL", "Objective tag in PT-BR: " + (arrival_tag.text if arrival_tag else "null"))
	await _shot("d:/geteco/game/tests/visual/ui_gameplay_hud_objective_pt_%s.png" % res_tag)

	settings.set_language("en")
	await _frames(6)
	_check(arrival_tag != null and arrival_tag.text == "🎯 CURRENT OBJECTIVE", "Objective tag translates to EN: " + (arrival_tag.text if arrival_tag else "null"))
	await _shot("d:/geteco/game/tests/visual/ui_gameplay_hud_objective_en_%s.png" % res_tag)

	settings.set_language("pt_BR")
	await _frames(4)

	# TEST 4: JOURNAL MODAL & REST
	print("\n--- TEST 4: JOURNAL MODAL & REST ---")
	campaign.set_campaign_flag(&"harbor_delivery_complete", true)
	if bridge != null:
		bridge._refresh()
		await _frames(4)
		await _key(KEY_J)
		await _frames(8)
		_check(bridge._journal.visible, "Journal opens with J")
		_check(player.is_control_disabled, "Player movement disabled while journal is open")

		var cobra_card: Control = bridge.get("_objective_card") as Control
		_check(not arrival_card.visible, "Arrival card is COMPLETELY HIDDEN during journal")
		_check(cobra_card != null and not cobra_card.visible, "Cobra card is COMPLETELY HIDDEN during journal")

		_check(bridge._journal_button != null and not bridge._journal_button.get_global_rect().intersects(hud.get_node("RootMargin/TopRightPanel").get_global_rect()), "Journal button does NOT overlap Money/Stars/Weather")

		var journal_rect: Rect2 = bridge._journal.get_global_rect()
		_check(journal_rect.position.y >= 0.0 and journal_rect.end.y <= float(target_res.y), "Journal fits strictly inside viewport height")

		await _click_at(journal_rect.get_center())
		_check(player.weapon_ammo["pistol"]["clip"] == initial_ammo, "Clicking journal does NOT fire weapon")

		await _shot("d:/geteco/game/tests/visual/ui_journal_pt_%s.png" % res_tag)
		settings.set_language("en")
		await _frames(6)
		_check(bridge._journal_button.text.contains("Journal"), "Journal button in EN: " + bridge._journal_button.text)
		await _shot("d:/geteco/game/tests/visual/ui_journal_en_%s.png" % res_tag)
		settings.set_language("pt_BR")
		await _frames(4)

		await _key(KEY_J)
		await _frames(6)
		_check(not bridge._journal.visible, "Journal closes with J")
		_check(not player.is_control_disabled, "Player controls restored after journal close")

	# TEST 5: CLINIC TRIAGE TERMINAL & ARMED ISOLATION
	print("\n--- TEST 5: CLINIC TRIAGE TERMINAL & ARMED ISOLATION ---")
	var interiors: Node = world.get_node("Interiors")
	var clinic: Node = interiors.get("clinic_interior") as Node
	_check(clinic != null, "Clinic interior node exists (Interiors.clinic_interior)")
	if clinic == null:
		push_error("Clinic interior is missing from Interiors!")
		quit(1)
		return

	player.global_position = clinic.global_position + Vector2(210, 60)
	test_car.global_position = player.global_position + Vector2(25, 0)
	await _frames(8)
	await _key(KEY_E)
	await _frames(6)
	_check(clinic.triage_dialog != null and clinic.triage_dialog.visible, "Clinic triage dialog opens on KEY_E")
	if not clinic.triage_dialog.visible:
		push_error("Clinic triage dialog failed to open!")
		quit(1)
		return

	_check(not arrival_card.visible, "Arrival objective card is COMPLETELY HIDDEN during clinic terminal")
	if bridge != null and bridge.get("_objective_card"):
		_check(not (bridge.get("_objective_card") as Control).visible, "Cobra objective card is COMPLETELY HIDDEN during clinic terminal")

	var clinic_rect: Rect2 = clinic.triage_dialog.get_global_rect()
	_check(clinic_rect.end.y <= float(target_res.y), "Clinic triage dialog fits strictly in viewport (%f <= %d)" % [clinic_rect.end.y, target_res.y])

	var clinic_center: Vector2 = clinic_rect.get_center()
	await _click_at(clinic_center)
	_check(player.weapon_ammo["pistol"]["clip"] == initial_ammo, "Clicking clinic terminal does NOT fire pistol")

	player.active_weapon_id = "fists"
	await _click_at(clinic_center)
	_check(player.get("_melee_swing_timer") <= 0.0, "Clicking clinic terminal with fists does NOT punch")
	player.active_weapon_id = "pistol"

	await _shot("d:/geteco/game/tests/visual/ui_clinic_terminal_pt_%s.png" % res_tag)
	settings.set_language("en")
	await _frames(6)
	_check(clinic.triage_text.text.begins_with("MEDICAL TRIAGE"), "Active clinic text translates to English")
	await _shot("d:/geteco/game/tests/visual/ui_clinic_terminal_en_%s.png" % res_tag)
	settings.set_language("pt_BR")
	await _frames(4)

	test_car.enter_called = false
	await _key(KEY_ESCAPE)
	await _frames(6)
	_check(not clinic.triage_dialog.visible, "Clinic triage dialog closes with ESC")
	_check(not test_car.enter_called, "Closing clinic terminal does NOT enter adjacent vehicle")
	_check(player.visible, "Player remains on foot")
	await _frames(4)
	_check(not player.is_control_disabled, "Player controls restored after clinic terminal close")

	print("\n==========================================")
	print("UI COMFORT & ARMED ISOLATION FAILURES: ", failures.size())
	for f in failures:
		print("  - ", f)
	print("==========================================")
	world.queue_free()
	await _frames(4)
	quit(0 if failures.is_empty() else 1)
