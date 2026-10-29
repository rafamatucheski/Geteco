extends SceneTree
## Guarda-chuva do pedestre: sobe o braço, abre, fica na palma; largado, voa com o impacto e cai no chão.
## Não prova que fica bonito nem o comportamento no vento real: isso é no jogo.
var failures: Array[String] = []
func _initialize() -> void: call_deferred("run")
func verify(value: bool, label: String) -> void:
	if not value: failures.append(label)
func run() -> void:
	var umbrella_script = load("res://gameplay/crowd/PedestrianUmbrella.gd")
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 1
	var floor_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200, 1, 200)
	floor_shape.shape = box
	floor_shape.position.y = -0.5
	floor_body.add_child(floor_shape)
	root.add_child(floor_body)

	var model = load("res://assets/CivilianModel.gd").new()
	model.appearance_locked = true
	model.lod_enabled = false
	root.add_child(model)
	var held = umbrella_script.new()
	held.model = model
	held.color = Color("8c2a2a")
	model.add_child(held)
	model.umbrella = held
	held.set_raining(true)
	for frame in 150: await process_frame
	verify(model.umbrella_arm_weight() > 0.99, "braço não subiu: %.2f" % model.umbrella_arm_weight())
	verify(is_equal_approx(held.open, 1.0), "não abriu: %.2f" % held.open)
	verify(held.visible, "guarda-chuva escondido com o braço em cima")
	var grip: Vector3 = held.position
	verify(grip.y > 0.9 and grip.y < 1.3, "palma fora da altura do peito: %s" % grip)
	var apex: Vector3 = held.to_global(Vector3.UP * umbrella_script.SHAFT_TOP)
	verify(Vector2(apex.x, apex.z).length() < 0.2, "copa não fica sobre a cabeça: %s" % apex)
	verify(apex.y > 1.85, "copa baixa demais: %.2f" % apex.y)

	held.set_raining(false)
	for frame in 150: await process_frame
	verify(held.open == 0.0 and model.umbrella_arm_weight() == 0.0, "não fechou/guardou")
	verify(not held.visible, "guarda-chuva visível depois de guardado")

	held.set_raining(true)
	for frame in 150: await process_frame
	var start: Transform3D = held.global_transform
	load("res://gameplay/crowd/LooseUmbrella3D.gd").spawn(root, start, held.color, held.open, Vector3(0, 0, 12))
	var loose: RigidBody3D = root.get_child(root.get_child_count() - 1)
	verify(loose.linear_velocity.z > 5.0 and loose.linear_velocity.y > 1.0, "não saiu voando com o carro")
	for frame in 180: await physics_frame
	verify(loose.global_position.z > start.origin.z + 2.0, "não andou na direção do impacto")
	verify(loose.global_position.y > -0.3 and loose.global_position.y < 1.5, "não ficou no chão: %.2f" % loose.global_position.y)

	if failures.is_empty():
		print("PASS test_pedestrian_umbrella")
		quit(0)
	else:
		for failure in failures: print("FAIL ", failure)
		quit(1)
