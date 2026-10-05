extends SceneTree
## Main real: fogo, desembarque pela porta/salto, fuga física e explosão.
## Rodar com --no-save; --capture-dir=/caminho habilita fotos no jogo renderizado.
var world
var failures: Array[String] = []
var checks := 0
var completed_cases := 0
var capture_dir := ""

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)

func frames(count: int) -> void:
	for frame in count: await physics_frame

func shot(label: String) -> void:
	if capture_dir.is_empty() or DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(capture_dir.path_join(label + ".png"))

func wait_transition() -> bool:
	var deadline := Time.get_ticks_msec() + 6000
	while world.driving.is_body_transition_active() and Time.get_ticks_msec() < deadline:
		await physics_frame
	return not world.driving.is_body_transition_active()

func road_pose(car: CharacterBody3D) -> Transform3D:
	var route: Curve3D = world.production.traffic_routes.route_near(car.position)
	if route == null: return Transform3D.IDENTITY
	var offset := route.get_closest_offset(car.position)
	for attempt in 16:
		var distance := fposmod(offset + attempt * 6, route.get_baked_length())
		var point := route.sample_baked(distance, true) + Vector3.UP * .12
		var forward := route.sample_baked(minf(distance + 1, route.get_baked_length()), true) - point
		forward.y = 0
		forward = forward.normalized()
		var yaw := atan2(-forward.x, -forward.z)
		var clear := true
		for step in 6:
			var candidate := point + forward * step * 5
			# A explosão do caso anterior deixa fogo real no chão por quinze
			# segundos. O próximo caso precisa começar fora desse dano adicional.
			for fire: Node3D in get_nodes_in_group("ground_fire"):
				if fire.global_position.distance_to(candidate) < 5:
					clear = false
					break
			if not clear or not world.production.vehicle_position_clear(car, candidate, yaw):
				clear = false
				break
		if clear: return Transform3D(Basis(Vector3.UP, yaw), point)
	return Transform3D.IDENTITY

