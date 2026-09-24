extends SceneTree
class State extends RefCounted:
	var allowed := true
	func weapons_allowed() -> bool: return allowed
class Target extends CharacterBody3D:
	var health := 100.0
	var hits := 0
	func receive_damage(amount: float, _source: Node = null) -> void:
		health -= amount
		hits += 1
class World extends Node3D:
	var driving := {"occupied": false, "car": null}
var checks := 0
var failures: Array[String] = []
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)
	print("PASS " if ok else "FAIL ", label)
func body(node: CollisionObject3D, size: Vector3, position: Vector3) -> void:
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position = position
	node.add_child(shape)
func run() -> void:
	var world := World.new()
	root.add_child(world)
	current_scene = world
	var target := Target.new()
	body(target, Vector3(1, 2, 1), Vector3.UP)
	target.collision_layer = 2
	world.add_child(target)
	target.position = Vector3(0, 0, -8)
	var state := State.new()
	var game := preload("res://gameplay/Gameplay.gd").new()
	game.configure(world, target, null, state)
	world.add_child(game)
	game.set_physics_process(false)
	var officer := preload("res://gameplay/PoliceAgent.gd").new()
	officer.controller = game
	world.add_child(officer)
	officer.set_physics_process(false)
	officer.visual.update_pose(1.0, true, false, 0.0, 0.0)
	for i in 2: await physics_frame
	game._rng.seed = 7
	game.police_shoot(officer, 6)
	check(game.health == 100 and game._police_rounds.size() == 1, "shot starts at muzzle without immediate damage")
	check(game._police_rounds[0].point.is_equal_approx(officer.visual.muzzle_position()), "flight origin equals visible muzzle")
	# Straight deterministic flight isolates contact timing from random spread.
	game._police_rounds[0].direction = (game._police_rounds[0].point as Vector3).direction_to(target.position + Vector3.UP)
	game._advance_police_rounds(0.02)
	check(game.health == 100, "no damage before flight reaches target")
	for i in 20: game._advance_police_rounds(0.01)
	check(game.health == 94 and game._police_rounds.is_empty(), "one swept contact applies exactly one damage")
	for i in 20: game._advance_police_rounds(0.01)
	check(game.health == 94, "spent round cannot damage twice")
	game.health = 100
	game.police_shoot(officer, 6)
	target.position.x = 4
	for i in 2: await physics_frame
	for i in 70: game._advance_police_rounds(0.01)
	check(game.health == 100 and game._police_rounds.is_empty(), "moving target can evade; range expires")
	target.position.x = 0
	for i in 2: await physics_frame
	for scenario in ["wall", "corner", "car"]:
		game.police_shoot(officer, 6)
		game._police_rounds[0].direction = Vector3.FORWARD
		var obstacle := StaticBody3D.new()
		obstacle.collision_layer = 4 if scenario == "car" else 1
		body(obstacle, Vector3(2, 2, 0.05), Vector3(0, 1, -4))
		if scenario == "corner": body(obstacle, Vector3(0.05, 2, 2), Vector3(1, 1, -3))
		world.add_child(obstacle)
		for i in 2: await physics_frame
		for i in 20: game._advance_police_rounds(0.01)
		check(game.health == 100 and game._police_rounds.is_empty(), scenario + " interrupts swept flight")
		obstacle.free()
		for i in 2: await physics_frame
	var car := Target.new()
	car.collision_layer = 4
	body(car, Vector3(2, 2, 4), Vector3.UP)
	world.add_child(car)
	car.position = target.position
	world.driving = {"occupied": true, "car": car}
	target.position = Vector3(30, 0, 0)
	for i in 2: await physics_frame
	game.police_shoot(officer, 8)
	for i in 30: game._advance_police_rounds(0.01)
	check(car.hits == 1 and game.health == 100, "occupied vehicle receives contact, not duplicate driver damage")
	car.set_meta("invulnerable", true)
	game.police_shoot(officer, 8)
	for i in 30: game._advance_police_rounds(0.01)
	check(car.hits == 1, "protected body ignores police projectile damage")
	state.allowed = false
	game.police_shoot(officer, 6)
	check(game._police_rounds.is_empty(), "garage safety blocks firing")
	state.allowed = true
	world.driving.occupied = false
	car.free()
	target.position = Vector3(0, 0, -8)
	var thin_wall := StaticBody3D.new()
	thin_wall.collision_layer = 1
	var bridge_mid := (Vector3.UP * 1.1).lerp(officer.visual.muzzle_position(), 0.6)
	body(thin_wall, Vector3(0.012, 0.2, 0.02), bridge_mid)
	world.add_child(thin_wall)
	for i in 2: await physics_frame
	check(game.police_can_see(officer), "eye line clear beside thin muzzle obstruction")
	game.police_shoot(officer, 6)
	check(game._police_rounds.size() == 1 and not game._police_rounds[0].blocked.is_empty(), "muzzle beyond thin wall cannot bypass its surface")
	game._advance_police_rounds(0.02)
	check(game._police_rounds.is_empty() and game.health == 100, "muzzle obstruction consumes round without target damage")
	thin_wall.free()
	for i in 2: await physics_frame
	game.stars = 2
	game.last_known_valid = true
	game.last_known = target.position
	officer.last_known = target.position
	officer.sees_player = true
	officer.sensor = 1.0
	officer.repath = 1.0
	officer.reload_timer = 0.01
	officer.magazine = 0
	officer._physics_process(0.02)
	check(officer.reload_timer == 0 and officer.magazine == 12 and officer.velocity.z < -3.0,
		"reload ends and real pursuit resumes toward visible target")
	for profile in 10:
		var model := preload("res://gameplay/PoliceModel.gd").new()
		model.appearance_index = profile
		model.tier = profile % 5
		world.add_child(model)
		model.equip("pistol" if profile % 3 == 0 else ("smg" if profile % 3 == 1 else "m4a1"))
		for heading in 8:
			model.rotation.y = heading * TAU / 8
			model.update_pose(1.0, true, false, 0, 0)
			var palm: Vector3 = model.to_local(model.right_lower_arm.to_global(Vector3(0, -0.20, 0)))
			var grip: Vector3 = model.weapon.transform * model.POSE_DATA.GRIPS[model.weapon_id]
			check(palm.z < -0.05 and palm.distance_to(grip) < 0.001 and (-model.weapon.basis.z).dot(Vector3.FORWARD) > 0.99,
				"profile %d heading %d: hands forward, grip attached, barrel forward" % [profile, heading])
		model.update_pose(1, true, true, 0.3, 0)
		var reload_hand: Vector3 = model.left_lower_arm.global_position
		model.update_pose(1, true, false, 0, 0)
		check(reload_hand.distance_to(model.left_lower_arm.global_position) > 0.01, "profile %d reload releases support and resumes aim" % profile)
		model.free()
	officer.visual.attack()
	officer.receive_damage(1000.0)
	check(officer.dead and not officer.visual.muzzle_flash_3d.visible, "death cannot leave a frozen muzzle flash")
	print("POLICE_BALLISTICS checks=", checks, " failures=", failures)
	world.free()
	quit(0 if failures.is_empty() else 1)
