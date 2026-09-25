extends SceneTree
## Trânsito que não trava: viatura parada na faixa, fila atrás dela, fila de sinal
## vermelho e saída de cruzamento ocupada (Vehicle._drive_traffic, 2026-09-25).
## Mundo mínimo: chão plano, rota reta aberta e carros reais do catálogo.

const VEHICLE := preload("res://scripts/Vehicle.gd")
const JUNCTIONS := preload("res://gameplay/traffic_junctions/TrafficJunctions.gd")

var failures: Array[String] = []

func check(ok: bool, label: String) -> void:
	if not ok: failures.append(label)
	print(("PASS " if ok else "FAIL ") + label)

func _initialize() -> void: run.call_deferred()

func floor_body(parent: Node) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var box := CollisionShape3D.new()
	box.shape = BoxShape3D.new()
	box.shape.size = Vector3(40, 1, 400)
	box.position = Vector3(0, -.5, -150)
	body.add_child(box)
	parent.add_child(body)

## Rota reta indo para -Z na faixa da direita (x = 0); contramão em x = -3,4.
func straight_route() -> Curve3D:
	var curve := Curve3D.new()
	for z in range(10, -300, -10): curve.add_point(Vector3(0, 0, z))
	curve.set_meta("traffic_open", true)
	return curve

func car(parent: Node, point: Vector3, traffic_route: Curve3D) -> CharacterBody3D:
	var vehicle := VEHICLE.new()
	vehicle.archetype = "union_sedan"
	vehicle.position = point
	parent.add_child(vehicle)
	if traffic_route != null:
		vehicle.route = traffic_route
		vehicle.traffic = true
	return vehicle

func settle(seconds: float) -> void:
	for i in int(seconds * Engine.physics_ticks_per_second): await physics_frame

func run() -> void:
	JUNCTIONS.configure(null)
	var world := Node3D.new()
	root.add_child(world)
	floor_body(world)
	var route := straight_route()

	# 1) Viatura parada no meio da faixa, sem ninguém dirigindo, e fila de três atrás.
	var police := car(world, Vector3(0, .1, -40), null)
	police.set_external_driver(true)
	police.set_meta("dispatch_unit", true)
	var queue: Array = []
	for i in 3: queue.append(car(world, Vector3(0, .1, -20 + i * 7.0), route))
	await settle(40.0)
	var passed := 0
	for vehicle in queue: if vehicle.global_position.z < -52.0: passed += 1
	check(passed == 3, "fila inteira contornou a viatura parada (%d/3)" % passed)
	var back_in_lane := true
	for vehicle in queue: back_in_lane = back_in_lane and absf(vehicle.global_position.x) < 1.0 and vehicle.bypass_side == 0.0
	check(back_in_lane, "depois do desvio todos voltaram para a própria faixa")
	check(absf(police.global_position.z + 40.0) < .5 and absf(police.global_position.x) < .5, "viatura não foi empurrada")
	for vehicle in queue + [police]: vehicle.free()

	# 2) Contramão ocupada dos dois lados: não desvia, só espera e acumula stuck_time.
	var wall_left := car(world, Vector3(-3.4, .1, -46), null)
	var wall_right := car(world, Vector3(2.6, .1, -46), null)
	var wreck := car(world, Vector3(0, .1, -40), null)
	wreck.receive_damage(10000.0)
	var waiting := car(world, Vector3(0, .1, -28), route)
	await settle(8.0)
	check(waiting.bypass_side == 0.0 and waiting.global_position.z > -36.0, "sem espaço lateral não invade (fica na faixa)")
	check(waiting.stuck_time > 3.0, "carro travado acumula stuck_time para a limpeza (%.1f s)" % waiting.stuck_time)
	for vehicle in [wall_left, wall_right, wreck, waiting]: vehicle.free()

	# 3) Fila atrás de carro parado em sinal: stall_time zero, ninguém ultrapassa.
	var lead := car(world, Vector3(0, .1, -40), null)
	var follower := car(world, Vector3(0, .1, -31), route)
	await settle(.5)
	lead.traffic = true
	lead.route = route
	lead.set_physics_process(false)
	lead.junction_wait = true
	lead.blocked = false
	lead.speed = 0.0
	await settle(8.0)
	check(follower.blocked and follower.stall_time == 0.0 and follower.bypass_side == 0.0, "fila de sinal vermelho não conta como travada nem ultrapassa")
	check(follower.stuck_time == 0.0, "fila de sinal não vai para a limpeza")
	for vehicle in [lead, follower]: vehicle.free()

	# 4) Cruzamento com a saída ocupada por carro parado: espera antes da faixa.
	JUNCTIONS.configure({
		"vertices": [Vector3(0, 0, -80), Vector3(30, 0, -80), Vector3(-30, 0, -80), Vector3(0, 0, -50), Vector3(0, 0, -110)],
		"edges": {0: [{"to": 1}, {"to": 2}, {"to": 3}, {"to": 4}]},
	})
	var parked := car(world, Vector3(0, .1, -91), null)
	var arriving := car(world, Vector3(0, .1, -55), route)
	await settle(5.0)
	var line_z := -80.0 + JUNCTIONS.stop_line(JUNCTIONS.key_of(Vector3(0, 0, -80)))
	check(arriving.global_position.z - arriving.half_length > line_z - 1.0, "saída ocupada: para antes da faixa (frente em z=%.1f)" % (arriving.global_position.z - arriving.half_length))
	parked.free()
	await settle(6.0)
	check(arriving.global_position.z < -90.0, "saída livre: atravessa o cruzamento")
	arriving.free()
	JUNCTIONS.configure(null)

	print("TRAFFIC_UNSTICK ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
