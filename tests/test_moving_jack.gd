extends SceneTree
## Roubo em movimento: carro do trânsito a ~25 km/h, jogador ao lado da porta,
## E (interact) agarra, o carro para, o motorista sai e o jogador assume.
## Também: acima de JACK_MAX_SPEED não agarra. Rodar com --no-save.

var failures: Array[String] = []
var world

func _initialize() -> void: run.call_deferred()

func check(condition: bool, message: String) -> void:
	if condition: return
	failures.append(message)
	push_error(message)

func run() -> void:
	if not "--no-save" in OS.get_cmdline_user_args():
		quit(2)
		return
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	root.add_child(world)
	current_scene = world
	for i in 1200:
		await process_frame
		if world.session != null and world.session.ready_for_play: break
	var controller = world.session.controller
	controller.set_population(0)
	var driving = world.driving
	var car = null
	for offset in [Vector3(20, 0, 0), Vector3(-25, 0, 10), Vector3(0, 0, 30), Vector3(35, 0, -20), Vector3(-40, 0, -30)]:
		var road: Vector3 = controller.nearest_road(world.player.global_position + offset)
		car = controller.spawn_vehicle("union_sedan", road + Vector3.UP * .12, controller.road_yaw(road))
		if car != null: break
	check(car != null, "carro de teste deveria nascer")
	if car == null: return _finish()
	car.traffic = true
	for i in 20: await physics_frame
	for over in [true, false]:
		car.speed = 16.0 if over else 7.0
		var door: Vector3 = car.driver_door_anchor(-1)
		world.player.teleport(door + (door - car.global_position).normalized() * .6)
		await physics_frame
		car.speed = 16.0 if over else 7.0
		var took: bool = driving.interact(true)
		if over:
			check(not took, "a 58 km/h não deveria agarrar")
			continue
		check(took, "a 25 km/h deveria agarrar o carro em movimento")
		for i in 240:
			await physics_frame
			if driving.occupied and driving.car == car and not driving.is_body_transition_active(): break
		check(driving.occupied and driving.car == car, "o jogador deveria terminar ao volante do carro roubado")
		check(absf(car.speed) < 1.0, "o carro deveria ter parado no roubo (speed=%.1f)" % car.speed)
		check(not car.traffic, "o carro roubado deixa de ser trânsito")
	_finish()

func _finish() -> void:
	if failures.is_empty():
		print("PASS test_moving_jack")
		quit(0)
	else:
		print("FAIL test_moving_jack: %d" % failures.size())
		quit(1)
