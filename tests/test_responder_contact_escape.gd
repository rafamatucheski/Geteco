extends SceneTree

const NAV := preload("res://ResponderNavigation.gd")
var failures := 0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok: failures += 1

func block(at: Vector2, size: Vector2) -> StaticBody2D:
	var obstacle := StaticBody2D.new()
	obstacle.position = at
	obstacle.collision_layer = 2
	var hull := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = size
	hull.shape = shape
	obstacle.add_child(hull)
	root.add_child(obstacle)
	return obstacle

func run() -> void:
	create_timer(20).timeout.connect(func(): quit(2))
	var actor := CharacterBody2D.new()
	actor.collision_layer = 4
	actor.collision_mask = 7
	actor.motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	var hull := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 11.0
	hull.shape = circle
	actor.add_child(hull)
	root.add_child(actor)
	var wall := block(Vector2.ZERO, Vector2(40, 200))
	actor.position = Vector2(31.02, 0)
	await physics_frame
	await physics_frame
	var nav := NAV.new()
	check(nav.movement(actor, Vector2(100, 0), 100.0, 1.0 / 60.0).x > 0.0, "Responder touching vehicle safety margin can step away")
	check(not nav.clear_segment(actor, actor.position, Vector2(-100, 0)), "Touching a vehicle does not permit traversing it")
	var max_step := 0.0
	var min_x := actor.position.x
	for frame in 80:
		await physics_frame
		var before := actor.position
		actor.velocity = nav.movement(actor, Vector2(100, 0), 100.0, 1.0 / 60.0)
		actor.move_and_slide()
		max_step = maxf(max_step, before.distance_to(actor.position))
		min_x = minf(min_x, actor.position.x)
	check(actor.position.x > 90.0, "Contact recovery resumes physical travel")
	check(max_step <= 100.0 / 60.0 + 0.001 and min_x >= 31.0, "Recovery stays outside wall and within speed budget")
	actor.position = Vector2(30.96, 0)
	await physics_frame
	await physics_frame
	nav = NAV.new()
	check(nav.clear_segment(actor, actor.position, Vector2(100, 0)), "Shallow geometric contact can recover outward")
	check(not nav.clear_segment(actor, actor.position, Vector2(-100, 0)), "Shallow geometric contact cannot recover through the vehicle")
	actor.position = Vector2(20, 0)
	await physics_frame
	await physics_frame
	check(not nav.clear_segment(actor, actor.position, Vector2(-100, 0)), "Deep penetration never bypasses obstruction checks")
	wall.queue_free()
	var workzone := block(Vector2(200, 0), Vector2(120, 120))
	actor.add_collision_exception_with(workzone)
	var patient := Node2D.new()
	patient.position = Vector2(200, 0)
	root.add_child(patient)
	await physics_frame
	await physics_frame
	nav = NAV.new()
	var station := nav.service_position(actor, patient, 32.0, 0.1)
	check(is_equal_approx(station.distance_to(patient.position), 32.0), "Crew ignores its own work zone when selecting a patient station")
	actor.remove_collision_exception_with(workzone)
	workzone.queue_free()
	await physics_frame
	var ambulance := block(Vector2(200, 0.55), Vector2(100, 34))
	circle.radius = 13.0
	actor.position = Vector2(130, 30)
	patient.position = Vector2(239, 30)
	await physics_frame
	await physics_frame
	nav = NAV.new()
	station = nav.service_position(actor, patient, 24.0, 0.1)
	check(station != patient.position and nav.clear_segment(actor, station, station), "Stretcher station fits its full thirteen-pixel body beside an ambulance")
	ambulance.queue_free()
	patient.queue_free()
	actor.queue_free()
	print("RESPONDER_CONTACT_ESCAPE failures=", failures)
	quit(1 if failures else 0)
