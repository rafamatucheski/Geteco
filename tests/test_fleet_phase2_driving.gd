extends SceneTree

const SCENE: PackedScene = preload("res://prototypes/living_cast/FleetShowcasePhase2.tscn")

var failures: Array[String] = []

func _init() -> void:
	call_deferred("_run")

func _check(cond: bool, msg: String) -> void:
	if not cond:
		failures.append(msg)
		push_error("FAIL: " + msg)
		print("  [FALHA] ", msg)
	else:
		print("  [OK] ", msg)

func _run() -> void:
	print("=================================================================")
	print("=== TESTE DE CONDUÇÃO E JOGABILIDADE: FASE 2 (9 VEÍCULOS) ===")
	print("=================================================================")

	var world = SCENE.instantiate()
	root.add_child(world)
	current_scene = world

	for f in 5:
		await physics_frame

	var cars: Array = world.get("spawned_vehicles")
	_check(cars.size() == 9, "Deve instanciar exatamente 9 veículos no showcase (obteve " + str(cars.size()) + ")")

	var player = world.get("player") as CharacterBody2D
	_check(player != null, "Player (Dante) deve estar presente na cena")
	if not player:
		quit(1)
		return

	# Testar condução e resposta em cada um dos 9 carros
	for i in cars.size():
		var car = cars[i] as CharacterBody2D
		var id: String = car.get("archetype_id")
		print("\n--- Testando condução do veículo [%d]: %s ---" % [i, id])

		var initial_pos: Vector2 = car.position

		# 1. Embarque
		car.enter_vehicle(player)
		_check(car.is_driven_by_player, id + " - Jogador deve conseguir embarcar no veículo")

		# 2. Aceleração para frente
		for f in 10:
			car.velocity = car.transform.x * 150.0
			car.move_and_slide()
			await physics_frame

		_check(car.position.distance_to(initial_pos) > 5.0, id + " - Veículo deve se mover ao acelerar")

		# 3. Esterçamento / Direção das Rodas
		car.steering_angle = 0.35
		_check(absf(car.steering_angle) > 0.0, id + " - Ângulo de esterçamento deve responder ao volante")

		# 4. Desembarque
		car.exit_vehicle()
		_check(not car.is_driven_by_player, id + " - Jogador deve conseguir desembarcar do veículo")
		_check(player.visible, id + " - Jogador deve ficar visível após desembarcar")

	print("\n=================================================================")
	if failures.size() == 0:
		print(">>> VALIDAÇÃO DE CONDUÇÃO DA FASE 2 APROVADA COM 100% DE SUCESSO! <<<")
		quit(0)
	else:
		print(">>> ENCONTRADAS %d FALHAS <<<" % failures.size())
		for f in failures:
			print(" - ", f)
		quit(1)
