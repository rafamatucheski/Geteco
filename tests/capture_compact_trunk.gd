extends SceneTree

class TestGarage extends Node2D:
	func get_vehicle_bay_position() -> Vector2: return global_position

class TestManager extends "res://world/harbor/monaliza/PersonalCarManager.gd":
	func _ready() -> void: _build_ui()

var failures: Array[String] = []

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok: failures.append(label)

func run() -> void:
	create_timer(30).timeout.connect(func(): quit(2))
	root.content_scale_size = Vector2i.ZERO
	var world := Node2D.new()
	root.add_child(world)
	current_scene = world
	var player = preload("res://Player.gd").new()
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
	player.world_pickups_collected.append("monaliza_starter_case")
	player.personal_loadout_enabled = true
	for id in ["pistol", "shotgun", "knife", "grenade", "ak47"]:
		player.add_weapon_loot(StringName(id), 24, false)
	player.personal_loadout = {"curta":"pistol", "longa":"shotgun", "corpo":"knife", "granada":"grenade"}
	player.global_position = car.global_position - car.global_transform.x * 47
	root.get_node("SettingsManager").text_scale = 1.0
	manager.open_panel()
	for resolution in [Vector2i(1280,720), Vector2i(1920,1080), Vector2i(960,720)]:
		root.size = resolution
		await create_timer(1.6).timeout
		var rect: Rect2 = manager.panel.get_global_rect()
		check(rect.position.y >= 0 and rect.end.y <= resolution.y, "panel stays inside " + str(resolution))
		check(manager.live_view.get_global_rect().end.y <= rect.position.y, "3D view stays above controls " + str(resolution))
		check(rect.size.y < resolution.y * (0.28 if resolution.x >= 1280 else 0.45), "compact height " + str(rect.size))
		for slot in manager.live_view.slot_models:
			var weapon: Node3D = manager.live_view.slot_models[slot]
			var visible_bounds := Rect2(Vector2.ZERO, Vector2(manager.live_view.stage.size))
			var inside := true
			for mesh in weapon.find_children("*", "MeshInstance3D", true, false):
				for index in 8:
					var point: Vector2 = manager.live_view.camera.unproject_position(mesh.global_transform * mesh.get_aabb().get_endpoint(index))
					inside = inside and visible_bounds.has_point(point)
			check(inside, "whole weapon visible: " + slot)
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("D:/geteco/artifacts/trunk-compact-%dx%d.png" % [resolution.x,resolution.y])
	root.size = Vector2i(1280,720)
	var choice: OptionButton = manager.rows.find_child("Slot_longa", true, false)
	for index in choice.item_count:
		if choice.get_item_metadata(index) == "ak47": choice.item_selected.emit(index); break
	await create_timer(1.6).timeout
	check(manager.weapon_stats.visible, "inspection details visible")
	check(manager.live_view.get_global_rect().end.y <= manager.panel.position.y, "details keep viewport clear")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("D:/geteco/artifacts/trunk-compact-inspection.png")
	manager.close_panel()
	check(player.personal_loadout.longa == "shotgun", "cancel preserves equipped loadout")
	manager.open_panel()
	manager.set_slot("longa", "ak47")
	manager.save_loadout()
	check(player.personal_loadout.longa == "ak47" and not player.is_control_disabled, "equip applies selection and releases controls")
	root.get_node("SettingsManager").text_scale = 1.25
	manager.open_panel()
	await create_timer(0.2).timeout
	check(manager.panel.get_global_rect().end.x <= 1280 and manager.panel.size.y < 200, "large text fits at 720p")
	manager.close_panel()
	print("COMPACT TRUNK FAILURES ", failures)
	quit(0 if failures.is_empty() else 1)
