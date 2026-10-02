extends SceneTree
## R2: Main real + dano letal na primeira espera física das transações.
## --no-save obrigatório; o executor também deve isolar APPDATA. Sem FPS claim.
## As transações são chamadas diretamente; não testa a aproximação até a porta.
const PLACES = preload("res://world/places/PlaceCatalog.gd")
var world: Node3D
var failures: Array[String] = []
var checks := 0
var injected := false
var death_usec := 0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	print(("R2 PASS " if ok else "R2 FAIL ") + label)
	if not ok: failures.append(label)

func _new_world() -> bool:
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	root.add_child(world)
	current_scene = world
	var deadline := Time.get_ticks_msec() + 60000
	while Time.get_ticks_msec() < deadline:
		await physics_frame
		if world.session != null and world.session.ready_for_play: break
	var ready: bool = world.session != null and world.session.ready_for_play
	check(ready, "sessão real pronta")
	if not ready: return false
	check(world.production.no_save, "persistência pessoal desativada")
	check(world.session.state.place_id.is_empty() and world.session.state.weapons_allowed(), "dano injetado em contexto exterior vulnerável")
	return world.production.no_save and world.session.state.place_id.is_empty() and world.session.state.weapons_allowed()

func _inject_next_physics(label: String) -> void:
	# Registrado antes da coroutine da transação: executa dentro de sua primeira
	# janela await, depois de ela ter capturado o snapshot e adquirido o token.
	var target: Node3D = world
	await physics_frame
	if not is_instance_valid(target) or target.is_queued_for_deletion() or world != target: return
	check(not world.session.transition_kind.is_empty(), label + " atingiu janela de transição")
	if world.session.transition_kind.is_empty(): return
	check(world.session.state.weapons_allowed(), label + " não contorna proteção da garagem")
	death_usec = Time.get_ticks_usec()
	world.gameplay.damage_player(1000.0)
	injected = world.gameplay.health <= 0 and world.session.rescue_pending
	check(injected, label + " dano real iniciou morte e resgate")

func _dead_violations(car: CharacterBody3D) -> Array[String]:
	var found: Array[String] = []
	if world.driving.occupied: found.append("occupied")
	if is_instance_valid(car) and car.controlled: found.append("car.controlled")
	if not world.player.input_locked: found.append("player unlocked")
	if world.player.is_physics_processing(): found.append("player physics")
	if world.player.collision_layer != 0 or world.player.collision_mask != 0: found.append("player collision")
	return found

func _observe_rescue(label: String, car: CharacterBody3D) -> void:
	var violations: Array[String] = []
	var observed_dead_frames := 0
	var deadline := Time.get_ticks_msec() + 10000
	while Time.get_ticks_msec() < deadline:
		if world.gameplay.health <= 0:
			observed_dead_frames += 1
			for violation in _dead_violations(car):
				if not violations.has(violation): violations.append(violation)
		if world.gameplay.health > 0 and not world.session.rescue_pending and not world.session.respawn_busy: break
		await process_frame
	check(observed_dead_frames > 0, label + " observou apresentação de morte")
	check(violations.is_empty(), label + " rollback preservou morto: " + str(violations))
	check(world.gameplay.health > 0 and not world.session.rescue_pending and not world.session.respawn_busy, label + " resgate real concluiu")
	check(not world.driving.occupied and not world.player.input_locked and world.player.is_physics_processing(), label + " controle a pé restaurado")
	check(world.player.collision_layer == 2 and world.player.collision_mask == 7, label + " colisão viva restaurada somente após resgate")
	check(world.session.room == null and world.session.state.place_id.is_empty() and not world.session.is_transition_blocked(), label + " sala candidata e bloqueios liberados")
	print("R2_OBSERVATION ", JSON.stringify({"case": label, "dead_frames": observed_dead_frames, "violations": violations, "rescue_elapsed_ms": (Time.get_ticks_usec() - death_usec) / 1000.0}))

func _case(label: String) -> void:
	if not await _new_world(): return
	var car: CharacterBody3D = world.driving.car
	check(is_instance_valid(car), label + " veículo real disponível")
	if not is_instance_valid(car): return
	if label == "transfer":
		var boarded: bool = await world.session.restore_garage_driver(car)
		check(boarded and world.driving.occupied and car.controlled, "transfer preparação: motorista embarcou fisicamente")
		if not boarded: return
		car.stop_boarding_motion()
	elif label == "enter":
		var definition: Dictionary = PLACES.get_definition("harbor_ammunation")
		var door: Vector3 = definition.return_position + Vector3.UP * .06
		world.production.region.prepare_collision_at(door)
		for index in 3: await physics_frame
		check(world.session.position_clear(door), "enter preparação: porta exterior livre")
		if not world.session.position_clear(door): return
		world.player.teleport(door)
	injected = false
	_inject_next_physics(label)
	var accepted := false
	match label:
		"transfer": accepted = await world.session.transfer_garage_vehicle("maciota", car, true)
		"restore": accepted = await world.session.restore_garage_driver(car)
		"enter": accepted = await world.session.enter_place("harbor_ammunation", false)
	check(injected and not accepted, label + " transação recusada após morte")
	if injected: await _observe_rescue(label, car)

func run() -> void:
	if not "--no-save" in OS.get_cmdline_user_args():
		push_error("R2 exige --no-save e APPDATA temporário do executor")
		quit(2)
		return
	create_timer(240.0).timeout.connect(func(): print("R2 TIMEOUT"); quit(2))
	var cases: Array[String] = ["transfer", "restore", "enter"]
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--case="):
			var selected := argument.trim_prefix("--case=")
			if not cases.has(selected): push_error("Caso R2 desconhecido"); quit(2); return
			cases = [selected]
	for label in cases:
		await _case(label)
		if is_instance_valid(world): world.queue_free()
		await process_frame
		await process_frame
	print("TRANSITION_DEATH_ROLLBACK checks=", checks, " failures=", JSON.stringify(failures))
	quit(0 if failures.is_empty() else 1)
