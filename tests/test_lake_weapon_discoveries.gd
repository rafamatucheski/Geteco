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
	var cabin := preload("res://world/mountain_pass/MountainCabinInterior.gd").new()
	cabin.position = Vector2(2400, 1000)
	world.add_child(cabin)
	var rifle = cabin.get_node("LegendaryRifleStation")
	player.global_position = rifle.global_position
	player.notices.clear()
	rifle._collect(player)
	check(player.is_weapon_shop_unlocked("hunting_rifle") and player.weapon_ammo.hunting_rifle.reserve == 35, "Cabin rifle discovery unlocks buying and preserves its authored ammunition")
	rifle._collect(player)
	check(player.notices.size() == 1, "Cabin unlock notice is also emitted once")
	var saved: Dictionary = JSON.parse_string(JSON.stringify(player.serialize()))
	player.world_pickups_collected.clear()
	player.restore(saved)
	check(player.is_weapon_shop_unlocked("smg") and player.is_weapon_shop_unlocked("hunting_rifle"), "Both unlocks survive a JSON save and restore")
	var restored_plane := preload("res://world/mountain_pass/MountainCargoPlane.gd").new()
	restored_plane.position = Vector2(5000, 0)
	world.add_child(restored_plane)
	player.notices.clear()
	restored_plane.get_node("CargoSMG")._process(0.1)
	check(restored_plane.get_node("CargoSMG").collected and player.notices.is_empty(), "Revisiting a collected item hides it without repeating the notice")
	var shop := preload("res://world/harbor/interiors/HarborAmmunationInterior.gd").new()
	shop.position = Vector2(6000, 1000)
	world.add_child(shop)
	player.weapon_inventory.erase("smg")
	player.weapon_inventory.erase("hunting_rifle")
	shop._refresh_weapon_buttons()
	check(not shop.weapon_buttons.smg.disabled and not shop.weapon_buttons.hunting_rifle.disabled, "City store offers the discovered guns for repurchase")
	shop.is_near_counter = true
	shop._buy_weapon("smg")
	shop._buy_weapon("hunting_rifle")
	check(player.weapon_inventory.smg and player.weapon_inventory.hunting_rifle and player.money == initial_money-6000, "Store purchases use actual inventory and catalog prices")
	var water := preload("res://world/mountain_pass/MountainLakeWater.gd").new()
	water.position = plane.position
	water.polygon = PackedVector2Array([Vector2(-400,-400),Vector2(400,-400),Vector2(400,400),Vector2(-400,400)])
	water.plane = plane
	world.add_child(water)
	var resolver := preload("res://audio/footsteps/FootstepSurfaceResolver.gd")
	player.global_position = water.to_global(Vector2(200, 120))
	player.velocity = Vector2(50, 0)
	check(resolver.resolve(player, false) == "water", "Lake footstep detection respects translated region coordinates")
	water.actor_step(player, false)
	check(water.marks.size() == 1 and water.marks[0].water, "Walking in water creates a ripple and splash")
	water._process(0.1)
	check(water.marks.size() == 1, "Idle updates do not create footsteps")
	player.global_position = water.to_global(Vector2(410, 120))
	water.actor_step(player, false)
	check(not water.marks.back().water, "Leaving the lake creates fading wet footprints")
	player.global_position = plane.to_global(plane.project_floor(Vector2(0, 0)))
	check(resolver.resolve(player, false) == "metal", "Walking inside the plane uses a dry metal floor, not water")
	var count := water.marks.size()
	water.actor_step(player, false)
	check(water.marks.size() == count, "The plane's dry deck does not emit splashes")
	player.global_position = water.to_global(Vector2(200, 120))
	for i in 70: water.actor_step(player, true)
	check(water.marks.size() == water.MAX_MARKS, "Water effects have a bounded population")
	water._process(5.0)
	check(water.marks.is_empty() and not water.is_processing(), "All marks expire and stop their update loop")
	var bank := preload("res://audio/footsteps/FootstepAudioBank.gd")
	var sound: AudioStreamWAV = bank.sound("water", 0)
	check(sound.data.size() == 13230 and sound == bank.sound("water", 0) and sound.data != bank.sound("water", 1).data, "Water audio provides cached, distinct splash variations")
	root.size = Vector2i(640,360)
	root.content_scale_size = root.size
	await process_frame
	player.weapon_wheel.show_notice("PRESA DO INVERNO LIBERADA PARA COMPRAR NA LOJA · +35 BALAS")
	for i in 3: await process_frame
	var notice_rect: Rect2 = player.weapon_wheel._notice_panel.get_global_rect()
	check(player.weapon_wheel.get_parent() is CanvasLayer and notice_rect.position.x >= 0 and notice_rect.end.x <= 640 and notice_rect.position.y >= 0 and notice_rect.end.y <= 360, "Unlock notice remains visible on screen at distant world coordinates and small resolutions")
	player.weapon_wheel.notice_until = 0
	player.weapon_wheel._process(0)
	check(not player.weapon_wheel._notice_panel.visible, "Unlock notice disappears after its duration")
	print("LAKE_WEAPON_DISCOVERIES failures=", failures)
	world.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