func escape_case(speed: float, ratio: float) -> void:
	var car: CharacterBody3D = world.driving.car
	car.repair()
	car.traffic = false
	var pose := road_pose(car)
	check(pose != Transform3D.IDENTITY, "clear road for fire escape at speed %s" % speed)
	if pose == Transform3D.IDENTITY: return
	car.place(pose.origin, pose.basis.get_euler().y)
	world.player.speed = 0
	world.player.automatic_direction = Vector3.ZERO
	await frames(3)
	var entered := false
	for side in [-1, 1]:
		var approach: Vector3 = car.driver_door_anchor(side) + car.global_basis.x * side * .35
		if not world.session.position_clear(approach): continue
		world.player.teleport(approach)
		await frames(2)
		if world.driving.interact():
			entered = true
			break
	check(entered and await wait_transition(), "real boarding completes before fire")
	if not entered or not world.driving.occupied: return
	car.external_input = true
	car.throttle_input = 0
	car.speed = speed
	car.horizontal_velocity = -car.global_basis.z * speed
	car.receive_damage((car.health - car.max_health * ratio) / car.damage_resistance)
	check(car.damage_look.burning, "collision damage starts engine fire")
	var started_frame := Engine.get_physics_frames()
	var explosions := [0]
	var extra_hits := [0]
	var burn_tick: float = car.health / (10.0 * Engine.physics_ticks_per_second)
	var damage_observer := func(amount: float):
		if amount > burn_tick * 1.1:
			extra_hits[0] += 1
			print("FIRE_ESCAPE_EXTRA_DAMAGE amount=", amount, " frame=", Engine.get_physics_frames() - started_frame, " position=", car.global_position)
	car.damaged.connect(damage_observer)
	var observer := func(_point: Vector3, _radius: float, source: Node3D):
		if source == car: explosions[0] += 1
	world.gameplay.explosion_occurred.connect(observer)
	await shot("fire-%s" % int(speed))
	await frames(60) # Um segundo para perceber o fogo e pedir a saída.
	check(car.health > 0 and world.gameplay.health > 0, "occupant survives reaction time")
	var admitted: bool = world.driving.leave()
	check(admitted, "burning vehicle allows dismount at speed %s" % speed)
	if not admitted:
		world.gameplay.explosion_occurred.disconnect(observer)
		car.damaged.disconnect(damage_observer)
		return
	check(await wait_transition(), "fire dismount finishes")
	check(not world.driving.occupied and not world.player.input_locked and world.player.is_physics_processing(), "walking controls return before explosion")
	await shot("outside-%s" % int(speed))
	var outward: Vector3 = world.player.global_position - car.global_position
	outward.y = 0
	world.player.automatic_direction = outward.normalized()
	world.player.speed = 3.5 # Caminhada normal já deve permitir escapar.
	while car.health > 0 and Engine.get_physics_frames() - started_frame < 720:
		await physics_frame
		if world.player.global_position.distance_to(car.global_position) > 9:
			world.player.automatic_direction = Vector3.ZERO
	world.player.automatic_direction = Vector3.ZERO
	var elapsed := float(Engine.get_physics_frames() - started_frame) / Engine.physics_ticks_per_second
	var distance: float = world.player.global_position.distance_to(car.global_position)
	check(car.health <= 0 and explosions[0] == 1, "engine fire still produces one real explosion")
	check(extra_hits[0] == 0, "normal fire escape route receives no additional damage")
	check(elapsed >= 9.9 and elapsed <= 10.1, "fire grants ten seconds in the real scene: %s" % elapsed)
	check(distance > 5.0 and world.gameplay.health >= 80, "player escapes the blast radius alive: distance=%s health=%s" % [distance, world.gameplay.health])
	print("FIRE_ESCAPE speed=", speed, " ratio=", ratio, " seconds=", elapsed, " distance=", distance, " health=", world.gameplay.health, " explosions=", explosions[0], " extra_hits=", extra_hits[0])
	await shot("escaped-%s" % int(speed))
	world.gameplay.explosion_occurred.disconnect(observer)
	car.damaged.disconnect(damage_observer)
	await frames(3)
	completed_cases += 1

func run() -> void:
	if not "--no-save" in OS.get_cmdline_user_args(): quit(2); return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="): capture_dir = arg.trim_prefix("--capture-dir=")
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	root.add_child(world)
	current_scene = world
	var deadline := Time.get_ticks_msec() + 60000
	while Time.get_ticks_msec() < deadline:
		await physics_frame
		if world.session != null and world.session.ready_for_play: break
	check(world.session != null and world.session.ready_for_play, "native session starts")
	if not failures.is_empty(): world.free(); quit(1); return
	check(world.production.no_save, "test preserves personal saves")
	world.player.controlled_automatically = true
	world.driving.set_process_unhandled_input(false)
	world.camera.set_process_unhandled_input(false)
	# Use o spawner de produção, que instala os callbacks reais de explosão
	# e emergência; o veículo provisório de Driving só observa o ocupante.
	var original: CharacterBody3D = world.driving.car
	var pose := road_pose(original)
	check(pose != Transform3D.IDENTITY, "production escape vehicle has an admitted road pose")
	if pose == Transform3D.IDENTITY: world.free(); quit(1); return
	original.queue_free()
	await frames(2)
	var car: CharacterBody3D = world.production.spawn_vehicle("sport_coupe", pose.origin, pose.basis.get_euler().y)
	check(is_instance_valid(car), "production escape vehicle materializes")
	if not is_instance_valid(car): world.free(); quit(1); return
	world.driving.car = car
	world.driving._watch_car(car)
	await escape_case(0.0, .01)
	if failures.is_empty(): await escape_case(9.0, .15)
	check(completed_cases == 2, "both stopped and moving fire escape cases completed")
	world.free()
	await process_frame
	print("VEHICLE_FIRE_ESCAPE checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
