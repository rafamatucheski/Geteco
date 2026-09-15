extends SceneTree

var failures: Array[String] = []

class TestGarage extends Node2D:
	func get_vehicle_bay_position() -> Vector2: return global_position

class TestManager extends "res://world/harbor/monaliza/PersonalCarManager.gd":
	func _ready() -> void:
		add_to_group("personal_car_manager")
		_build_ui()

func _initialize() -> void: _run.call_deferred()

func check(ok: bool, label: String) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok: failures.append(label)

func _run() -> void:
	create_timer(30).timeout.connect(func(): quit(2))
	var world := Node2D.new()
	root.add_child(world)
	current_scene = world
	var player = preload("res://characters/Player.gd").new()
	var camera := Camera2D.new()
	camera.name = "Camera"
	player.add_child(camera)
	world.add_child(player)
	player.set_physics_process(false)
	var car = preload("res://world/harbor/monaliza/MonalizaCar.gd").new()
	world.add_child(car)
	car.set_physics_process(false)
	car.unlocked = true
	var garage := TestGarage.new()
	world.add_child(garage)
	var manager := TestManager.new()
	manager.player = player
	manager.car = car
	manager.garage = garage
	world.add_child(manager)
	await process_frame
	check(player.active_weapon_id == "fists" and player.weapon_inventory.values().count(true) == 1, "new game has no weapons")
	check(player.weapon_ammo.pistol == {"clip":0,"reserve":0}, "new game has no pistol ammunition")
	player.global_position = car.global_position - car.global_transform.x * 47
	manager.open_panel()
	check(manager.panel.visible and car.trunk_open, "first trunk opens")
	check(player.weapon_inventory.values().count(true) == 2 and player.weapon_inventory.pistol, "only the pistol is granted")
	check(player.weapon_ammo.pistol == {"clip":12,"reserve":60}, "pistol starts loaded")
	check(manager.pending_loadout == {"curta":"pistol","longa":"","corpo":"","granada":""}, "other loadout spaces are empty")
	for slot in ["longa", "granada"]:
		check(manager.live_view.slot_models[slot].get_child_count() == 0 and manager.live_view.cutouts[slot].get_child_count() > 0, "empty space retains only a foam outline: " + slot)
	check(manager.first_trunk_hint._box.visible and manager.first_trunk_hint.layer > manager.panel.get_parent().layer, "tip is visible above trunk")
	check(manager.first_trunk_hint._box.anchor_left == 0.5 and manager.first_trunk_hint._box.anchor_top == 0.5, "tip is centered")
	await create_timer(1.5).timeout
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("D:/geteco/artifacts/monaliza-starter-tip.png")
	manager.close_panel()
	manager.open_panel()
	check(manager.first_trunk_hint == null and player.weapon_ammo.pistol == {"clip":12,"reserve":60}, "reopening repeats neither tip nor reward")
	if DisplayServer.get_name() != "headless":
		await create_timer(1.5).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("D:/geteco/artifacts/monaliza-starter-trunk.png")
	manager.close_panel()
	player.add_weapon_loot(&"shotgun",16,false)
	player.add_weapon_loot(&"grenade",3,false)
	check(player.personal_loadout.longa == "shotgun" and player.personal_loadout.granada == "grenade", "later pickups fill their own spaces")
	var snapshot: Dictionary = JSON.parse_string(JSON.stringify(player.serialize()))
	player.restore(snapshot)
	player.set_physics_process(false)
	car.unlocked = true
	player.global_position = car.global_position - car.global_transform.x * 47
	manager.open_panel()
	check(manager.first_trunk_hint == null and int(player.weapon_ammo.pistol.clip) == 12 and int(player.weapon_ammo.pistol.reserve) == 60, "saved game preserves consumed starter reward")
	check(manager.pending_loadout.longa == "shotgun" and manager.pending_loadout.granada == "grenade", "saved game preserves collected loadout")
	manager.close_panel()
	print("MONALIZA STARTER FAILURES ", failures)
	quit(0 if failures.is_empty() else 1)
