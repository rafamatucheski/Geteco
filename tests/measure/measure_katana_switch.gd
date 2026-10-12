extends "res://tests/measure/measure_katana_session.gd"
## Real session, thirty seconds alternating draw/holster; no save writes.
func run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args() or DisplayServer.get_name() == "headless":
		quit(2)
		return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("out_dir="): output_dir = arg.trim_prefix("out_dir=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir))
	world = load("res://Main.tscn").instantiate()
	root.add_child(world)
	current_scene = world
	for i in 1200:
		await process_frame
		if world.session != null and world.session.ready_for_play: break
	if world.session == null or not world.session.ready_for_play:
		quit(1)
		return
	gameplay = world.gameplay
	state = world.session.state
	if "--garage-only" in OS.get_cmdline_user_args():
		await verify_garage()
		world.queue_free()
		await process_frame
		quit(0 if failures.is_empty() else 1)
		return
	state.grant_weapon("katana")
	state.equip_weapon("fists")
	gameplay.god_mode = true
	var warm := Time.get_ticks_usec()
	while Time.get_ticks_usec() - warm < 8000000: await process_frame
	var samples: Array[float] = []
	var start := Time.get_ticks_usec()
	var last := start
	var next_switch := 0.0
	var draw := true
	while Time.get_ticks_usec() - start < 30000000:
		await process_frame
		var now := Time.get_ticks_usec()
		var elapsed := float(now - start) / 1000000.0
		samples.append(float(now - last) / 1000.0)
		last = now
		if elapsed >= next_switch:
			state.equip_weapon("katana" if draw else "fists")
			draw = not draw
			next_switch += 2.0
	var summary := summarize(samples)
	summary.merge({"gpu": RenderingServer.get_video_adapter_name(), "renderer": RenderingServer.get_current_rendering_method(), "viewport": str(root.size), "vsync": DisplayServer.window_get_vsync_mode(), "max_fps": Engine.max_fps})
	FileAccess.open(output_dir.path_join("measure.json"), FileAccess.WRITE).store_string(JSON.stringify(summary, "\t"))
	var compact := summary.duplicate()
	compact.erase("samples_ms")
	print("KATANA_SWITCH_MEASURE ", compact)
	# Temporal evidence is separate from frame-time measurement.
	var detail := Camera3D.new()
	world.add_child(detail)
	detail.look_at_from_position(world.player.global_position + Vector3(2.2, 1.6, 2.2), world.player.global_position + Vector3.UP)
	detail.make_current()
	state.equip_weapon("fists")
	await frames(100)
	var pictures: Array[Image] = []
	var labels: Array[String] = []
	var poses: Array[Dictionary] = []
	for weapon in ["katana", "fists"]:
		state.equip_weapon(weapon)
		var switched_at := Time.get_ticks_usec()
		for frame in 24:
			await physics_frame
			await RenderingServer.frame_post_draw
			pictures.append(root.get_texture().get_image())
			labels.append("%s_%02d" % [weapon, frame])
			poses.append({"frame": labels[-1], "wall_seconds": float(Time.get_ticks_usec() - switched_at) / 1000000.0, "clip": gameplay._sheath_clip, "age": gameplay._sheath_age, "back_visible": gameplay.back_katana.visible, "hand_visible": gameplay.hand_katana.visible, "gun_visible": gameplay.gun.visible})
	for index in pictures.size(): pictures[index].save_png(output_dir.path_join(labels[index] + ".png"))
	FileAccess.open(output_dir.path_join("poses.json"), FileAccess.WRITE).store_string(JSON.stringify(poses, "\t"))
	if "--check-garage" in OS.get_cmdline_user_args(): await verify_garage()
	world.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

func verify_garage() -> void:
	var player = world.player
	gameplay.god_mode = false
	gameplay._sync_god_mode()
	# A bare grant marks takeshi_honor discovered but lacks its save contract.
	# Use the real award API before exercising restore, even for an owned sword.
	preload("res://runtime/TakeshiHonor.gd").record_finish(state.world_state, true, 8.0)
	check(preload("res://runtime/TakeshiHonor.gd").claim_state(state, "katana").ok, "fixture recebe katana pelo prêmio persistente de Takeshi")
	state.grant_weapon("pistol")
	state.equip_weapon("fists")
	await frames(20)
	check(state.equip_weapon("katana"), "katana disponível antes de entrar")
	await frames(2)
	check(gameplay._sheath_clip != "", "saque em andamento antes da transição")
	var entered: bool = await world.session.enter_place("maciota", false)
	for frame in 240:
		await physics_frame
		if state.place_id == "maciota" and not world.session.is_transition_blocked(): break
	await frames(10)
	check(entered and state.place_id == "maciota", "entrada real na garagem")
	check(state.equipped_weapon == "fists" and gameplay._sheath_clip == "" and not gameplay.hand_katana.visible, "entrada guarda katana e cancela animação em andamento")
	check(not state.equip_weapon("katana") and not gameplay.equip_slot("katana") and not gameplay.cycle_weapon(1), "garagem bloqueia saque e troca da katana")
	check(not gameplay.attack_allowed() and not gameplay.fire_at(player.global_position + Vector3.FORWARD), "garagem bloqueia disparo e corpo a corpo")
	var hp: float = gameplay.health
	gameplay.explode(player.global_position, 4.0, 90.0, player)
	check(gameplay.health == hp, "garagem bloqueia explosivo do jogador")
	check(state.owns_weapon("katana") and state.owns_weapon("pistol"), "inventário preservado na entrada")
	for person in [world.maciota_place.maciota, world.maciota_place.mechanic]:
		var body := person.get_node("ResidentBody") as StaticBody3D
		gameplay._damage(body, 500.0, player)
		gameplay._damage(person, 500.0, player)
		gameplay.explode(body.global_position, 3.0, 500.0, player)
		check(is_instance_valid(person) and person.get_meta("invulnerable", false) and preload("res://gameplay/DamageProtection.gd").is_protected(body), "%s permanece protegido" % person.name)
	var snapshot: Dictionary = state.snapshot()
	snapshot.economy.equipped_weapon = "pistol"
	var restored: bool = state.restore_snapshot(snapshot)
	if not restored:
		FileAccess.open(output_dir.path_join("garage_snapshot_rejected.json"), FileAccess.WRITE).store_string(JSON.stringify(snapshot, "\t"))
		print("GARAGE_RESTORE rejected; economy_valid=", preload("res://systems/economy/Economy.gd").new().restore_snapshot(snapshot.economy))
	check(restored and state.equipped_weapon == "fists" and state.owns_weapon("katana"), "restore na garagem guarda arma e preserva katana")
	var left: bool = await world.session.leave_place()
	for frame in 240:
		await physics_frame
		if state.place_id == "" and not world.session.is_transition_blocked(): break
	await frames(10)
	check(left and gameplay.attack_allowed() and state.equip_weapon("katana"), "saída libera katana preservada")
	await frames(20)
	check(gameplay._sheath_clip == "" and not gameplay.back_katana.visible and not gameplay.hand_katana.visible and gameplay.gun.visible, "saque após saída termina e entrega arma de combate")
	print("KATANA_GARAGE checks=", checks, " failures=", failures)
