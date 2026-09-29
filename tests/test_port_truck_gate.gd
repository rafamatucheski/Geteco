extends SceneTree

## Dirigindo o caminhão de carga do porto, a cancela abre sozinha e a portaria não dá alarme.
var world
var failures: Array[String] = []

func _initialize() -> void: run.call_deferred()

func check(ok: bool, message: String) -> void:
	if ok: return
	failures.append(message)
	push_error(message)

func run() -> void:
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	root.add_child(world)
	for _frame in 500:
		await physics_frame
		if world.session != null and world.session.ready_for_play: break
	if world.session == null or not world.session.ready_for_play:
		check(false,"Main V2 starts")
		quit(1)
		return
	var session = world.session
	check(world.production.no_save,"Test isolates the personal save")
	session.weather.time_of_day = .4
	var security = session.urban_operations.security
	var gate := Vector3(3310.0 / 16.0,0.0,3380.0 / 16.0)
	# O caminhão do porto existe na cena; leva o jogador até ele e embarca.
	var logistics = session.urban_operations.cargo_handling
	var truck: CharacterBody3D = null
	for _frame in 600:
		await physics_frame
		for state in logistics.work_trucks:
			if is_instance_valid(state.truck) and state.truck.visible:
				truck = state.truck
				break
		if truck != null: break
	check(truck != null,"há um caminhão de carga do porto na cena")
	if truck == null:
		quit(1)
		return
	# Parado, para a porta ser alcançável; o jogador fica junto da porta do motorista.
	truck.traffic = false
	truck.speed = 0.0
	truck.velocity = Vector3.ZERO
	truck.brake_input = true
	world.production.region.set_focus(truck.global_position)
	for _frame in 60: await physics_frame
	var sides: Array = truck.boarding_sides() if truck.has_method("boarding_sides") else [-1,1]
	var boarded := false
	for _frame in 400:
		if not world.driving.occupied:
			var door: Vector3 = truck.driver_door_anchor(int(sides[0])) if truck.has_method("driver_door_anchor") else truck.global_position
			world.player.teleport(door + Vector3.UP * .05)
			truck.speed = 0.0
			world.driving.interact(true)
		await physics_frame
		if world.driving.occupied and world.driving.car == truck and truck.controlled: boarded = true; break
	check(boarded,"o jogador embarca no caminhão do porto")
	if not boarded:
		quit(1)
		return
	check(truck.get_meta("port_work_vehicle",false),"é o caminhão de trabalho do porto")
	# Fora do pátio, longe da cancela: ela fica fechada.
	truck.global_position = gate + Vector3(0,0.1,-40)
	truck.velocity = Vector3.ZERO
	for _frame in 90: await physics_frame
	check(not security.gate_open,"longe da cancela ela fica fechada")
	# A 10 m da cancela ela abre sozinha, sem propina.
	truck.global_position = gate + Vector3(0,0.1,-10)
	truck.velocity = Vector3.ZERO
	for _frame in 90: await physics_frame
	check(security.gate_open,"a cancela abre sozinha para o caminhão do porto")
	check(not security.authorized_entry and not security.authorized_visit,"ainda não entrou: sem autorização por propina")
	# Entra no pátio: sem alarme e sem crime.
	truck.global_position = gate + Vector3(0,0.1,14)
	truck.velocity = Vector3.ZERO
	for _frame in 120: await physics_frame
	check(not security.alerted,"entrar a serviço não dispara alarme de invasão")
	check(world.gameplay.stars == 0,"nenhuma estrela por entrar com o caminhão do porto")
	print("PORT_TRUCK_GATE failures=",failures.size())
	world.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
