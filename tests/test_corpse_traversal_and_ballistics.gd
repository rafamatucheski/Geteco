extends SceneTree

var failures: Array[String] = []

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok:
		failures.append(label)

func run() -> void:
	create_timer(30).timeout.connect(func():
		printerr("TEST TIMEOUT")
		quit(2)
	)

	var world := Node2D.new()
	root.add_child(world)
	current_scene = world

	# 1. Validacao de Colisao do Jogador (Caminhar por cima de corpos)
	var player = preload("res://characters/Player.gd").new()
	var cam := Camera2D.new()
	cam.name = "Camera"
	player.add_child(cam)
	player.position = Vector2(0, 0)
	var p_col = CollisionShape2D.new()
	var p_shape = CircleShape2D.new()
	p_shape.radius = 8.0
	p_col.shape = p_shape
	player.add_child(p_col)
	world.add_child(player)

	# Alvo vivo deve bloquear movimento quando o jogador tenta atravessar sua posicao
	var living = preload("res://characters/AnimatedPedestrian3D.gd").new()
	living.position = Vector2(30, 0)
	world.add_child(living)
	await physics_frame
	await physics_frame

	var hit_living = player.test_move(player.global_transform, Vector2(35, 0))
	check(hit_living, "Jogador colide com pedestre vivo no caminho")

	# Pedestre morto NAO deve bloquear movimento
	living._die()
	await physics_frame
	await physics_frame

	check(living.collision_layer == 0, "Pedestre morto tem collision_layer == 0")
	var hit_dead = player.test_move(player.global_transform, Vector2(35, 0))
	check(not hit_dead, "Jogador consegue passar por cima do corpo morto sem colidir")

	living.queue_free()
	await physics_frame

	# Pedestre atropelado em baixa velocidade
	var victim = preload("res://characters/AnimatedPedestrian3D.gd").new()
	victim.position = Vector2(30, 0)
	world.add_child(victim)
	await physics_frame
	await physics_frame
	# Impact speed deve ser >= 35.0 e < 200.0
	victim.get_run_over(Vector2(60, 0), false)
	await physics_frame
	await physics_frame

	print("DEBUG victim: is_incapacitated=", victim.is_incapacitated, " is_dead=", victim.is_dead, " collision_layer=", victim.collision_layer)
	check(victim.is_incapacitated, "Pedestre atropelado em baixa velocidade fica incapacitado")
	check(victim.collision_layer == 0, "Pedestre incapacitado tem collision_layer == 0")
	var hit_incapacitated = player.test_move(player.global_transform, Vector2(35, 0))
	check(not hit_incapacitated, "Jogador consegue passar por cima de pessoa incapacitada no chao")

	victim.queue_free()
	await physics_frame

	# 2. Validacao Balistica (Tiros atravessam corpos caidos no chao)
	var corpse = preload("res://characters/AnimatedPedestrian3D.gd").new()
	corpse.position = Vector2(60, 0)
	world.add_child(corpse)
	await physics_frame
	corpse._die()
	await physics_frame
	await physics_frame

	var living_behind = preload("res://characters/AnimatedPedestrian3D.gd").new()
	living_behind.position = Vector2(140, 0)
	living_behind.health = 100
	world.add_child(living_behind)
	await physics_frame
	await physics_frame

	# Dispara bala em direcao ao alvo vivo que esta ATRAS do corpo morto
	var bullet = preload("res://guns/Bullet.tscn").instantiate()
	bullet.damage = 25
	bullet.speed = 1000.0
	bullet.direction = Vector2.RIGHT
	bullet.position = Vector2(0, 0)
	bullet.owner_body = player
	world.add_child(bullet)
	bullet.set_physics_process(false)
	await physics_frame

	# Avanca o projetil manualmente para cobrir a distancia
	bullet._physics_process(0.2)
	await physics_frame

	check(living_behind.health < 100, "Tiro atravessou o corpo morto e atingiu o alvo vivo atras")
	check(corpse.is_dead, "Corpo morto permaneceu no estado morto")

	corpse.queue_free()
	living_behind.queue_free()
	if is_instance_valid(bullet): bullet.queue_free()
	await physics_frame

	# 3. Validacao Balistica com pessoa incapacitada (no chao aguardando socorro)
	var downed = preload("res://characters/AnimatedPedestrian3D.gd").new()
	downed.position = Vector2(60, 0)
	world.add_child(downed)
	await physics_frame
	await physics_frame
	downed.get_run_over(Vector2(60, 0), false)
	await physics_frame
	await physics_frame

	var second_target = preload("res://characters/AnimatedPedestrian3D.gd").new()
	second_target.position = Vector2(140, 0)
	second_target.health = 100
	world.add_child(second_target)
	await physics_frame
	await physics_frame

	var bullet2 = preload("res://guns/Bullet.tscn").instantiate()
	bullet2.damage = 25
	bullet2.speed = 1000.0
	bullet2.direction = Vector2.RIGHT
	bullet2.position = Vector2(0, 0)
	bullet2.owner_body = player
	world.add_child(bullet2)
	bullet2.set_physics_process(false)
	await physics_frame

	bullet2._physics_process(0.2)
	await physics_frame

	check(second_target.health < 100, "Tiro atravessou a pessoa incapacitada no chao e atingiu o alvo atras")

	downed.queue_free()
	second_target.queue_free()
	if is_instance_valid(bullet2): bullet2.queue_free()
	player.queue_free()
	await physics_frame

	print("\nCORPSE TRAVERSAL AND BALLISTICS: %d failures" % failures.size())
	if failures.is_empty():
		quit(0)
	else:
		quit(1)
