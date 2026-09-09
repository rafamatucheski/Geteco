extends SceneTree

## Verifica que toda roda dianteira 3D esterça para o mesmo lado em que o carro
## vira, e que o pneu gira com o raio autoral do próprio modelo.
##
## O que este teste NÃO cobre: aparência final renderizada no SubViewport,
## cadência de re-render e o comportamento das viaturas de emergência em
## perseguição (essas exigem partida de verdade).

const RIG := preload("res://prototypes/living_cast/VehicleWheelRig.gd")
const PPM := 74.0 / 4.46
const STEP := 1.0 / 60.0

var failures := 0

func _init() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	print(("PASS " if ok else "FAIL ") + message)
	if not ok:
		failures += 1
		push_error(message)

func _model_paths() -> Array:
	var paths: Array = []
	for id in VehicleCatalog.VEHICLES:
		var path: String = VehicleCatalog.get_vehicle_spec(id).model_class
		if not paths.has(path): paths.append(path)
	for id in VehicleCatalog.LEGACY_MODELS:
		var path: String = VehicleCatalog.LEGACY_MODELS[id]
		if not paths.has(path): paths.append(path)
	paths.sort()
	return paths

func _axle_indices(rig) -> Dictionary:
	var min_z := INF
	var max_z := -INF
	for pivot in rig.pivots:
		min_z = minf(min_z, pivot.position.z)
		max_z = maxf(max_z, pivot.position.z)
	var limit := (min_z + max_z) * 0.5
	var front: Array = []
	var rear: Array = []
	for i in rig.pivots.size():
		if rig.pivots[i].position.z < limit: front.append(i)
		else: rear.append(i)
	return {"front": front, "rear": rear}

## Direção real do pneu na tela, com a mesma projeção usada em jogo:
## +X do mundo 3D é a direita da tela e +Z é para baixo.
func _tire_screen_angle(model: Node3D, pivot: Node3D) -> float:
	var forward: Vector3 = (model.transform.basis * pivot.transform.basis) * Vector3(0, 0, -1)
	return Vector2(forward.x, forward.z).angle()

func _drive(rig, yaw_rate: float, speed_m: float, steps: int = 60) -> void:
	var heading := 0.0
	for i in steps:
		heading += yaw_rate * STEP
		rig.update(STEP, speed_m, heading)

