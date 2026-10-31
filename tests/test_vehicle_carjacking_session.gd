extends SceneTree
## Main real, sem gravar save. As fixtures põem veículos de trânsito ao lado do Dante;
## Driving.interact e motocross.steal_bike executam as transições de produção.
var world: Node3D
var checks := 0
var failures: Array[String] = []
var capture := false
var folder := "res://output/vehicle-jacking-20261010/capture/"

func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); push_error(label)

func shot(label: String) -> void:
	if not capture: return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(folder + label + ".png")

func wait_entry(limit := 14000) -> void:
	var deadline := Time.get_ticks_msec() + limit
	while world.driving.is_body_transition_active() and Time.get_ticks_msec() < deadline: await process_frame
	check(not world.driving.is_body_transition_active(), "boarding completes within its finite deadline")

func run() -> void:
	create_timer(240).timeout.connect(func(): push_error("CARJACKING_SESSION timeout"); quit(2))
	if "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	capture = "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless"
	if capture: DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	for action in InputMap.get_actions(): InputMap.action_erase_events(action)
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	root.add_child(world)
	current_scene = world
	while world.session == null or not world.session.ready_for_play: await process_frame
	check(world.production.no_save,"session uses isolated no-save mode")
	world.gameplay.health = 1000000
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	var pose: Transform3D = world.driving.car.global_transform
	world.driving.car.position += Vector3(15,0,0)
	world.player.teleport(pose.origin + Vector3(12,0,12))
	await physics_frame
	await physics_frame
	world.camera.target_size = 12
	for id in ["sedan_classic","bike_sport"]:
		var car: CharacterBody3D = world.production.spawn_vehicle(id,pose.origin,pose.basis.get_euler().y)
		check(is_instance_valid(car),id + ": fixture spawns on an unobstructed physical surface")
		if not is_instance_valid(car): world.free(); quit(1); return
		car.traffic = true
		world.player.teleport(car.driver_door_anchor(-1) - car.global_basis.x * .15)
		await physics_frame
		check(world.driving.interact(),id + ": real interaction accepts the occupied vehicle")
		if not world.driving.occupied: break
		var body = world.driving.transition
		check(is_instance_valid(body) and body.carjacking != null,id + ": occupied entry owns a forced-removal sequence")
		if not is_instance_valid(body) or body.carjacking == null: break
		var theft = body.carjacking
		var victim = theft.victim
		var captured := false
		var captured_outside := false
		var deadline := Time.get_ticks_msec() + 14000
		while is_instance_valid(body) and body.active and Time.get_ticks_msec() < deadline:
			await process_frame
			if not is_instance_valid(body): break
			if body._extracting and body._extraction_progress > .45 and not captured:
				check(not car.controlled and not world.player.seated,id + ": Dante cannot drive while pulling the original occupant")
				await shot(id + "-pull")
				captured = true
			if body._extracting and body._extraction_progress > .8 and not captured_outside:
				check(victim.is_visible_in_tree(),id + ": displaced driver remains visible during removal")
				await shot(id + "-outside")
				captured_outside = true
		check(captured and theft.released and car.controlled,id + ": forceful removal precedes driver control")
		# Com o arremesso (2026-10-14) a vítima ainda está no voo/no chão quando o Dante senta: espera levantar.
		# O levantar com mocap (28/10) leva 2,7–8 s depois de 1,3 s caída: até 14 s.
		var up_deadline := Time.get_ticks_msec() + 14000
		while is_instance_valid(victim) and victim.has_meta("street_down") and Time.get_ticks_msec() < up_deadline: await process_frame
		check(is_instance_valid(victim) and victim.collision_layer != 0,id + ": displaced driver is a physical actor")
		await shot(id + "-seated")
		check(world.driving.leave(),id + ": exit remains available after theft")
		await wait_entry()
		car.queue_free()
		victim.queue_free()
		world.player.teleport(pose.origin + Vector3(12,0,12))
		await process_frame
		await physics_frame
	# Aborta a pegada em movimento antes que ela possa começar um tween de embarque.
	var bike: CharacterBody3D = world.production.spawn_vehicle("bike_urban",pose.origin,pose.basis.get_euler().y)
	check(is_instance_valid(bike),"moving bike fixture spawns on a clear surface")
	if not is_instance_valid(bike): world.free(); quit(1); return
	bike.traffic = true
	bike.speed = 6
	world.player.teleport(bike.driver_door_anchor(-1))
	check(world.driving.interact(),"moving motorcycle can be grabbed")
	world.driving.cancel_transition("test_cancel")
	check(not world.driving.occupied and world.player.is_physics_processing() and world.player.collision_layer != 0,"cancelled moving theft restores Dante")
	bike.queue_free()
	await process_frame
	# O piloto autoral do motocross precisa continuar no mundo, em vez de ser
	# renomeado Dante no lugar. Usa o percurso físico para apoiar o pouso dele.
	var course := preload("res://activities/motocross/MotocrossCourse.gd")
	world.player.teleport(course.ENTRY + Vector3.UP * .1)
	world.production.region.set_focus(world.player.position)
	var mx = world.session.motocross
	var deadline := Time.get_ticks_msec() + 30000
	while mx.ambient.rows.is_empty() and Time.get_ticks_msec() < deadline: await process_frame
	check(not mx.ambient.rows.is_empty(),"physical motocross park creates riders")
	if not mx.ambient.rows.is_empty():
		var race_bike: CharacterBody3D = mx.ambient.rows[0].bike
		race_bike.race_enabled = false
		race_bike.speed = 0
		world.player.teleport(race_bike.global_position - race_bike.global_basis.x * 1.05)
		await physics_frame
		var original_model: Node3D = race_bike._rider_visual
		check(mx.steal_bike(race_bike),"occupied motocross accepts theft")
		check(mx.stealing and not mx.mounted,"motocross defers mounting until punch and extraction")
		await shot("motocross-start")
		var stop := Time.get_ticks_msec() + 8000
		while mx.stealing and Time.get_ticks_msec() < stop: await process_frame
		check(mx.mounted and not mx.stealing,"motocross mounts Dante after removal")
		check(is_instance_valid(original_model) and original_model != race_bike._rider_visual,"original motocross pilot survives separately with the same presentation")
		await shot("motocross-complete")
		mx.dismount()
	print("VEHICLE_CARJACKING_SESSION checks=",checks," failures=",JSON.stringify(failures))
	world.free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
