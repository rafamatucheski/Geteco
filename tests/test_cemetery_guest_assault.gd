extends SceneTree

var failures := 0

class Attacker extends CharacterBody2D:
	var health := 100

class Target extends CharacterBody2D:
	var health := 80
	func take_damage(amount: int, _source: Variant = null) -> void:
		health -= amount

class CemeteryFixture extends Node2D:
	func get_gate_position() -> Vector2:
		return global_position + Vector2(0, -350)

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, label: String) -> void:
	print(("PASS " if condition else "FAIL ") + label)
	if not condition: failures += 1

func _run() -> void:
	var scene := Node2D.new()
	root.add_child(scene)
	current_scene = scene

	var player := Attacker.new()
	player.add_to_group("player")
	player.collision_layer = 4
	player.collision_mask = 7
	var player_shape := CollisionShape2D.new()
	player_shape.shape = CircleShape2D.new()
	player_shape.shape.radius = 7.0
	player.add_child(player_shape)
	scene.add_child(player)

	var guests: Array[Node2D] = []
	for x in [20.0, 45.0, 260.0]:
		var guest := preload("res://world/harbor/events/WorldEventResident.gd").new()
		guest.position = Vector2(x, 0)
		scene.add_child(guest)
		guest.set_physics_process(false)
		guests.append(guest)
	await physics_frame

	var first := preload("res://guns/combat/MeleeContact.gd").first_body(player, Vector2.RIGHT, 46.0, 0.35, guests)
	check(first == guests[0], "Punch contact resolves to the first cemetery guest")
	first.set_meta("combat_attacker", player)
	first.take_damage(9, true)
	check(guests[0].health == 71, "Punch damages the first cemetery guest")
	check(guests[1].health == 80, "Second body remains untouched behind first contact")
	var wall := StaticBody2D.new()
	wall.position = Vector2(10, 0)
	var wall_shape := CollisionShape2D.new()
	wall_shape.shape = RectangleShape2D.new()
	wall_shape.shape.size = Vector2(3, 30)
	wall.add_child(wall_shape)
	scene.add_child(wall)
	await physics_frame
	check(preload("res://guns/combat/MeleeContact.gd").first_body(player, Vector2.RIGHT, 46.0, 0.35, guests) == null, "Wall blocks punch contact")
	wall.queue_free()
	await physics_frame
	check(guests[0].panic_timer >= 9.0 and not guests[0].danger_response.threats.is_empty(), "Struck guest gets a real escape destination")
	check(guests[1].panic_timer >= 9.0 and not guests[1].danger_response.threats.is_empty(), "Nearby funeral guest reacts to the assault")
	check(guests[2].panic_timer == 0.0, "Distant guest is not alerted outside the local group")

	var before := guests[0].global_position
	for frame in 12:
		guests[0]._physics_process(1.0 / 60.0)
		guests[1]._physics_process(1.0 / 60.0)
		await physics_frame
	if guests[0].global_position.distance_to(before) <= 2.0:
		print("FLEE_DIAGNOSTIC velocity=%s destination=%s threats=%s panic=%.2f" % [guests[0].velocity, guests[0].danger_response.destination, guests[0].danger_response.threats, guests[0].panic_timer])
	check(guests[0].global_position.distance_to(before) > 2.0, "Threatened guest physically flees")

	scene.queue_free()
	await process_frame

	var world := Node2D.new()
	root.add_child(world)
	var cemetery := CemeteryFixture.new()
	cemetery.name = "Cemetery"
	cemetery.position = Vector2(400, 500)
	world.add_child(cemetery)
	var events := preload("res://world/harbor/events/HarborWorldEvents.gd").new()
	events.name = "WorldEvents"
	world.add_child(events)
	events.set_process(false)
	check(events.start_funeral(), "Funeral event starts")
	for frame in 10:
		if events.guests.size() == 5: break
		await process_frame
	check(events.guests.size() == 5, "Five funeral guests spawn through the real event routine")
	var clear_formation := events.guests.size() == 5
	for i in events.guests.size():
		for j in range(i + 1, events.guests.size()):
			clear_formation = clear_formation and events.guests[i].global_position.distance_to(events.guests[j].global_position) >= 24.0
	check(clear_formation, "Funeral formation starts without overlapping bodies")
	world.queue_free()
	await process_frame

	var combat_scene := Node2D.new()
	root.add_child(combat_scene)
	current_scene = combat_scene
	var real_player := preload("res://characters/Player.gd").new()
	var camera := Camera2D.new()
	camera.name = "Camera"
	real_player.add_child(camera)
	combat_scene.add_child(real_player)
	real_player.set_physics_process(false)
	real_player.active_weapon_id = "fists"
	var punch_targets: Array[Target] = []
	for x in [20.0, 45.0]:
		var target := Target.new()
		target.position = Vector2(x, 0)
		target.collision_layer = 4
		var shape := CollisionShape2D.new()
		shape.shape = CircleShape2D.new()
		shape.shape.radius = 7.0
		target.add_child(shape)
		target.add_to_group("damageable")
		combat_scene.add_child(target)
		punch_targets.append(target)
	await physics_frame
	real_player._perform_melee_attack(Vector2.RIGHT, WeaponCatalog.get_weapon("fists"))
	check(punch_targets[0].health == 71 and punch_targets[1].health == 80, "Real player punch damages only the first physical body")
	combat_scene.queue_free()
	await process_frame
	print("CEMETERY_GUEST_ASSAULT failures=%d" % failures)
	quit(0 if failures == 0 else 1)