func run() -> void:
	# ---- 1. Todo modelo autoral entrega um rig completo ----------------------
	# Os modelos precisam estar na árvore: RearEngineCoupe e BossMuscleModel só
	# constroem a geometria em _ready, como acontece dentro do SubViewport.
	var bench := Node3D.new()
	root.add_child(bench)
	for path in _model_paths():
		var model: Node3D = load(path).new()
		bench.add_child(model)
		var rig = RIG.new()
		check(rig.mount(model), "%s: rodas extraídas do metadado autoral" % path.get_file())
		check(rig.pivots.size() >= 4, "%s: pelo menos quatro cubos (obteve %d)" % [path.get_file(), rig.pivots.size()])
		var axles := _axle_indices(rig)
		check(not axles.front.is_empty() and not axles.rear.is_empty(), "%s: eixo dianteiro e traseiro distintos" % path.get_file())
		var tires_ok := true
		for spin in rig.spinners:
			if spin.get_child_count() == 0: tires_ok = false
		check(tires_ok, "%s: todo cubo giratório recebeu peças de roda" % path.get_file())

		# Curva à direita: guinada 2D positiva, roda dianteira aponta à direita.
		_drive(rig, 0.55, 12.0)
		var steer_right: float = rig.steering_angle
		check(steer_right > 0.05, "%s: curva à direita produz esterço à direita (%.3f rad)" % [path.get_file(), steer_right])
		for i in axles.front:
			check(rig.pivots[i].rotation.y < -0.05, "%s: cubo dianteiro %d gira para a direita" % [path.get_file(), i])
		for i in axles.rear:
			check(is_zero_approx(rig.pivots[i].rotation.y), "%s: cubo traseiro %d não esterça" % [path.get_file(), i])

		# Curva à esquerda pelo mesmo caminho.
		var left_rig = RIG.new()
		var left_model: Node3D = load(path).new()
		bench.add_child(left_model)
		left_rig.mount(left_model)
		_drive(left_rig, -0.55, 12.0)
		check(left_rig.steering_angle < -0.05, "%s: curva à esquerda produz esterço à esquerda (%.3f rad)" % [path.get_file(), left_rig.steering_angle])
		for i in _axle_indices(left_rig).front:
			check(left_rig.pivots[i].rotation.y > 0.05, "%s: cubo dianteiro %d gira para a esquerda" % [path.get_file(), i])
		bench.remove_child(left_model)
		left_model.free()

		# O pneu roda, e roda com o raio que o modelo declarou.
		var spun := false
		for spin in rig.spinners:
			if absf(spin.rotation.x) > 0.1: spun = true
		check(spun, "%s: pneus giram com o deslocamento" % path.get_file())
		bench.remove_child(model)
		model.free()

	# ---- 2. Projeção na tela: direita é direita, esquerda é esquerda ---------
	var geometry_model: Node3D = load("res://prototypes/living_cast/models/UnionSedanModel.gd").new()
	bench.add_child(geometry_model)
	var geometry_rig = RIG.new()
	geometry_rig.mount(geometry_model)
	var front_index: int = _axle_indices(geometry_rig).front[0]
	for heading in [0.0, 2.0, -1.2]:
		geometry_model.rotation.y = -heading - PI * 0.5
		for steer in [0.30, -0.30]:
			geometry_rig.update(STEP, 0.0, heading, steer)
			var tire := _tire_screen_angle(geometry_model, geometry_rig.pivots[front_index])
			var offset := angle_difference(heading, tire)
			check(absf(offset - steer) < 0.01,
				"proa %.1f rad: pneu aponta %.3f rad ao lado do carro, esterço pedido %.3f" % [heading, offset, steer])
	bench.remove_child(geometry_model)
	geometry_model.free()
	bench.queue_free()

	# ---- 3. Carro do jogador na cena real -----------------------------------
	var scene = load("res://world/harbor/HarborPreview.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	for i in 6: await physics_frame
	var car = scene.get_node("PlayerCar")
	check(car.wheels.size() == 4 and car.spinners.size() == 4, "PlayerCar monta quatro rodas articuladas")
	car.set_physics_process(false)
	car.rotation = 0.0
	car.velocity = Vector2.ZERO
	car.is_driven_by_player = true
	for i in 60:
		car._apply_steering_motion(1.0, STEP)
		car.wheel_rig.update(STEP, 0.0, car.global_rotation, car.steering_angle)
	var player_axles := _axle_indices(car.wheel_rig)
	check(car.steering_angle > 0.4, "volante à direita chega ao batente com o carro parado")
	for i in player_axles.front:
		check(car.wheels[i].rotation.y < -0.4, "roda dianteira %d acompanha o volante parado" % i)
	for i in player_axles.rear:
		check(is_zero_approx(car.wheels[i].rotation.y), "roda traseira %d permanece reta" % i)
	# Soltando o volante as rodas voltam ao centro.
	for i in 90:
		car._apply_steering_motion(0.0, STEP)
		car.wheel_rig.update(STEP, 0.0, car.global_rotation, car.steering_angle)
	for i in player_axles.front:
		check(absf(car.wheels[i].rotation.y) < 0.02, "roda dianteira %d recentraliza ao soltar o volante" % i)
	scene.queue_free()
	await process_frame

	# ---- 4. Trânsito ambiente numa curva de verdade -------------------------
	for turn in [{"label": "direita", "corner": Vector2(4000, 2000), "sign": -1.0},
			{"label": "esquerda", "corner": Vector2(4000, -2000), "sign": 1.0}]:
		var sample := await _traffic_corner(turn.corner)
		check(sample.wheels == 4, "trânsito na curva à %s monta quatro rodas" % turn.label)
		check(absf(sample.steer) > 0.05, "trânsito na curva à %s esterça (%.3f rad)" % [turn.label, sample.steer])
		check(sample.front * turn.sign > 0.05, "trânsito: cubo dianteiro acompanha a curva à %s (%.3f)" % [turn.label, sample.front])
		check(is_zero_approx(sample.rear), "trânsito na curva à %s: eixo traseiro reto" % turn.label)

	print("VEHICLE_WHEEL_STEERING failures=%d" % failures)
	quit(0 if failures == 0 else 1)


## Roda um TrafficVehicle por uma curva autoral com a câmera colada nele, que é
## a única condição em que `_update_3d_orientation` realmente atualiza a pose.
func _traffic_corner(corner: Vector2) -> Dictionary:
	var world := Node2D.new()
	root.add_child(world)
	current_scene = world
	var camera := Camera2D.new()
	world.add_child(camera)
	camera.make_current()
	var path := Path2D.new()
	path.curve = Curve2D.new()
	# Arco suave de raio 800: uma curva de três pontos vira 45 graus num único
	# passo, o que o rig trata como teleporte — e ruas autorais não fazem isso.
	path.curve.add_point(Vector2.ZERO)
	path.curve.add_point(Vector2(1200, 0))
	for step in range(1, 41):
		var angle := PI * 0.5 * step / 40.0
		path.curve.add_point(Vector2(1200, 0) + Vector2(sin(angle), corner.sign().y * (1.0 - cos(angle))) * 800.0)
	world.add_child(path)
	var follow := PathFollow2D.new()
	path.add_child(follow)
	var car = preload("res://world/shared/traffic/TrafficVehicle.tscn").instantiate()
	follow.add_child(car)
	car.apply_archetype("union_sedan", Color.BLUE)
	# A cadência de pose é assumida aqui: o objetivo é medir o rig sobre uma proa
	# vinda da faixa de verdade, não reproduzir o negociador de espaçamento (que
	# sem malha viária ao redor mantém o carro parado).
	car.set_process(false)
	var speed := 420.0
	var result := {"wheels": 0, "steer": 0.0, "front": 0.0, "rear": 0.0, "progress": 0.0}
	for i in 600:
		follow.progress += speed / 60.0
		car.is_moving_on_lane = true
		car._lane_motion_speed = speed
		camera.global_position = car.global_position
		camera.force_update_scroll()
		await process_frame
		car._update_3d_orientation(1.0 / 60.0)
		result.wheels = car.wheels.size()
		result.progress = follow.progress
		if absf(car.wheel_rig.steering_angle) > absf(result.steer):
			result.steer = car.wheel_rig.steering_angle
			for pivot in car.wheels:
				if pivot.position.z < 0.0: result.front = pivot.rotation.y
				else: result.rear = pivot.rotation.y
	print("  [trânsito] progresso=%.1f rodas=%d esterço=%.3f renders=%d" % [result.progress, result.wheels, result.steer, car.body_render_requests])
	world.queue_free()
	await process_frame
	return result
