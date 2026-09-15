extends SceneTree

# Keep the real startup, save restoration and achievement logic; omit 3D art.
class TestPlayer extends "res://characters/Player.gd":
	func _build_dante_3d_viewport() -> void: pass
	func _rebuild_dante_costume() -> void: pass
	func _update_equipped_weapon_3d_mesh() -> void: pass
	func _physics_process(_delta: float) -> void: pass

class TestHUD extends Node:
	var notifications: Array[String] = []
	func show_achievement(title: String, _desc: String) -> void:
		notifications.append(title)
	func set_money(_money: int) -> void: pass
	func update_health(_health: int) -> void: pass
	func set_weapon_info(_id: String, _ammo: Dictionary) -> void: pass
	func set_armor(_armor: int, _max_armor: int) -> void: pass

var failures: Array[String] = []
var unlocks: Array[String] = []

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok: failures.append(label)

func run() -> void:
	var world := Node2D.new()
	root.add_child(world)
	current_scene = world
	var hud := TestHUD.new()
	hud.add_to_group("hud")
	world.add_child(hud)
	var save_manager := root.get_node("SaveManager")
	save_manager.clear_pending_save()
	for scenario in ["new_game", "saved", "legacy", "low_money"]:
		var data := {"money": 12000, "races_finished": 1}
		if scenario == "saved":
			data["unlocked_achievements"] = ["first_grand", "shark", "first_race"]
		elif scenario == "low_money":
			data = {"money": 100, "unlocked_achievements": []}
		if scenario != "new_game":
			save_manager._pending_save_data = {"player": data}
		hud.notifications.clear()
		unlocks.clear()
		var player := TestPlayer.new()
		var camera := Camera2D.new()
		camera.name = "Camera"
		player.add_child(camera)
		player.achievement_unlocked.connect(func(id: String, _title: String): unlocks.append(id))
		world.add_child(player)
		for i in 4: await process_frame
		check(hud.notifications.is_empty() and unlocks.is_empty(), scenario + ": startup stays silent")
		if scenario == "low_money":
			check(player.unlocked_achievements.is_empty(), "Loaded save replaces initial achievements")
		else:
			check("first_grand" in player.unlocked_achievements, scenario + ": existing progress retained")
		if scenario in ["saved", "legacy"]:
			check("shark" in player.unlocked_achievements and "first_race" in player.unlocked_achievements, scenario + ": saved criteria reconciled")
		player._refresh_weapon_ui()
		check(hud.notifications.is_empty() and unlocks.is_empty(), scenario + ": later HUD refresh stays silent")
		player.report_chop_shop_delivery(100)
		check(hud.notifications.size() == 1 and unlocks == ["first_scrap"], scenario + ": new achievement notifies once")
		player.report_chop_shop_delivery(100)
		player._unlock_achievement("first_scrap")
		check(hud.notifications.size() == 1 and unlocks.size() == 1, scenario + ": earned achievement never repeats")
		check("first_scrap" in player.serialize()["unlocked_achievements"], scenario + ": new achievement persists")
		player.queue_free()
		for i in 2: await process_frame
		for child in world.get_children():
			if child is CanvasLayer: child.queue_free()
		await process_frame
	print("ACHIEVEMENT_STARTUP failures=", failures)
	quit(0 if failures.is_empty() else 1)
