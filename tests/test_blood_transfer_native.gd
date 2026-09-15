extends SceneTree
const FACTORY := preload("res://world/shared/emergency/ModernTrafficFactory.gd")
var failures: Array[String] = []
func _initialize() -> void: run.call_deferred()
func check(value: bool, message: String) -> void:
	if not value: failures.append(message)
	print("PASS " if value else "FAIL ", message)

func run() -> void:
	var world := Node2D.new()
	root.add_child(world)
	current_scene = world
	var car := load("res://world/shared/traffic/SavedPlayerCar.tscn").instantiate() as Node2D
	car.position = Vector2(80, 100)
	world.add_child(car)
	var bike := FACTORY.spawn_parked_vehicle(world, "BloodyMotorcycle", Vector2(80, 250), 0.0, "bike_urban", 0)
	var person := preload("res://AnimatedPedestrian3D.gd").new()
	person.position = Vector2(80, 400)
	world.add_child(person)
	var medic := load("res://Paramedic.tscn").instantiate() as Node2D
	medic.position = Vector2(80, 550)
	world.add_child(medic)
	var actors: Array[Node2D] = [car, bike, person, medic]
	for actor in actors:
		actor.set_physics_process(false)
		var blood := preload("res://guns/combat/GroundBlood.gd").new()
		blood.radius = 32.0
		world.add_child(blood)
		blood.position = Vector2(165, actor.position.y + 3)
		blood.age = 3.0
		blood.set_process(false)
	for frame in 3: await process_frame
	var system := get_first_node_in_group("blood_transfer_system")
	check(system != null, "Real ground pools automatically install the transfer system")
	check(bike.is_in_group("motorcycle"), "Production motorcycle uses its actual wheel layout")
	for frame in 170:
		for actor in actors: actor.position.x += 2.0
		# Manual movement must advance the production gait as physics normally does.
		person._advance_gait(1.0 / 60.0)
		medic.velocity = Vector2(120, 0)
		medic._animate_danger(1.0 / 60.0)
		await physics_frame
	var counts := [0, 0, 0, 0]
	for mark in system.marks:
		if mark.position.y < 160: counts[0] += 1
		elif mark.position.y < 310: counts[1] += 1
		elif mark.position.y < 460: counts[2] += 1
		else: counts[3] += 1
	check(counts[0] > 50 and counts[1] > 25 and counts[2] >= 3 and counts[2] <= 14, "Production car, motorcycle and pedestrian leave bounded tire tracks and footsteps: %s" % str(counts))
	# At 120 px/s and 10 rad/s each sole lands ~75 px apart; an 85 px
	# residue budget permits two impressions from one contaminated sole.
	check(counts[3] >= 2 and counts[3] <= 8, "Working paramedics also leave a short trail after stepping in blood")
	var count_before: int = system.marks.size()
	for frame in 10: await physics_frame
	check(system.marks.size() == count_before, "Stationary actors do not stamp blood repeatedly")
	if OS.get_cmdline_user_args().has("--capture"):
		root.size = Vector2i(1100, 950)
		RenderingServer.set_default_clear_color(Color("737877"))
		var camera := Camera2D.new()
		camera.position = Vector2(300, 325)
		camera.zoom = Vector2.ONE * 1.2
		world.add_child(camera)
		camera.make_current()
		for frame in 5: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("D:/geteco/artifacts/life-refinement-0911/blood-transfer-native.png")
	print("BLOOD_TRANSFER_NATIVE failures=", failures)
	world.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
