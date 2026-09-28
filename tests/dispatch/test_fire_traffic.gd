extends SceneTree

const VEHICLE = preload("res://gameplay/dispatch/DispatchVehicle.gd")
const DRIVER = preload("res://gameplay/dispatch/DispatchDriver.gd")
const ROUTES = preload("res://gameplay/NativeTrafficRoutes.gd")
const KIT = preload("res://tests/dispatch/DispatchTestKit.gd")
var failures: Array[String] = []
var checks := 0

func _initialize() -> void: run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)

func run() -> void:
	await scenario(24.0, false)
	await scenario(9.0, false)
	await scenario(24.0, true)
	check(checks == 24, "todos os cenários executados")
	print("FIRE_TRAFFIC checks=%d failures=%d" % [checks, failures.size()])
	for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)

func scenario(distance: float, opposing: bool) -> void:
	var scene := Node3D.new()
	root.add_child(scene)
	KIT.add_wall(scene, Vector3(0, -0.5, 0), Vector3(200, 1, 300))
	var roads := ROUTES.new()
	roads.configure([{"id": "straight", "width": 12.0, "points": PackedVector3Array([Vector3(0, 0, 120), Vector3(0, 0, -120)])}])
	var truck := VEHICLE.new()
	truck.archetype = "rescue_pumper"
	truck.position = Vector3(3, 0.05, 50)
	scene.add_child(truck)
	truck.ensure_equipment(scene)
	truck.equipment.set_process(false)
	truck.equipment.siren_on = true
	var blocker := VEHICLE.new()
	blocker.position = truck.position + Vector3(0, 0, -distance)
	scene.add_child(blocker)
	blocker.traffic = true
	blocker.set_physics_process(false)
	var second := VEHICLE.new()
	second.position = blocker.position + Vector3(0, 0, -7)
	scene.add_child(second)
	second.traffic = true
	second.set_physics_process(false)
	var driver := DRIVER.new()
	driver.setup(truck, 10.0, 2.0)
	driver.enable_overtaking(roads)
	var route := Curve3D.new()
	route.add_point(Vector3(3, 0, 90))
	route.add_point(Vector3(3, 0, -70))
	route.set_meta("traffic_open", true)
	driver.set_route(route)
	var oncoming: CharacterBody3D
	if opposing:
		oncoming = VEHICLE.new()
		oncoming.position = Vector3(-3, 0.05, 15)
		oncoming.rotation.y = PI
		scene.add_child(oncoming)
		oncoming.set_physics_process(false)
	await physics_frame
	await physics_frame
	check(driver.overtake._stopped_fire_blocker(blocker), "fila parada reconhecida")
	blocker.controlled = true
	check(not driver.overtake._stopped_fire_blocker(blocker), "não trata carro do jogador como fila ambiente")
	blocker.controlled = false
	truck.equipment.siren_on = false
	check(not driver.overtake._stopped_fire_blocker(blocker), "sem sirene não invade contramão para fila")
	truck.equipment.siren_on = true
	blocker.rotation.y = PI
	check(not driver.overtake._stopped_fire_blocker(blocker), "carro contrário não é alvo de ultrapassagem")
	blocker.rotation.y = 0
	var rear := KIT.add_wall(scene, truck.position + Vector3(0, 1, truck.half_length + 1), Vector3(3, 2, 1))
	await physics_frame
	await physics_frame
	check(not driver._rear_clear(), "obstáculo traseiro impede ré")
	rear.free()
	await physics_frame
	var health: float = truck.health
	var passed := false
	var reversed := false
	var unsafe := false
	var arrived := false
	for frame in 2400:
		driver.tick(1.0 / 60.0)
		await physics_frame
		reversed = reversed or driver.reversing
		if opposing and driver.overtake.is_active(): unsafe = true
		if truck.global_position.z < second.global_position.z - 12.0 and not driver.pending_recovery():
			passed = true
		if driver.at_route_end():
			arrived = true
			break
		if opposing and frame >= 600: break
	check(is_equal_approx(truck.health, health), "sem colisão/dano durante desvio")
	if opposing:
		check(not unsafe and not passed, "aguarda contramão ocupada")
	else:
		check(passed, "ultrapassa fila e retoma rota: distância %.1f; estado %s motivo %s posição %s" % [distance, driver.overtake.state, driver.overtake.last_reason, truck.position])
		check(arrived, "chega ao destino depois de contornar fila")
		if distance < 10.0: check(reversed, "recua com segurança para criar espaço")
	driver.discard_overtaking("test_end")
	driver.disable_overtaking()
	scene.free()
	await physics_frame
