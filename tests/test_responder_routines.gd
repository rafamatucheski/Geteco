extends SceneTree

var failures: Array[String] = []
var scene: Node2D

class Incident extends Node2D:
	var treatments := 0
	var extinguished := false
	func rescue_from_emergency(_ambulance: Node2D) -> void:
		treatments += 1
	func extinguish_fire() -> void:
		extinguished = true

class Witness extends CharacterBody2D:
	var alerts := 0
	func hear_gunfire(_origin: Vector2, _end: Vector2) -> void:
		alerts += 1

class SlowCar extends CharacterBody2D:
	var is_driven_by_player := true

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, label: String) -> void:
	print(("PASS " if value else "FAIL ") + label)
	if not value: failures.append(label)

func wall(point: Vector2, size: Vector2) -> StaticBody2D:
	var body := StaticBody2D.new()
	var shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = size
	shape.shape = rectangle
	body.add_child(shape)
	body.position = point
	scene.add_child(body)
	return body

func _run() -> void:
	seed(9210)
	create_timer(90).timeout.connect(func(): printerr("RESPONDER_ROUTINES TIMEOUT"); quit(2))
	scene = Node2D.new()
	root.add_child(scene)
	current_scene = scene
	root.get_node("WantedManager").set_process(false)
	await physics_frame
	var lane := Path2D.new()
	lane.curve = Curve2D.new()
	lane.curve.add_point(Vector2.ZERO)
	lane.curve.add_point(Vector2(100, 0))
	scene.add_child(lane)
	var probe := CharacterBody2D.new()
	scene.add_child(probe)
	probe.position = Vector2(100, 0)
	var router := preload("res://geodata/roads/EmergencyLaneRouter.gd").new()
	router.destination = Vector2(100, 200)
	router.next_plan_ms = Time.get_ticks_msec() + 10000
	router.legs.append({"path": lane, "start": 0.0, "end": 100.0})
	check(router.guidance(probe, router.destination) == probe.position, "Fim da rota estaciona na rua em vez de circular no waypoint")
	lane.queue_free()
	probe.queue_free()
	# Contorno real: parede entre policial e destino, sem teleporte ou rodopio.
	var officer = load("res://police/PoliceOfficer.tscn").instantiate()
	officer.set_meta("quiet_patrol", true)
	scene.add_child(officer)
	officer.set_physics_process(false)
	officer.position = Vector2(-100, 0)
	var obstacle := wall(Vector2.ZERO, Vector2(40, 130))
	await physics_frame
	for frame in 360:
		officer.velocity = officer._navigate_towards(Vector2(100, 0), 120.0, 1.0 / 60.0)
		officer.move_and_slide()
		await physics_frame
	check(officer.position.distance_to(Vector2(100, 0)) < 8.0, "Policial contorna parede e chega ao destino")
	officer.queue_free()
	obstacle.queue_free()
	await physics_frame
	var wanted := root.get_node("WantedManager")
	wanted.current_stars = 1
	var cruiser = root.get_node("EmergencyPool").get_vehicle("police")
	cruiser.set_physics_process(false)
	cruiser.position = Vector2(600, 0)
	cruiser.rotation = 0.0
	var slow_car := SlowCar.new()
	slow_car.add_to_group("vehicle")
	scene.add_child(slow_car)
	slow_car.position = Vector2(700, 0)
	slow_car.velocity = Vector2(25, 0)
	cruiser.target = slow_car
	for frame in 20: cruiser._physics_process(0.1)
	check(not cruiser.officer_deployed, "Polícia permanece na viatura enquanto o carro anda devagar")
	slow_car.velocity = Vector2.ZERO
	cruiser.current_speed = 0.0
	cruiser.velocity = Vector2.ZERO
	var heading: float = cruiser.rotation
	for frame in 8: cruiser._physics_process(0.1)
	check(cruiser.officer_deployed and cruiser.is_acting, "Parada estável inicia abordagem")
	check(absf(angle_difference(heading, cruiser.rotation)) < 0.01, "Viatura não gira enquanto desembarca")
	for crew in get_nodes_in_group("police_officer"):
		if crew.service_vehicle == cruiser: crew.queue_free()
	cruiser._deactivate()
	slow_car.queue_free()
	wanted.current_stars = 0
	await physics_frame
	# A equipe precisa caminhar mais de sete segundos e continuar sendo esperada.
	for service in ["ambulance", "fire"]:
		var unit = root.get_node("EmergencyPool").get_vehicle(service)
		unit.set_physics_process(false)
		unit.position = Vector2(1000, 0)
		unit.rotation = 0.0
		var incident := Incident.new()
		scene.add_child(incident)
		incident.position = Vector2(1190, 0)
		unit.target = incident
		unit._physics_process(0.1)
		check(unit.is_acting and unit._response_crew.size() == 2, service + ": desembarca no final da faixa")
		var crew_snapshot: Array = unit._response_crew.duplicate()
		for crew in crew_snapshot: crew.speed = 35.0
		var origin: Vector2 = unit.position
		var abandoned := false
		for frame in 1500:
			if not unit.is_returning_to_base: unit._physics_process(1.0 / 60.0)
			var outside := false
			for crew in crew_snapshot:
				if is_instance_valid(crew) and crew.state != crew.State.EMBARKED: outside = true
			if outside and (unit.is_returning_to_base or unit.position.distance_to(origin) > 0.1): abandoned = true
			await physics_frame
			if unit.is_returning_to_base: break
		check(not abandoned, service + ": espera a equipe sem sair após sete segundos")
		check(incident.treatments > 0 if service == "ambulance" else incident.extinguished, service + ": conclui o atendimento")
		check(unit.returned_paramedics == 2 if service == "ambulance" else unit.returned_firefighters == 2, service + ": os dois socorristas reembarcam")
		check(unit.is_returning_to_base, service + ": retorna à base após o embarque")
		for crew in crew_snapshot:
			if is_instance_valid(crew): crew.queue_free()
		unit._deactivate()
		incident.queue_free()
		await physics_frame
	# O bloqueio não pode contar como atendimento à distância.
	var fireman = load("res://Firefighter.tscn").instantiate()
	scene.add_child(fireman)
	fireman.set_physics_process(false)
	var fire := Incident.new()
	scene.add_child(fire)
	fire.position = Vector2(50, 0)
	fireman.target = fire
	fireman.stuck_timer = 3.0
	obstacle = wall(Vector2(25, 0), Vector2(10, 100))
	await physics_frame
	fireman._physics_process(0.1)
	check(fireman.state == fireman.State.APPROACH and not fire.extinguished, "Bombeiro não apaga incêndio através da parede")
	for frame in 600:
		fireman._physics_process(1.0 / 60.0)
		await physics_frame
		if fire.extinguished: break
	check(fire.extinguished, "Bombeiro contorna a parede e trabalha do lado acessível")
	fireman.queue_free()
	fire.queue_free()
	obstacle.queue_free()
	await physics_frame
	var ped = load("res://world/shared/pedestrians/AuthoredSidewalkPedestrian.gd").new()
	ped.configure_authored_route(PackedVector2Array([Vector2(0, 300), Vector2(500, 300)]), "routine")
	scene.add_child(ped)
	ped.set_physics_process(false)
	ped.visit_cooldown = 100.0
	ped._window_shop_pause = 2.0
	var paused_position: Vector2 = ped.position
	for frame in 60:
		ped._physics_process(1.0 / 60.0)
		await physics_frame
	check(ped.position.distance_to(paused_position) < 0.1 and ped.velocity.is_zero_approx(), "Pausa de vitrine interrompe a caminhada")
	ped._window_shop_pause = 0.0
	for frame in 60:
		ped._physics_process(1.0 / 60.0)
		await physics_frame
	check(ped.position.distance_to(paused_position) > 20.0 and not ped.is_scared, "Pedestre retoma caminhada normal após a pausa")
	ped.is_visiting = true
	ped._visiting_timer = 0.0
	ped._visiting_door_pos = Vector2(900, 900)
	ped._process_visiting_state(13.0)
	check(not ped.is_visiting and ped.visit_cooldown > 0.0, "Porta inacessível encerra a tentativa de visita")
	ped.queue_free()
	var witness := Witness.new()
	witness.add_to_group("pedestrian")
	scene.add_child(witness)
	witness.position = Vector2(500, 0)
	obstacle = wall(Vector2(200, 0), Vector2(20, 200))
	await physics_frame
	preload("res://PedestrianDanger.gd").report(scene, Vector2.ZERO, Vector2.RIGHT, null)
	check(witness.alerts == 0, "Tiro bloqueado não causa pânico em outra rua")
	witness.position = Vector2(100, 30)
	preload("res://PedestrianDanger.gd").report(scene, Vector2.ZERO, Vector2.RIGHT, null)
	check(witness.alerts == 1, "Testemunha próxima reage ao tiro")
	scene.queue_free()
	await process_frame
	print("RESPONDER_ROUTINES: ", failures)
	quit(0 if failures.is_empty() else 1)
