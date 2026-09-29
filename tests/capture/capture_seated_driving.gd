extends SceneTree
## Captura renderizada (NÃO headless) do fluxo real: Main.tscn, o jogador entra num veículo
## de cada porte pela animação de embarque de verdade, dirige e sai. Mostra o motorista
## sentado na câmera do jogo, e confirma que ele volta ao normal depois da saída.
## Uso: --script res://tests/capture/capture_seated_driving.gd -- --no-save [ids,separados,por,virgula]
## Saída em res://evidence/seated-driver/ (PNG fica fora do Git).
const OUTPUT := "res://evidence/seated-driver/"
const INTERIOR := preload("res://gameplay/VehicleInterior.gd")
var world
var failures: Array[String] = []

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	print("SEATED_MAIN ", "PASS " if ok else "FAIL ", label)
	if not ok: failures.append(label)

func capture(label: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path(OUTPUT + label + ".png"))

func run() -> void:
	if not "--no-save" in OS.get_cmdline_user_args():
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	var ids: Array = ["union_sedan", "ranch_pickup", "american_dump_truck", "route_city", "beach_buggy", "port_forklift"]
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
		var door: Vector3 = car.driver_door_anchor(side)
		world.player.teleport(door + car.global_basis.x * float(side) * .45)
		world.camera.target = world.player
		await create_timer(.4).timeout
		var started: bool = driving.interact(true)
		check(started, id + " embarque aceito")
		var meio := false
		var last_hips := Vector3.INF
		var max_jump := 0.0
		var jump_at := ""
		var settled := 0
		for i in 400:
			await physics_frame
			var hips_now: Vector3 = world.player.skeleton.to_global(world.player.skeleton.get_bone_global_pose(world.player.hips).origin)
			if last_hips.is_finite() and world.player.visible and driving.transition != null and driving.transition.progress > .6 or (last_hips.is_finite() and driving.occupied and driving.transition == null and settled < 40):
				var jump := hips_now.distance_to(last_hips)
				if jump > max_jump:
					max_jump = jump
					jump_at = "frame %d transicao=%s" % [i, str(driving.transition != null)]
			last_hips = hips_now
			if driving.occupied and driving.transition == null: settled += 1
			if "--mid" in OS.get_cmdline_user_args() and not meio and driving.is_body_transition_active() and driving.transition != null and driving.transition.progress > .5:
				meio = true
				await capture(id + "_entrada_meio")
			if driving.occupied and not driving.is_body_transition_active(): break
		check(driving.occupied and driving.car == car, id + " terminou ao volante")
		print("SEATED_MAIN salto maximo do quadril por quadro na entrada: %.3f m (%s)" % [max_jump, jump_at])
		check(world.player.visible and world.player.seated, id + " piloto visível e sentado")
		world.camera.target_size = 12.0
		await create_timer(1.2).timeout
		await capture(id + "_dirigindo_parado")
		car.external_input = true
		car.throttle_input = 1.0
		car.brake_input = false
		await create_timer(1.6).timeout
		await capture(id + "_dirigindo_andando")
		# O corpo acompanha o carro em movimento: distância ao ponto esperado do banco.
		var state: Dictionary = world.player.get_meta("seated_state", {})
		if not state.is_empty():
			var expected: Vector3 = (car.global_transform * Transform3D(Basis.IDENTITY, state.origin)).origin
			var gap: float = world.player.visual.global_position.distance_to(expected)
			check(world.player.global_position.distance_to(car.global_position) < .001, id + " world.player.position segue igual à posição do carro")
			check(gap < .05, id + " piloto colado ao banco em movimento (%.3f m)" % gap)
		car.throttle_input = 0
		car.brake_input = true
		car.external_input = false
		for i in 240:
			await physics_frame
			if absf(car.speed) < .3: break
		car.speed = 0
		var seated_pelvis: Vector3 = INTERIOR.pelvis_world(world.player)
		var left: bool = driving.leave()
		check(left, id + " saída aceita")
		var quarter := false
		var exit_jump := 0.0
		var exit_first := -1.0
		var last_exit_hips := seated_pelvis
		var exit_frames: Array = []
		for i in 400:
			await physics_frame
			if driving.transition != null and i < 45:
				var now_hips: Vector3 = INTERIOR.pelvis_world(world.player)
				if exit_first < 0.0: exit_first = now_hips.distance_to(last_exit_hips)
				exit_frames.append(snappedf(now_hips.distance_to(last_exit_hips), .001))
				exit_jump = maxf(exit_jump, now_hips.distance_to(last_exit_hips))
				last_exit_hips = now_hips
			if "--mid" in OS.get_cmdline_user_args() and not quarter and driving.is_body_transition_active() and driving.transition != null and driving.transition.exiting and driving.transition.progress < .45:
				quarter = true
				await capture(id + "_saida_meio")
			if not driving.occupied and not driving.is_body_transition_active(): break
		print("SEATED_MAIN saida: salto do primeiro quadro %.3f m | maximo nos primeiros 45 quadros %.3f m | primeiros 14 quadros: %s" % [exit_first, exit_jump, str(exit_frames.slice(0, 14))])
		check(not driving.occupied and world.player.visible and not world.player.seated, id + " voltou a pé, visível")
		check(world.player.visual.position.is_equal_approx(baseline_visual) and world.player.visual.scale.is_equal_approx(Vector3.ONE), id + " sem visual deslocado nem escalado")
		check(world.player.global_basis.is_equal_approx(Basis.IDENTITY), id + " corpo de pé")
		await create_timer(.5).timeout
		if is_instance_valid(car): car.queue_free()
		await process_frame
	print("SEATED_MAIN_RESULT failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
