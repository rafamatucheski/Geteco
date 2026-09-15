extends SceneTree
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
func run() -> void:
	var world := Node2D.new()
	root.add_child(world)
	current_scene = world
	var person = preload("res://AnimatedPedestrian3D.gd").new()
	world.add_child(person)
	person.set_physics_process(false)
	var initial_health: int = person.health
	var bullet = preload("res://Bullet.gd").new()
	world.add_child(bullet)
	bullet.damage = 1
	bullet.direction = Vector2.RIGHT
	bullet._hit(person, person.global_position, Vector2.LEFT)
	check(person.health == initial_health - 1, "bullet applies damage once")
	check(not person.is_dead and not person.is_incapacitated, "light hit preserves survival")
	await physics_frame
	await physics_frame
	check(person.position.x > 0.0, "body recoils in bullet direction")
	var fatal = preload("res://Bullet.gd").new()
	world.add_child(fatal)
	fatal.damage = 1000
	fatal.direction = Vector2.DOWN
	fatal._hit(person, person.global_position, Vector2.UP)
	check(person.is_dead and person.fall_presentation.airborne, "lethal bullet starts directional fall")
	check(not person.has_meta("bullet_impulse"), "hit context does not leak into later falls")
	world.queue_free()
	await process_frame
	print("BULLET BODY REACTION: %d failures" % failures)
	quit(1 if failures else 0)
