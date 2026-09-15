extends SceneTree

var failures: Array[String] = []

class NoticePlayer extends "res://characters/Player.gd":
	var notices: Array[String] = []
	func _show_weapon_notice(message: String) -> void:
		notices.append(message)

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)

func run() -> void:
	var world := Node2D.new()
	world.position = Vector2(4300, -4960)
	root.add_child(world)
	current_scene = world
	var player := NoticePlayer.new()
	var camera := Camera2D.new()
	camera.name = "Camera"
	player.add_child(camera)
	var collision := CollisionShape2D.new()
	collision.name = "Collision"
	collision.shape = CircleShape2D.new()
	collision.shape.radius = 5
	player.add_child(collision)
	player.collision_layer = 4
	world.add_child(player)
	player.set_physics_process(false)
	player.world_pickups_collected.clear()
	player.weapon_inventory.erase("smg")
	player.weapon_inventory.erase("hunting_rifle")
	player.money = 20000
	var initial_money := player.money
	player.buy_weapon("smg")
	player.buy_weapon("hunting_rifle")
	check(player.money == initial_money and not player.weapon_inventory.get("smg", false) and not player.weapon_inventory.get("hunting_rifle", false), "Undiscovered guns cannot be bought or charge money")
	var plane := preload("res://world/mountain_pass/MountainCargoPlane.gd").new()
	plane.position = Vector2(800, 0)
	world.add_child(plane)
	var smg = plane.get_node("CargoSMG")
	player.global_position = plane.to_global(plane.project_floor(Vector2(0,-4.8)))
	var weapon: Node3D = smg.model.get_node("FloorWeapon")
	var halo: Node3D = smg.model.get_node("FloorHalo")
	var initial_y := weapon.position.y
	var initial_rotation: float = smg.model.rotation.y
	smg._process(0.4)
	check(weapon.global_position.y > 0.8 and halo.global_position.y > 0.215, "SMG and halo clear the cargo deck")
	check(not is_equal_approx(weapon.position.y,initial_y) and not is_equal_approx(smg.model.rotation.y,initial_rotation), "SMG floats and rotates before collection")
	player.global_position = world.global_position
	smg._collect(player)
	check(not smg.collected, "Plane loot cannot be collected from outside")
	player.global_position = smg.global_position
	player.notices.clear()
	smg._collect(player)
	check(smg.collected and player.weapon_ammo.smg.clip == 20 and player.weapon_ammo.smg.reserve == 0, "Plane SMG grants exactly 20 loaded rounds, with no catalog bonus")
	check(player.is_weapon_shop_unlocked("smg") and not player.is_weapon_shop_unlocked("hunting_rifle"), "Plane discovery unlocks only the SMG")
	check(player.notices.size() == 1 and "LIBERADA PARA COMPRAR NA LOJA" in player.notices[0], "Exactly one unlock notice on first pickup")
	smg._collect(player)
	check(player.notices.size() == 1 and player.weapon_ammo.smg.clip == 20, "Repeat contact grants no ammo or notice")
	var saved: Dictionary = JSON.parse_string(JSON.stringify(player.serialize()))
	player.world_pickups_collected.clear()
	player.restore(saved)
	var restored := preload("res://world/mountain_pass/MountainCargoPlane.gd").new()
	world.add_child(restored)
	restored.get_node("CargoSMG")._process(0.1)
	check(restored.get_node("CargoSMG").collected and not restored.get_node("CargoSMG").model.visible, "Saved SMG stays hidden on revisit")
	player.global_position = plane.to_global(plane.project_floor(Vector2(0.1,-6.4)))
	var money_before: int = player.money
	check(plane.claim_treasure(player) and player.money == money_before+1800, "Chest grants its cash reward")
	check(plane.treasure_lid.rotation.x < -1.0 and not plane.gold.visible, "Claimed chest opens and empties")
	check(not plane.claim_treasure(player) and player.money == money_before+1800, "Chest cannot grant cash twice")
	var chest_save: Dictionary = JSON.parse_string(JSON.stringify(player.serialize()))
	player.world_pickups_collected.clear()
	player.restore(chest_save)
	restored._process(0.2)
	check(restored.collected and restored.treasure_lid.rotation.x < -1.0, "Chest stays open after save restore")
	print("PLANE_LOOT_PRESENTATION failures=",failures)
	world.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
