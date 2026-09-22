extends SceneTree
## Dirigibilidade da V1 no Vehicle da V2, em pista plana isolada.
## Mede por carro: 0–60 km/h, velocidade final, raio de curva e deriva com freio
## de mão; e confere o que o catálogo da V1 manda: velocidade de estrada =
## max_speed × 0,8 / 16, caminhão mais lento e de curva mais aberta que cupê, e
## freio de mão soltando a traseira. Com `-- --legacy` roda o controle antigo
## da V2 para comparação (só imprime, não aprova).
const VEHICLE := preload("res://scripts/Vehicle.gd")
const IDS := ["sport_coupe", "police_cruiser", "porto_rosso", "american_dump_truck"]
var failures: Array[String] = []
var legacy := false
var stage: Node3D

func _initialize() -> void:
	legacy = "--legacy" in OS.get_cmdline_user_args()
	run.call_deferred()

func run() -> void:
	stage = Node3D.new()
	root.add_child(stage)
	var ground := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4000, 1, 4000)
	shape.shape = box
	shape.position.y = -0.5
	ground.add_child(shape)
	stage.add_child(ground)
	var results := {}
	for id in IDS: results[id] = await measure(id)
	print(("LEGACY " if legacy else "") + "V1_HANDLING ", JSON.stringify(results))
	if not legacy:
		var coupe: Dictionary = results.sport_coupe
		var truck: Dictionary = results.american_dump_truck
		for id in IDS:
			var r: Dictionary = results[id]
			check(absf(r.top - r.expected_top) / r.expected_top < 0.1, "%s velocidade de estrada = max_speed×0,8/16" % id, "top=%.1f esperado=%.1f" % [r.top, r.expected_top])
		check(truck.t60 > coupe.t60 * 1.5 or truck.t60 < 0.0, "caminhão acelera bem mais devagar que o cupê", "cupê=%.2f s caminhão=%.2f s" % [coupe.t60, truck.t60])
		check(truck.radius > coupe.radius * 1.3, "caminhão faz curva mais aberta que o cupê", "cupê=%.1f m caminhão=%.1f m" % [coupe.radius, truck.radius])
		check(coupe.handbrake_slide > 1.5, "freio de mão solta a traseira do cupê", "deriva=%.2f m/s" % coupe.handbrake_slide)
		check(coupe.plain_slide < coupe.handbrake_slide * 0.6, "sem freio de mão a deriva é menor", "normal=%.2f freio=%.2f" % [coupe.plain_slide, coupe.handbrake_slide])
	print("V1_HANDLING checks failures=", failures)
	quit(1 if failures.size() > 0 and not legacy else 0)

func check(ok: bool, label: String, detail := "") -> void:
	print(("CASE PASS " if ok else "CASE FAIL ") + label + " | " + detail)
	if not ok: failures.append(label)

func measure(id: String) -> Dictionary:
	var input = root.get_node("/root/GameInput")
	var car: CharacterBody3D = VEHICLE.new()
	car.archetype = id
	car.position = Vector3(0, 0.05, 0)
	stage.add_child(car)
	if legacy: car.handling = null
	car.controlled = true
	for i in 10: await physics_frame
	var spec: Dictionary = preload("res://runtime/FleetCatalog.gd").spec(id)
	var result := {"expected_top": float(spec.max_speed) * 0.8 / 16.0}
	# Aceleração em linha reta.
	input.touch_move = Vector2(0, -1)
	var t := 0.0
	result.t60 = -1.0
	for i in 60 * 30:
		await physics_frame
		t += 1.0 / 60.0
		if result.t60 < 0.0 and _planar(car) >= 60.0 / 3.6: result.t60 = snappedf(t, 0.01)
		if i == 60 * 6: result.v6 = snappedf(_planar(car), 0.1)
	result.top = snappedf(_planar(car), 0.1)
	# Curva: a 12 m/s, solta o acelerador e vira tudo por 1 s.
	await _reach(car, input, 12.0)
	input.touch_move = Vector2(1, 0)
	var yaw_start: float = car.rotation.y
	var speeds := 0.0
	var plain_slide := 0.0
	for i in 60:
		await physics_frame
		speeds += _planar(car)
		plain_slide = maxf(plain_slide, _lateral(car))
	var turned := absf(angle_difference(yaw_start, car.rotation.y))
	result.radius = snappedf((speeds / 60.0) / maxf(turned, 0.001), 0.1)
	result.plain_slide = snappedf(plain_slide, 0.01)
	# Freio de mão em curva a 15 m/s.
	await _reach(car, input, 15.0)
	input.touch_move = Vector2(1, 0)
	Input.action_press("handbrake")
	var slide := 0.0
	for i in 60:
		await physics_frame
		slide = maxf(slide, _lateral(car))
	Input.action_release("handbrake")
	result.handbrake_slide = snappedf(slide, 0.01)
	input.touch_move = Vector2.ZERO
	car.queue_free()
	await physics_frame
	return result

func _reach(car: CharacterBody3D, input, target: float) -> void:
	# Recomeça parado e acelera em linha reta até a velocidade pedida.
	car.teleport(Vector3(0, 0.05, 0)) if car.has_method("teleport") else null
	car.speed = 0.0
	car.horizontal_velocity = Vector3.ZERO
	car.rotation.y = 0.0
	input.touch_move = Vector2(0, -1)
	for i in 60 * 20:
		await physics_frame
		if _planar(car) >= target: break
	input.touch_move = Vector2.ZERO

static func _planar(car: CharacterBody3D) -> float:
	return Vector2(car.velocity.x, car.velocity.z).length()

static func _lateral(car: CharacterBody3D) -> float:
	return absf(Vector3(car.velocity.x, 0, car.velocity.z).dot(car.global_basis.x))
