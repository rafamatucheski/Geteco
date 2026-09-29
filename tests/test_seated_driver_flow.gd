extends SceneTree
## Fluxo real (Main.tscn, apresentação de embarque de verdade) do motorista sentado, um veículo
## de cada porte: entra pela porta/degrau, chega ao volante VISÍVEL e sentado, acompanha o carro
## em movimento, sai pelo caminho de saída e volta a pé sem resíduo (visual deslocado, escalado,
## agachado, corpo inclinado). Mede também a continuidade: o quadril não salta na passagem da
## animação de entrada para o banco nem do banco para a animação de saída.
## Complementa tests/test_seated_driver.gd (que cobre a frota inteira sem a apresentação).
## NÃO mede aparência (tests/capture/capture_seated_driving.gd) nem custo de quadro.
const INTERIOR := preload("res://gameplay/VehicleInterior.gd")
## Salto de quadril tolerado por quadro nos quadros seguintes à entrada e nos primeiros da saída:
## a própria animação anda até ~0,2 m por quadro; um estalo de pose seria de 0,3 m ou mais.
const MAX_HANDOFF_JUMP := 0.22
var world
var checks := 0
var failures: Array[String] = []

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		print("SEATED_FLOW FAIL ", label)

func run() -> void:
	if not "--no-save" in OS.get_cmdline_user_args():
		quit(2)
		return
	var ids: Array = ["union_sedan", "sport_coupe", "ranch_pickup", "american_dump_truck", "route_city", "dune_buggy", "port_forklift"]
	for argument in OS.get_cmdline_user_args():
		if not argument.begins_with("--"): ids = argument.split(",")
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	root.add_child(world)
	current_scene = world
	for i in 1500:
		await process_frame
		if world.session != null and world.session.ready_for_play: break
	var controller = world.session.controller
	controller.set_population(0)
	var driving = world.driving
	var baseline_visual: Vector3 = world.player.visual.position
	for id in ids:
		var car = null
		for offset in [Vector3(20, 0, 0), Vector3(-25, 0, 10), Vector3(0, 0, 30), Vector3(35, 0, -20), Vector3(-40, 0, -30), Vector3(50, 0, 40)]:
			var road: Vector3 = controller.nearest_road(world.player.global_position + offset)
			car = controller.spawn_vehicle(id, road + Vector3.UP * .12, controller.road_yaw(road))
			if car != null: break
		check(car != null, id + " nasceu")
		if car == null: continue
		car.traffic = false
		for i in 20: await physics_frame
		var side: int = int(car.boarding_sides()[0])
		world.player.teleport(car.driver_door_anchor(side) + car.global_basis.x * float(side) * .45)
		await create_timer(.3).timeout
		check(driving.interact(true), id + " embarque aceito")
		var last_hips := Vector3.INF
		var settled_frames := 0
		var entry_jump := 0.0
		for i in 600:
			await physics_frame
			var hips: Vector3 = INTERIOR.pelvis_world(world.player)
			if driving.transition == null and driving.occupied: settled_frames += 1
			# Só a passagem para o banco e os quadros seguintes (a animação em si tem o ritmo dela).
			if last_hips.is_finite() and driving.occupied and driving.transition == null and settled_frames <= 40:
				entry_jump = maxf(entry_jump, hips.distance_to(last_hips))
			last_hips = hips
			if settled_frames > 40: break
		check(driving.occupied and driving.car == car and not driving.is_body_transition_active(), id + " terminou ao volante")
		check(world.player.visible and world.player.seated, id + " piloto visível e sentado ao terminar a entrada")
		check(entry_jump < MAX_HANDOFF_JUMP, id + " sem estalo na passagem para o banco (%.3f m/quadro)" % entry_jump)
		check(world.player.global_position.distance_to(car.global_position) < .001, id + " world.player.position segue a posição do carro")
		car.external_input = true
		car.throttle_input = 1.0
		car.brake_input = false
		await create_timer(1.2).timeout
		var state: Dictionary = world.player.get_meta("seated_state", {})
		if not state.is_empty():
			var expected: Vector3 = (car.global_transform * Transform3D(Basis.IDENTITY, state.origin)).origin
			check(world.player.visual.global_position.distance_to(expected) < .05, id + " piloto colado ao banco em movimento")
			check(world.player.global_position.distance_to(car.global_position) < .001, id + " nó do jogador na posição do carro em movimento")
		else:
			check(false, id + " estado de sentado existe")
		car.throttle_input = 0
		car.brake_input = true
		car.external_input = false
		for i in 300:
			await physics_frame
			if absf(car.speed) < .3: break
		car.speed = 0
		var seated_pelvis: Vector3 = INTERIOR.pelvis_world(world.player)
		check(driving.leave(), id + " saída aceita")
		var exit_first := -1.0
		var exit_jump := 0.0
		var last_exit := seated_pelvis
		for i in 600:
			await physics_frame
			if driving.transition != null and i < 45:
				var now: Vector3 = INTERIOR.pelvis_world(world.player)
				if exit_first < 0.0: exit_first = now.distance_to(last_exit)
				exit_jump = maxf(exit_jump, now.distance_to(last_exit))
				last_exit = now
			if not driving.occupied and not driving.is_body_transition_active(): break
		check(exit_first < .1, id + " a saída começa sentado, sem estalo (primeiro quadro %.3f m)" % exit_first)
		check(exit_jump < MAX_HANDOFF_JUMP, id + " sem estalo nos primeiros quadros da saída (%.3f m/quadro)" % exit_jump)
		check(not driving.occupied and world.player.visible and not world.player.seated, id + " voltou a pé, visível")
		check(world.player.visual.position.is_equal_approx(baseline_visual) and world.player.visual.scale.is_equal_approx(Vector3.ONE) and world.player.visual.rotation.x == 0.0 and world.player.visual.rotation.z == 0.0, id + " sem visual deslocado, escalado ou inclinado")
		check(world.player.global_basis.is_equal_approx(Basis.IDENTITY), id + " corpo de pé")
		check(world.player.get_meta("seated_state", {}).is_empty(), id + " estado de sentado limpo")
		await create_timer(.3).timeout
		if is_instance_valid(car): car.queue_free()
		await process_frame
	print("SEATED_FLOW checks=", checks, " vehicles=", ids.size(), " failures=", failures.size())
	if failures.is_empty(): print("PASS test_seated_driver_flow")
	else: print("FAIL test_seated_driver_flow: ", failures.size())
	quit(0 if failures.is_empty() else 1)
