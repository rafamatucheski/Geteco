extends SceneTree

const NAV := preload("res://emergency/ResponderNavigation.gd")
var failures := 0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok: failures += 1

func block(at: Vector2, size: Vector2, layer: int = 1) -> StaticBody2D:
	var obstacle := StaticBody2D.new()
	obstacle.position = at
	obstacle.collision_layer = layer
	var hull := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = size
	hull.shape = shape
	obstacle.add_child(hull)
	root.add_child(obstacle)
	return obstacle

func run() -> void:
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
	var nav := NAV.new()
	var post := block(Vector2(40, 4), Vector2(2, 2))
	await physics_frame
	await physics_frame
	check(not nav.clear_segment(actor, Vector2.ZERO, Vector2(80, 0)), "Thin post between the former rays is detected")
	post.position = Vector2(40, 12)
	await physics_frame
	await physics_frame
	check(not nav.clear_segment(actor, Vector2.ZERO, Vector2(80, 0)), "Full eleven-pixel body clearance is respected")
	post.queue_free()
	await physics_frame
	var wall := block(Vector2(75, 0), Vector2(28, 240), 2)
	await physics_frame
	await physics_frame
	nav.search_budget = 4
	var goal := Vector2(180, 0)
	var max_detour := 0.0
	for frame in 900:
		await physics_frame
		actor.velocity = nav.movement(actor, goal, 100.0, 1.0 / 60.0)
		actor.move_and_slide()
		max_detour = maxf(max_detour, absf(actor.position.y))
		if actor.position.distance_to(goal) < 2.0: break
	check(max_detour > 130.0, "NPC goes around a long parked vehicle")
	check(actor.position.distance_to(goal) < 2.0, "Small per-frame search budget still reaches the destination")
	wall.queue_free()
	actor.position = Vector2.ZERO
	nav = NAV.new()
	await physics_frame
	await physics_frame
	check(nav.movement(actor, goal, 100.0, 0.1).x > 0.0, "Clear route moves directly")
	var new_block := block(Vector2(60, 0), Vector2(24, 40))
	await physics_frame
	await physics_frame
	max_detour = 0.0
	for frame in 360:
		await physics_frame
		actor.velocity = nav.movement(actor, goal, 100.0, 1.0 / 60.0)
		actor.move_and_slide()
		max_detour = maxf(max_detour, absf(actor.position.y))
		if actor.position.distance_to(goal) < 2.0: break
	check(max_detour > 30.0 and actor.position.distance_to(goal) < 2.0, "New obstacle invalidates direct route and NPC resumes after detour")
	new_block.queue_free()
	actor.queue_free()
	quit(1 if failures else 0)
