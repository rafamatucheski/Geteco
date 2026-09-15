extends SceneTree

var failures: Array[String] = []
func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok: failures.append(label)
func frames(count: int) -> void:
	for i in count: await physics_frame

func run() -> void:
	create_timer(45).timeout.connect(func(): quit(2))
	seed(904)
	var scene := Node2D.new()
	root.add_child(scene)
	current_scene = scene
	root.get_node("WantedManager").set_process(false)
	var officer = load("res://police/PoliceOfficer.tscn").instantiate()
	scene.add_child(officer)
	officer.set_physics_process(false)
	officer.position = Vector2(100, 300)
	var person = load("res://world/shared/pedestrians/AuthoredSidewalkPedestrian.gd").new()
	person.configure_authored_route(PackedVector2Array([Vector2(240, 380), Vector2(240, 900)]), "test")
	scene.add_child(person)
	person.is_gangster = false
	var distant = load("res://world/shared/pedestrians/AuthoredSidewalkPedestrian.gd").new()
	distant.configure_authored_route(PackedVector2Array([Vector2(2200, 1600), Vector2(2500, 1600)]), "far")
	scene.add_child(distant)
	distant.is_gangster = false
	var resident = load("res://world/mountain_pass/WinterResident.gd").new()
	resident.position = Vector2(180, 200)
	scene.add_child(resident)
	resident.speech.text = "routine dialogue"
	var sheltered = load("res://world/shared/pedestrians/AuthoredSidewalkPedestrian.gd").new()
	sheltered.configure_authored_route(PackedVector2Array([Vector2(500, -100), Vector2(550, -100)]), "cover")
	scene.add_child(sheltered)
	sheltered.is_gangster = false
	var cover := StaticBody2D.new()
	cover.position = Vector2(300, 100)
	cover.collision_layer = 1
	var cover_shape := CollisionShape2D.new()
	var cover_box := RectangleShape2D.new()
	cover_box.size = Vector2(100, 100)
	cover_shape.shape = cover_box
	cover.add_child(cover_shape)
	scene.add_child(cover)
	await frames(15)
	check(not person.is_scared, "Police presence alone does not scare civilians")
	person._window_shop_pause = 10.0
	var initial: Vector2 = person.global_position
	officer._shoot_at_target(Vector2(900, 300))
	await frames(4)
	check(person.is_scared, "Actual police bullet triggers civilian fear")
	check(resident.panic_timer > 0.0 and resident.speech.text.is_empty(), "Named resident interrupts dialogue and responds to gunfire")
	check(person._window_shop_pause == 0.0, "Gunfire interrupts window shopping")
	check(not distant.is_scared, "Distant civilian continues routine")
	check(not sheltered.is_scared, "Distant civilian behind cover keeps routine")
	await frames(100)
	check(person.global_position.distance_to(officer.global_position) > initial.distance_to(officer.global_position) + 50, "Civilian physically runs away from shooter")
	check(person.global_position.y > initial.y + 30, "Civilian leaves firing line rather than crossing it")
	person.panic_timer = 0.2
	# O segundo tiro precisa continuar perto de quem já correu para longe.
	officer.global_position = person.global_position - Vector2(140, 80)
	officer._shoot_at_target(officer.global_position + Vector2(800, 0))
	await frames(5)
	check(person.panic_timer > 8.0, "Further shots renew fear instead of expiring mid-fight")
	# Real collision fixture blocks the preferred direction of escape.
	var wall := StaticBody2D.new()
	wall.collision_layer = 1
	wall.position = person.global_position + Vector2(70, 80)
	var shape := CollisionShape2D.new()
	var box := RectangleShape2D.new()
	box.size = Vector2(180, 18)
	shape.shape = box
	wall.add_child(shape)
	scene.add_child(wall)
	await frames(2)
	person.danger_response.replan = 0.0
	await frames(2)
	var route := PhysicsRayQueryParameters2D.create(person.global_position, person.danger_response.destination, 1, [person.get_rid()])
	check(person.get_world_2d().direct_space_state.intersect_ray(route).is_empty(), "Escape destination does not lead through wall")
	await create_timer(13.0).timeout
	check(not person.is_scared, "Civilian resumes routine after sustained quiet")
	check(person.health > 0, "Civilian survived physical escape")
	print("CIVILIAN GUNFIRE failures=", failures)
	quit(0 if failures.is_empty() else 1)
