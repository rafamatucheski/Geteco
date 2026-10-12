extends SceneTree
class State extends RefCounted:
	var place_id := ""
	var allowed := true
	func weapons_allowed() -> bool: return allowed
	func owns_weapon(_id: String) -> bool: return false
class Target extends CharacterBody3D:
	var health := 100.0
	func receive_damage(amount: float, _source: Node = null) -> void: health -= amount
class World extends Node3D:
	var driving := {"occupied": false, "car": null}
	var gameplay
	var player
class Session extends RefCounted:
	var world
	func position_clear(_point: Vector3) -> bool: return true
class Car extends CharacterBody3D:
	var half_width := 1.0
	var opened := false
	var health := 100.0
	var traffic := true
	func set_external_driver(_value: bool) -> void: pass
	func animate_driver_door(_side: int, value: bool) -> void: opened = value

var failures: Array[String] = []
func _initialize() -> void: run.call_deferred()
func check(value: bool, label: String) -> void:
	print("PASS " if value else "FAIL ", label)
	if not value: failures.append(label)
func shape(node: CollisionObject3D, size: Vector3, point: Vector3) -> void:
	var collider := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	collider.shape = box
	collider.position = point
	node.add_child(collider)
func run() -> void:
	var world := World.new()
	root.add_child(world)
	current_scene = world
	var target := Target.new()
	target.collision_layer = 2
	shape(target, Vector3(1, 2, 1), Vector3.UP)
	world.add_child(target)
	target.position.z = -8
	var state := State.new()
	var game := preload("res://gameplay/Gameplay.gd").new()
	game.configure(world, target, null, state)
	world.add_child(game)
	game.set_physics_process(false)
	var cobra := preload("res://gameplay/CobraAgent.gd").new()
	cobra.configure(game)
	world.add_child(cobra)
	cobra.set_physics_process(false)
	cobra.visual.update_pose(1.0, true, false, 0, 0)
	await physics_frame
	await physics_frame
	cobra._shoot(target)
	check(game.health == 100 and game._police_rounds.size() == 1, "Cobra shot has flight time, no instant damage")
	check(game._police_rounds[0].point.is_equal_approx(cobra.visual.muzzle_position()), "Cobra bullet begins at visible barrel")
	var pistol: Dictionary = cobra.CATALOG.get_weapon("pistol")
	check(is_equal_approx(game._police_rounds[0].speed, float(pistol.projectile_speed) / 16.0)
		and is_equal_approx(game._police_rounds[0].range, float(pistol.max_range) / 16.0), "Cobra uses player catalog bullet speed and range")
	var token: Dictionary = game._police_rounds[0].visual
	var tracer_material: StandardMaterial3D = game.effects._tracers[token.index].mesh.material
	check(tracer_material.emission.is_equal_approx(pistol.tracer_color), "Cobra tracer uses player weapon color")
	game._police_rounds[0].direction = (game._police_rounds[0].point as Vector3).direction_to(target.position + Vector3.UP)
	game._advance_police_rounds(.01)
	check(game.health == 100, "Cobra bullet cannot hit before reaching target")
	for index in 60: game._advance_police_rounds(.01)
	check(game.health < 100 and game._police_rounds.is_empty(), "Shared swept collision hits target once and consumes bullet")
	var health: float = game.health
	for index in 20: game._advance_police_rounds(.01)
	check(game.health == health, "Spent Cobra round does not hit twice")
	cobra.magazine = 0
	cobra._shoot(target)
	check(cobra.reload_timer > 0 and game._police_rounds.is_empty(), "Empty Cobra magazine starts reload instead of firing")
	cobra.configure(game, 1)
	cobra.reload_timer = 0
	cobra.magazine = 6
	cobra._shoot(target)
	check(game._police_rounds.size() == 8, "Shotgun launches all eight catalog pellets")
	for index in 100: game._advance_police_rounds(.01)
	state.allowed = false
	cobra._shoot(target)
	check(game._police_rounds.is_empty(), "Weapon restriction blocks Cobra firing")
	state.allowed = true
	var wall := StaticBody3D.new()
	wall.collision_layer = 1
	shape(wall, Vector3(4, 3, .25), Vector3(0, 1, -3))
	world.add_child(wall)
	await physics_frame
	await physics_frame
	cobra.configure(game)
	cobra.magazine = 12
	game.health = 100
	cobra._shoot(target)
	for index in 80: game._advance_police_rounds(.01)
	check(game.health == 100, "Wall intercepts Cobra rounds")
	wall.free()
	var car := Car.new()
	world.add_child(car)
	var occupant := preload("res://gameplay/CobraModel.gd").new()
	occupant.seated = true
	occupant.seat_armed = true
	car.add_child(occupant)
	occupant.position.x = .4
	occupant.aim_from_seat(target.position, 1.0)
	preload("res://gameplay/CobraGunfire.gd").fire(game, car, occupant, target, "pistol")
	check(game._police_rounds.size() == 1 and game._police_rounds[0].rid == car.get_rid(), "Seated gunfire uses same flight and excludes own vehicle")
	check(game._police_rounds[0].point.is_equal_approx(occupant.muzzle_position()), "Seated shot begins at occupant weapon")
	for index in 100: game._advance_police_rounds(.01)
	var floor_body := StaticBody3D.new()
	car.position.x = 5.0
	shape(floor_body, Vector3(20, .2, 20), Vector3(0, -.1, 0))
	world.add_child(floor_body)
	var guard := preload("res://gameplay/urban_v1/CobraPatrolGuard.gd").new()
	guard.configure(game)
	world.add_child(guard)
	guard.set_physics_process(false)
	var before: Transform3D = occupant.global_transform
	guard.begin_exit(car, occupant, Vector3(6.8, .1, 0), 1)
	check(guard.visual == occupant and occupant.global_transform.is_equal_approx(before), "Exit preserves occupant identity and visible position")
	check(guard.exiting and car.opened, "Door opens before physical exit")
	await physics_frame
	await physics_frame
	var previous := guard.global_position
	var max_step := 0.0
	for index in 160:
		guard._physics_process(1.0 / 60.0)
		max_step = maxf(max_step, guard.global_position.distance_to(previous))
		previous = guard.global_position
		await physics_frame
		if not guard.exiting: break
	print("EXIT_DIAGNOSTIC position=", guard.global_position, " max_step=", max_step)
	check(not guard.exiting and guard.global_position.x > 6.65 and max_step < .08, "Occupant walks out continuously without teleport")
	check(not car.opened and occupant.body.sit_amount == 0.0 and not guard.get_collision_exceptions().has(car), "Exit closes door, stands up and restores car collision")
	guard.free()
	var patrol := preload("res://gameplay/urban_v1/CobraPatrol.gd").new()
	var session := Session.new()
	session.world = world
	world.gameplay = game
	world.player = target
	patrol.session = session
	patrol.car = car
	for side in [-1, 1]:
		var passenger := preload("res://gameplay/CobraModel.gd").new()
		passenger.seated = true
		passenger.seat_armed = true
		passenger.position.x = float(side) * .4
		car.add_child(passenger)
		patrol.passengers.append(passenger)
	patrol._deploy(1)
	check(patrol.crew.size() == 2 and patrol.crew[0]._side == -1 and patrol.crew[1]._side == 1,
		"Real patrol deployment uses each actual seat side, not crew index")
	check(patrol.crew[0]._landing.x < car.global_position.x and patrol.crew[1]._landing.x > car.global_position.x,
		"Occupants leave outward through separate doors without crossing cabin")
	for actor in patrol.crew: actor.free()
	patrol.free()
	print("COBRA_BALLISTICS failures=", failures)
	world.free()
	quit(0 if failures.is_empty() else 1)
