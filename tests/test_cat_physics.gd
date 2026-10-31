extends SceneTree
## Corpo real do gato e mobília de produção num World3D nativo mínimo.
## Isto valida só o movimento físico; profundidade renderizada/desempenho são à parte.
const CAT := preload("res://runtime/cats/HouseCat.gd")
const FURNITURE := preload("res://runtime/cats/CatFurniture.gd")
var scene: Node3D
var cat: CharacterBody3D
var bed: Node3D
var scratcher: Node3D
var ball: Node3D
var controller: FixtureController
var checks := 0
var failures: Array[String] = []

class FixtureController extends RefCounted:
	var enabled := true
	func can_animate() -> bool: return enabled
	func choose_activity(actor: CharacterBody3D) -> void:
		actor.set_activity("sit")
		actor.rest = 100.0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	print("CAT_PHYSICS ", "PASS " if ok else "FAIL ", label)
	if not ok: failures.append(label)

func _box(label: String, at: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = label
	body.collision_layer = 1
	body.collision_mask = 0
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collider.shape = shape
	body.add_child(collider)
	scene.add_child(body)
	body.global_position = at
	return body

func _sweep(from: Vector3, to: Vector3) -> bool:
	return cat.test_move(Transform3D(Basis.IDENTITY, from), to - from)

func _walk(from: Vector3, to: Vector3, next := "sit", prop: Node3D = null, max_frames := 360) -> bool:
	cat.global_position = from
	cat.velocity = Vector3.ZERO
	cat.walk_to(to, next, prop)
	cat.set_physics_process(true)
	for frame in max_frames:
		await physics_frame
		if cat.activity != "walk": break
	cat.set_physics_process(false)
	return Vector2(cat.global_position.x - to.x, cat.global_position.z - to.z).length() < .12 and cat.activity == next

func run() -> void:
	create_timer(45).timeout.connect(func(): push_error("CAT_PHYSICS timeout"); quit(3))
	scene = Node3D.new()
	scene.name = "CatPhysicsFixture"
	root.add_child(scene)
	current_scene = scene
	_box("Floor", Vector3(0, -.15, 0), Vector3(24, .3, 16))
	_box("Wall", Vector3(0, 1, 2), Vector3(2.2, 2, .2))
	bed = FURNITURE.create("bed")
	scene.add_child(bed)
	bed.position = Vector3(-3, 0, 0)
	scratcher = FURNITURE.create("scratcher")
	scene.add_child(scratcher)
	scratcher.position = Vector3(3, 0, 0)
	ball = FURNITURE.create("ball")
	scene.add_child(ball)
	ball.position = Vector3(6, 0, 0)
	controller = FixtureController.new()
	cat = CAT.new()
	cat.configure("cat_02", 1, true, controller)
	scene.add_child(cat)
	cat.global_position = Vector3(0, .025, 0)
	cat.set_process(false)
	cat.set_physics_process(false)
	for frame in 4: await physics_frame
	check(is_instance_valid(cat.model) and cat.model.get_meta("native_cat_model", false), "corpo usa o modelo 3D real")
	check(_sweep(Vector3(0, .025, 0), Vector3(0, .025, 5)), "sweep longo não atravessa parede")
	check(not _sweep(Vector3(1.65, .025, 0), Vector3(1.65, .025, 5)), "rota livre ao lado da parede permanece caminhável")
	check(not await _walk(Vector3(0, .025, 0), Vector3(0, .025, 4)), "movimento real para antes da parede")
	check(cat.global_position.z < 1.72 and cat.global_position.z > 1.45, "corpo para junto à parede sem penetrar nem parar distante")
	check(await _walk(cat.global_position, Vector3(0, .025, -.4)), "gato se recupera e caminha de volta após tocar parede")
	await _bed_contract()
	await _toy_contract()
	await _lifecycle_contract()
	print("CAT_PHYSICS_RESULT checks=", checks, " failures=", failures)
	quit(0 if failures.is_empty() else 1)

func _bed_contract() -> void:
	var center := bed.global_position + Vector3.UP * .025
	var use_point: Vector3 = center + bed.get_meta("use_position")
	check(not _sweep(center + Vector3(0, 0, -1.15), use_point), "frente aberta da caminha admite o gato inteiro")
	check(_sweep(center + Vector3(-1.2, 0, 0), use_point), "lateral esquerda da caminha bloqueia")
	check(_sweep(center + Vector3(1.2, 0, 0), use_point), "lateral direita da caminha bloqueia")
	check(_sweep(center + Vector3(0, 0, 1.2), use_point), "encosto da caminha bloqueia")
	check(await _walk(center + Vector3(0, 0, -1.15), use_point, "sleep", bed), "gato caminha pela abertura e deita dentro da caminha")
	check(absf(cat.global_position.y) < .12, "gato repousa no piso sem subir no encosto")
	check(await _walk(cat.global_position, center + Vector3(0, 0, -1.15)), "gato sai da caminha pela frente")
	check(not await _walk(center + Vector3(1.2, 0, 0), use_point, "sleep", bed), "movimento real não atravessa lateral para fingir uso da cama")
	check(cat.global_position.x > center.x + .43, "gato barrado permanece fora do encosto lateral")

func _toy_contract() -> void:
	var center := scratcher.global_position + Vector3.UP * .025
	var use_point: Vector3 = scratcher.global_position + scratcher.get_meta("use_position")
	check(_sweep(center + Vector3(0, 0, -1), center + Vector3(0, 0, 1)), "base e poste do arranhador bloqueiam sweep")
	check(not _sweep(center + Vector3(0, 0, -1.15), use_point), "posição autorada de arranhar admite aproximação")
	check(await _walk(center + Vector3(0, 0, -1.15), use_point, "scratch", scratcher), "gato alcança arranhador e inicia animação funcional")
	center = ball.global_position + Vector3.UP * .025
	use_point = ball.global_position + ball.get_meta("use_position")
	check(_sweep(center + Vector3(0, 0, -1), center + Vector3(0, 0, 1)), "bolinha tem colisão física proporcional")
	check(await _walk(center + Vector3(0, 0, -1), use_point, "play", ball), "gato chega à bolinha sem atravessá-la")

func _lifecycle_contract() -> void:
	cat.global_position = Vector3(-7, .025, 2)
	cat.walk_to(Vector3(-7, .025, 4))
	controller.enabled = false
	cat.set_physics_process(true)
	var before := cat.global_position
	for frame in 8: await physics_frame
	cat.set_physics_process(false)
	check(cat.global_position == before, "transição bloqueada suspende movimento")
	controller.enabled = true
	var discovery := CAT.new()
	discovery.configure("cat_01", 0, false, controller)
	scene.add_child(discovery)
	discovery.position = Vector3(-7, .025, -2)
	discovery.set_process(false)
	discovery.walk_to(Vector3(-7, .025, -4))
	before = discovery.global_position
	for frame in 8: await physics_frame
	check(discovery.global_position == before, "gato não adotado fica no ponto de descoberta")
	discovery.queue_free()
