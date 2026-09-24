extends SceneTree
const CUSTOM = preload("res://guns/WeaponCustomization.gd")
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(value: bool, label: String) -> void:
	print(("PASS " if value else "FAIL ") + label)
	if not value: failures += 1
func press_g(echo := false) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = KEY_G
	event.pressed = true
	event.echo = echo
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	event = InputEventKey.new()
	event.physical_keycode = KEY_G
	Input.parse_input_event(event)
	Input.flush_buffered_events()
func run() -> void:
	create_timer(60).timeout.connect(func(): quit(2))
	root.get_node("SaveManager")._save_dir = OS.get_temp_dir().path_join("weapon_customization_%d" % OS.get_process_id()) + "/"
	root.get_node("SaveManager").clear_pending_save()
	var world := Node2D.new()
	root.add_child(world)
	current_scene = world
	var player = load("res://characters/Player.gd").new()
	var camera := Camera2D.new()
	camera.name = "Camera"
	player.add_child(camera)
	world.add_child(player)
	player.set_physics_process(false)
	player.personal_loadout_enabled = false
	player.money = 1000
	check(player.customize_weapon("knife", "install") == "ARMA INCOMPATÍVEL", "Melee cannot accept flashlight")
	check(player.customize_weapon("pistol", "install") == "COMPRE A ARMA PRIMEIRO", "Unowned weapon cannot be customized")
	player.weapon_inventory.pistol = true
	player.weapon_inventory.smg = true
	player.equip_weapon("pistol")
	player.money = 349
	check(player.customize_weapon("pistol", "install") == "SALDO INSUFICIENTE" and player.money == 349 and player.weapon_customization.is_empty(), "Insufficient balance is atomic")
	player.money = 1000
	var room = load("res://world/harbor/interiors/HarborAmmunationInterior.gd").new()
	world.add_child(room)
	player.global_position = room.spawn_point.global_position
	room.open_catalog()
	check(room.active and room.customize_button.visible, "Real catalog exposes customization")
	check(room.workbench_button.text == "PERSONALIZAR ARMA" and room.workbench_button.custom_minimum_size.y >= 46.0 and room.workbench_button.size_flags_stretch_ratio > 1.0, "Personalize action is the prominent catalog control")
	room.customize_button.pressed.emit()
	check(player.money == 650 and CUSTOM.installed(player.weapon_customization, "pistol"), "Catalog installs and charges once")
	check(not CUSTOM.installed(player.weapon_customization, "smg"), "Attachments are per weapon")
	check(player.current_gun_mesh.has_node("TacticalFlashlight"), "Held model includes attachment")
	check(room.gun.get_child(0).has_node("TacticalFlashlight"), "Store preview includes attachment")
	check(player.weapon_flashlight.BEAM_SCALE <= 0.55 and player.weapon_flashlight.BEAM_OFFSET <= 92.0, "Flashlight uses one finite car-style beam")
	check(player.customize_weapon("pistol", "wide") == "MODIFICAÇÃO INVÁLIDA", "Flashlight exposes no redundant beam mode")
	room.customize_button.pressed.emit()
	check(not CUSTOM.installed(player.weapon_customization, "pistol"), "Bench removes attachment")
	room.customize_button.pressed.emit()
	check(player.money == 650, "Reinstallation is free")
	if DisplayServer.get_name() != "headless":
		for i in 5: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(OS.get_temp_dir().path_join("weapon-customization-catalog.png"))
	room.close_catalog()
	player.global_position = Vector2(1000,1000)
	await process_frame
	press_g()
	check(player.weapon_flashlight.enabled and player.weapon_flashlight.lamp.visible, "G enables actual light")
	press_g(true)
	check(player.weapon_flashlight.enabled, "Holding G does not flicker")
	press_g()
	check(not player.weapon_flashlight.enabled, "Second G switches off")
	root.get_node("GameInput").remapping = true
	press_g()
	check(not player.weapon_flashlight.enabled, "Rebinding controls cannot toggle flashlight")
	root.get_node("GameInput").remapping = false
	player.is_dead = true
	press_g()
	check(not player.weapon_flashlight.enabled, "Dead player cannot activate flashlight")
	player.is_dead = false
	player.weapon_flashlight.toggle()
	player.set_dialogue_active(true)
	player.weapon_flashlight._physics_process(0)
	check(not player.weapon_flashlight.enabled, "Dialogue switches light off")
	player.set_dialogue_active(false)
	player.weapon_flashlight.toggle()
	player.equip_weapon("smg")
	check(not player.weapon_flashlight.enabled, "Weapon switch turns light off")
	player.equip_weapon("pistol")
	player.weapon_flashlight.toggle()
	player.hide()
	check(not player.weapon_flashlight.enabled, "Boarding/hidden actor switches light off")
	player.show()
	var save: Dictionary = player.serialize()
	player.weapon_customization.clear()
	player.restore(save)
	check(CUSTOM.installed(player.weapon_customization, "pistol") and not player.weapon_customization.pistol.has("beam"), "Save round-trip preserves the single-mode attachment")
	check(not player.weapon_flashlight.enabled, "Restored light starts safely off")
	save.erase("weapon_customization")
	player.restore(save)
	check(player.weapon_customization.is_empty(), "Legacy save defaults to no modifications")
	check(CUSTOM.normalize({"pistol": "bad", "knife": {"owned":true}}).is_empty(), "Malformed or incompatible saved entries are discarded")
	check(player.customize_weapon("pistol", "bogus") == "MODIFICAÇÃO INVÁLIDA" and player.money == 650, "Invalid operation cannot charge")
	print("WEAPON CUSTOMIZATION: %d failures" % failures)
	quit(1 if failures else 0)
