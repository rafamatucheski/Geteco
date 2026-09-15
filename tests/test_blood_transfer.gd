extends SceneTree
const SYSTEM := preload("res://world/shared/combat/BloodTransferSystem.gd")
const BLOOD := preload("res://world/shared/combat/GroundBlood.gd")
var failures: Array[String] = []
var checks := 0
var world: Node2D
var system: Node2D

func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		push_error(message)

func actor_at(point: Vector2, group: String) -> Node2D:
	var actor := Node2D.new()
	actor.position = point
	actor.add_to_group(group)
	var collision := CollisionShape2D.new()
	collision.name = "Collision"
	var shape := RectangleShape2D.new()
	shape.size = Vector2(60, 24)
	collision.shape = shape
	actor.add_child(collision)
	world.add_child(actor)
	return actor

func stain_at(point: Vector2, radius := 20.0) -> Node2D:
	var stain := BLOOD.new()
	stain.radius = radius
	world.add_child(stain)
	stain.global_position = point
	stain.age = 3.0
	stain.set_process(false)
	return stain

func drive(actor: Node2D, distance: float, step := 2.0) -> void:
	var track: Dictionary = system.tracks[actor.get_instance_id()]
	for index in ceili(distance / step):
		actor.position.x += minf(step, distance - index * step)
		system.sample_actor(actor, track)

func run() -> void:
	world = Node2D.new()
	root.add_child(world)
	current_scene = world
	system = SYSTEM.ensure(world)
	system.set_physics_process(false)
	var car := actor_at(Vector2(60, 80), "vehicle")
	stain_at(Vector2(120, 80), 27)
	var bike := actor_at(Vector2(60, 180), "vehicle")
	bike.add_to_group("motorcycle")
	stain_at(Vector2(120, 180), 20)
	var walker := actor_at(Vector2(60, 280), "pedestrian")
	stain_at(Vector2(120, 283), 20)
	var player := actor_at(Vector2(60, 380), "player")
	stain_at(Vector2(120, 383), 20)
	var clean := actor_at(Vector2(60, 460), "vehicle")
	system._refresh_contacts()
	drive(clean, 300)
	check(system.marks.is_empty(), "Dry pavement never produces blood")
	drive(car, 310)
	var tire_marks: Array = system.marks.duplicate()
	check(tire_marks.size() > 70, "Car produces two wheel tracks after crossing an existing pool")
	var upper := false
	var lower := false
	var wheels_only := true
	for mark in tire_marks:
		upper = upper or mark.position.y < 80
		lower = lower or mark.position.y > 80
		wheels_only = wheels_only and absf(mark.position.y - 80) > 8.0
	check(wheels_only, "Tire marks stay under wheels, never the vehicle centre")
	check(upper and lower, "Both contaminated wheels leave distinct tracks")
	check(tire_marks[-1].strength < tire_marks[15].strength * 0.25, "Residue visibly weakens with distance")
	var previous_count: int = system.marks.size()
	drive(car, 200)
	check(system.marks.size() == previous_count, "Tires stop marking once their distance budget is exhausted")
	previous_count = system.marks.size()
	drive(bike, 310)
	var bike_marks: Array = system.marks.slice(previous_count)
	check(bike_marks.size() > 30 and bike_marks.all(func(m): return is_equal_approx(m.position.y, 180.0)), "Motorcycle leaves a single narrow wheel path")
	previous_count = system.marks.size()
	drive(walker, 210)
	var footprints: Array = system.marks.slice(previous_count)
	check(footprints.size() >= 3 and footprints.size() <= 8, "Pedestrian leaves a short, bounded trail after contact")
	var alternating := true
	for index in range(1, footprints.size()):
		var gap: float = footprints[index].position.x - footprints[index - 1].position.x
		alternating = alternating and (gap >= 39.9 or footprints[index].position.y != footprints[index - 1].position.y)
	check(alternating, "Footprints alternate left and right feet")
	drive(player, 210)
	check(system.marks.any(func(m): return not m.tire and m.position.y > 370), "Player footsteps use the same transfer")
	var washed := actor_at(Vector2(110, 80), "vehicle")
	system._refresh_contacts()
	drive(washed, 55)
	check(system.tracks[washed.get_instance_id()].residue[0] > 0, "Wheel contamination is picked up before washing")
	SYSTEM.wash(washed)
	system._refresh_contacts()
	previous_count = system.marks.size()
	drive(washed, 100)
	check(system.marks.size() == previous_count, "Water washing clears residue without erasing existing ground marks")
	var one_wheel := actor_at(Vector2(60, 560), "vehicle")
	stain_at(Vector2(120, 569.36), 6)
	# Exercise the spatial lookup with distant stains and a pool across a cell boundary.
	for index in 12: stain_at(Vector2(2000 + index * 160, 800))
	system._refresh_contacts()
	previous_count = system.marks.size()
	drive(one_wheel, 200, 12)
	var side_marks: Array = system.marks.slice(previous_count)
	check(not side_marks.is_empty() and side_marks.all(func(m): return m.position.y > 560), "Only the wheel touching a small stain is contaminated, including fast crossings")
	var teleport_count: int = system.marks.size()
	one_wheel.position += Vector2(500, 0)
	system.sample_actor(one_wheel, system.tracks[one_wheel.get_instance_id()])
	check(system.marks.size() == teleport_count and system.tracks[one_wheel.get_instance_id()].residue == [0.0, 0.0], "Teleports do not draw a connecting stripe or carry stale residue")
	var expired := stain_at(Vector2(900, 900))
	system._refresh_contacts()
	expired.free()
	check(not system._in_blood(Vector2(900, 900)), "An expired pool is safe to query before the next spatial refresh")
	if OS.get_cmdline_user_args().has("--capture"):
		root.size = Vector2i(720, 620)
		RenderingServer.set_default_clear_color(Color("757777"))
		var camera := Camera2D.new()
		camera.position = Vector2(360, 310)
		world.add_child(camera)
		system.queue_redraw()
		for frame in 4: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("D:/geteco/artifacts/life-refinement-0911/blood-transfer.png")
	system._clock += SYSTEM.MARK_LIFETIME + 1.0
	system._physics_process(0)
	check(system.marks.is_empty(), "Old ground marks expire instead of accumulating forever")
	print("BLOOD_TRANSFER checks=", checks, " failures=", failures)
	world.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
