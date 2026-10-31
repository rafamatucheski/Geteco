extends "res://tests/police_response/test_air_k9.gd"

func run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	box(world, "Ground", Vector3(0, -0.2, 0), Vector3(40, 0.4, 40))
	var gameplay := Controller.new()
	world.add_child(gameplay)
	gameplay.player = CharacterBody3D.new()
	body_shape(gameplay.player)
	world.add_child(gameplay.player)
	gameplay.player.position = Vector3(0, 0.04, -1.2)
	gameplay.force = true
	var director := DIRECTOR.new()
	director.configure(gameplay)
	gameplay.add_child(director)
	director.set_physics_process(false)
	var handler := Handler.new()
	world.add_child(handler)
	handler.position = Vector3(3, 0, 0)
	var dog := DOG.new()
	dog.director = director
	dog.handler = handler
	world.add_child(dog)
	dog.set_physics_process(false)
	await frames(2)
	dog._physics_process(0.016)
	check(gameplay.health == 100.0 and dog._attack_time == 0.0, "attack starts with visible preparation and no instant damage")
	dog._physics_process(0.20)
	check(dog._rig.jaw.rotation.x < -0.3 and gameplay.health == 100.0, "jaw opens downward before contact")
	dog._physics_process(0.20)
	check(gameplay.health == 92.0 and gameplay.restraint > 0.0, "jaw contact causes one bite and restraint")
	dog._physics_process(0.1)
	check(gameplay.health == 92.0, "bite cannot repeat damage during recovery")
	dog._cancel_attack()
	dog._attack_time = 0.0
	dog._attack_hit = false
	gameplay.surrender = true
	dog._physics_process(0.4)
	check(gameplay.health == 92.0 and dog._attack_time < 0, "surrender interrupts prepared bite")
	gameplay.surrender = false
	dog._attack_time = 0.0
	dog._attack_hit = false
	gameplay.player.position.z = -4.0
	dog._physics_process(0.4)
	check(gameplay.health == 92.0 and dog._attack_time < 0, "escaping before contact avoids damage")
	dog.position = Vector3.ZERO
	gameplay.player.position = Vector3(0, 0.04, -1.2)
	dog._attack_time = 0.0
	var wall := box(world, "Wall", Vector3(0, 1, -0.65), Vector3(3, 2, 0.1))
	await frames(2)
	dog._physics_process(0.4)
	check(gameplay.health == 92.0 and dog._attack_time < 0, "new cover interrupts bite")
	wall.queue_free()
	await frames(2)
	dog.position = Vector3.ZERO
	dog._attack_time = 0.0
	dog._attack_hit = false
	gameplay.health = 3.0
	dog._physics_process(0.4)
	check(gameplay.health == 1.0, "bite remains nonlethal")
	dog.receive_damage(100.0)
	dog.set_physics_process(false)
	check(dog.dead and dog.visual.rotation.z == 0.0 and not dog.can_bite(gameplay.player), "death disables combat before animated fall")
	dog._physics_process(0.3)
	check(dog.visual.rotation.z > 0.0 and dog.visual.rotation.z < PI * 0.5, "death visibly passes through intermediate pose")
	dog._physics_process(0.6)
	check(is_equal_approx(dog.visual.rotation.z, PI * 0.5) and not dog.is_physics_processing(), "corpse settles and stops animation updates")
	world.queue_free()
	await process_frame
	# Dá tempo ao mixer de áudio para liberar o latido parado antes de o motor sair.
	await create_timer(0.1).timeout
	print("K9_ANIMATION failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
