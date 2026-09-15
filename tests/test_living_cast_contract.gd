extends SceneTree

const CIVIL := preload("res://prototypes/living_cast/LivingCivil.gd")
const LAB := preload("res://prototypes/living_cast/LivingCastLab.gd")
var failures: Array[String] = []

class Target extends CharacterBody2D:
	var health := 100
	var is_dead := false
	func take_damage(amount: int, _attacker := false) -> void:
		health -= amount

func _init() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)

func run() -> void:
	var scene := Node2D.new()
	root.add_child(scene)
	current_scene = scene
	var camera := Camera2D.new()
	scene.add_child(camera)
	var target := Target.new()
	target.add_to_group("player")
	target.position = Vector2(30, 0)
	scene.add_child(target)
	var actors: Array = []
	for i in 6:
		var actor := CIVIL.new()
		actor.appearance = i
		actor.response = 1 if i == 4 else (2 if i == 5 else 0)
		actor.roam = false
		actor.position = Vector2(0, i * 180)
		scene.add_child(actor)
		actors.append(actor)
		check(actor.viewport.size == Vector2i(96,96), "No default viewport resolution inflation")
		check(actor.left_lower_arm != null and actor.right_lower_leg != null, "Articulated rig %d" % i)
	var fighter = actors[4]
	for frame in 12: await physics_frame
	target.position = fighter.position + Vector2(31,0)
	fighter.take_damage(1, true)
	check(not fighter.is_scared and fighter.combat_target == target, "Brawler retaliates unarmed")
	for frame in 4: await physics_frame
	check(target.health == 100, "Punch damage cannot precede contact window")
	await create_timer(0.45).timeout
	check(target.health == 93 and fighter.punches_landed == 1, "One punch, one timed hit")
	# Solid wall must prevent another melee strike.
	var wall := StaticBody2D.new()
	wall.position = fighter.position + Vector2(15,0)
	wall.collision_layer = 1
	var shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(5,80)
	shape.shape = rectangle
	wall.add_child(shape)
	scene.add_child(wall)
	fighter.base_walk_speed = 0
	await create_timer(1.1).timeout
	check(target.health == 93, "No punches through wall")
	actors[0].take_damage(1, true)
	check(actors[0].is_scared and actors[0].combat_target == null, "Ordinary civil flees, no gun")
	var runner_start: Vector2 = actors[0].position
	await create_timer(0.3).timeout
	check(actors[0].position.distance_to(runner_start) > 1, "Panic physically runs")
	actors[1].take_damage(1000, true)
	check(actors[1].death_animation_started, "Death animation starts")
	check(absf(actors[1].model_root.rotation.x) < 0.5, "No instantaneous final death pose")
	await create_timer(0.8).timeout
	check(actors[1].is_dead and actors[1].model_root.rotation.x > 1.3, "Death settles")
	var gunner = actors[5]
	target.position = gunner.position + Vector2(180,0)
	gunner.combat_target = target
	gunner.gun_cooldown = 0
	await create_timer(0.12).timeout
	check(gunner.shots_fired > 0, "Armed profile uses actual projectile path")
	wall.position = gunner.position + Vector2(90,0)
	for frame in 3: await physics_frame
	var shots_before: int = gunner.shots_fired
	gunner.gun_cooldown = 0
	await create_timer(0.12).timeout
	check(gunner.shots_fired == shots_before, "Armed response respects line of sight")
	for variant in range(1,6):
		var sample = LAB.make_car(variant)
		sample.position = Vector2(2000 + variant * 200, 1500)
		scene.add_child(sample)
		check(sample.body_panels.size() >= 10 and sample.active_archetype_id == sample.SPECS[variant], "Vehicle variant %d complete" % variant)
		sample.queue_free()
	var car = LAB.make_car(0)
	car.position = Vector2(700,0)
	scene.add_child(car)
	var original: PackedVector2Array = car.body_panels[0].polygon.duplicate()
	car._apply_crash_deformation(Vector2.LEFT, 280, car.position + Vector2(35, 0))
	await create_timer(0.3).timeout
	check(car.body_panels[0].polygon != original, "Localized geometry dent")
	check(car.scale == Vector2.ONE and car.position == Vector2(700,0), "Crash does not squash or teleport body")
	for i in 5:
		car._apply_crash_deformation(Vector2.LEFT, 450, car.position + Vector2(35,0))
		await create_timer(0.22).timeout
	for j in original.size():
		check(original[j].distance_to(car.body_panels[0].polygon[j]) <= 7.01, "Bounded repeated deformation")
	car._clear_all_dents()
	check(car.body_panels[0].polygon == original, "Repair restores original panel geometry")
	# Actual driving input into a physical wall must call the same deformation path.
	target.remove_from_group("player")
	var driver = load("res://characters/Player.gd").new()
	driver.position = car.position + Vector2(0, 35)
	var driver_camera := Camera2D.new()
	driver_camera.name = "Camera"
	driver.add_child(driver_camera)
	driver.collision_layer = 4
	driver.collision_mask = 7
	var driver_shape := CollisionShape2D.new()
	var driver_circle := CircleShape2D.new()
	driver_circle.radius = 5
	driver_shape.shape = driver_circle
	driver.add_child(driver_shape)
	scene.add_child(driver)
	var barrier := StaticBody2D.new()
	barrier.position = car.position + Vector2(150,0)
	barrier.collision_layer = 1
	var barrier_shape := CollisionShape2D.new()
	var barrier_rect := RectangleShape2D.new()
	barrier_rect.size = Vector2(20, 150)
	barrier_shape.shape = barrier_rect
	barrier.add_child(barrier_shape)
	scene.add_child(barrier)
	for frame in 12: await physics_frame
	var key := InputEventKey.new()
	key.keycode = KEY_E
	key.physical_keycode = KEY_E
	key.pressed = true
	Input.parse_input_event(key)
	for frame in 4: await physics_frame
	key = key.duplicate()
	key.pressed = false
	Input.parse_input_event(key)
	await create_timer(0.4).timeout
	check(car.is_driven_by_player, "Real Player input boards vehicle")
	# Embarque é animado (~2 s) desde 10/09 e o carro ignora o acelerador até a
	# transição terminar; 0,4 s de espera consumia os 95 quadros de aceleração.
	var board_deadline := Time.get_ticks_msec() + 6000
	while car.has_meta("vehicle_boarding") and Time.get_ticks_msec() < board_deadline:
		await physics_frame
	for frame in 4: await physics_frame
	var dents_before: int = car.collision_animations
	# O carro lê as ações move_* do GameInput (desde 10/09), não ui_up.
	Input.action_press("move_up")
	for frame in 95:
		await physics_frame
		if car.collision_animations > dents_before: break
	Input.action_release("move_up")
	await create_timer(0.3).timeout
	check(car.collision_animations > dents_before, "Physical driven collision triggers deformation")
	check(car.position.x < barrier.position.x, "Car did not pass through barrier")
	print("LIVING_CAST_RESULT failures=%d variants=6 melee_hits=%d shots=%d dents=%d" % [failures.size(), fighter.punches_landed, gunner.shots_fired, car.collision_animations])
	scene.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
