extends SceneTree
## Motoristas visíveis do trânsito (TrafficDriverPool, playtest 29/10). Pista plana com câmera e
## carros do trânsito parados: confere que o carro perto ganha motorista no banco, o longe não, o
## teto do pool vale, corpo é reaproveitado (não recriado), o roubo tira a mesma identidade, o carro
## que some devolve o corpo ao pool e o tiro no tronco fere/mata/faz fugir.
## Escrito em 29/10 sem rodar (o usuário pediu para não abrir Godot nessa sessão).
const VEHICLE := preload("res://scripts/Vehicle.gd")
const POOL := preload("res://gameplay/traffic/TrafficDriverPool.gd")
const MOCAP := preload("res://gameplay/VehicleBoardingMocap.gd")
var failures: Array[String] = []

class FakeProduction extends Node:
	var traffic_drivers: Node
	var civilian_reactions: Node

class FakeWorld extends Node3D:
	var production: Node
	var people: Array = []

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String, detail := "") -> void:
	print(("CASE PASS " if ok else "CASE FAIL ") + label + " | " + detail)
	if not ok: failures.append(label)

func run() -> void:
	var world := FakeWorld.new()
	root.add_child(world)
	var ground := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(600, 1, 600)
	shape.shape = box
	shape.position.y = -.5
	ground.add_child(shape)
	world.add_child(ground)
	var camera := Camera3D.new()
	camera.position = Vector3(0, 30, 10)
	camera.rotation.x = -1.2
	world.add_child(camera)
	camera.make_current()
	var production := FakeProduction.new()
	world.production = production
	world.add_child(production)
	var pool = POOL.new()
	pool.configure(world)
	pool._max = 2
	production.traffic_drivers = pool
	production.add_child(pool)
	var cars: Array = []
	for x in [0.0, 6.0, 12.0, 200.0]:
		var car: CharacterBody3D = VEHICLE.new()
		car.archetype = "sedan_classic"
		car.vehicle_id = "traffic_test_%d" % int(x)
		car.position = Vector3(x, .05, 0)
		world.add_child(car)
		car.traffic = true
		cars.append(car)
	for i in 30: await physics_frame
	# O pool monta um corpo por passo: alguns passos enchem os dois lugares.
	for i in 4: pool._refresh()
	var near: CharacterBody3D = cars[0]
	var far: CharacterBody3D = cars[3]
	check(pool._assigned.has(near.get_instance_id()), "carro perto ganha motorista")
	check(not pool._assigned.has(far.get_instance_id()), "carro longe fica sem motorista")
	check(pool._assigned.size() == 2 and pool._bodies.size() == 2, "teto do pool", "assigned=%d bodies=%d" % [pool._assigned.size(), pool._bodies.size()])
	if pool._assigned.has(near.get_instance_id()):
		var body: Node3D = pool._assigned[near.get_instance_id()].body
		check(body.get_parent() == near and body.visible, "corpo é filho do carro e visível")
		var pelvis_target: Vector3 = MOCAP.seat_pelvis(near)
		var pelvis: Vector3 = body.pelvis.global_position if body.get("pelvis") != null else body.global_position
		check(pelvis.distance_to(pelvis_target) < .25, "pelve no banco medido", "%.3f m" % pelvis.distance_to(pelvis_target))
	# Roubo: o corpo sai do banco e a identidade volta para o Actor.
	var bodies_before: int = pool._bodies.size()
	var identity: int = POOL.take_driver(world, near)
	check(identity >= 0 and not pool._assigned.has(near.get_instance_id()), "roubo tira o motorista do pool", "identity=%d" % identity)
	near.traffic = false
	near.controlled = true
	pool._refresh()
	check(pool._bodies.size() == bodies_before, "corpo reaproveitado, não recriado", "bodies=%d" % pool._bodies.size())
	check(pool._assigned.has((cars[2] as Node).get_instance_id()), "corpo estacionado vai para o próximo carro")
	# Carro que some devolve o corpo ao pool.
	var gone: CharacterBody3D = cars[1]
	var gone_body: Node3D = pool._assigned[gone.get_instance_id()].body if pool._assigned.has(gone.get_instance_id()) else null
	gone.queue_free()
	await process_frame
	await process_frame
	check(is_instance_valid(gone_body) and gone_body in pool._parked, "carro liberado devolve o corpo")
	# Tiro no tronco do motorista.
	var target: CharacterBody3D = cars[2]
	if pool._assigned.has(target.get_instance_id()):
		var body: Node3D = pool._assigned[target.get_instance_id()].body
		var chest: Vector3 = body.global_position + Vector3.UP * (.45 + .35 * body.scale.y)
		pool._bullet(target, chest + Vector3(-4, 0, 0), chest + Vector3(4, 0, 0), null)
		var state := str(target.get_meta(POOL.STATE_META, ""))
		check(state in ["hurt", "dead", "gone"], "tiro no tronco muda o motorista", state)
		if state == "dead": check(target.traffic == false, "morto: carro sai do trânsito e freia")
		# Tiro que não passa pelo tronco não conta.
		var other := str(target.get_meta(POOL.STATE_META, ""))
		pool._bullet(target, chest + Vector3(-4, 3, 0), chest + Vector3(4, 3, 0), null)
		check(str(target.get_meta(POOL.STATE_META, "")) == other, "tiro alto não acerta o motorista")
	print("TRAFFIC_DRIVER_POOL failures=", failures.size(), " ", failures)
	quit(1 if failures.size() > 0 else 0)
