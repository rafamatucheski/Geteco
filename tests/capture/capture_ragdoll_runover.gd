extends SceneTree
## Atropelamento no jogo de verdade (2026-10-19): um sedã acelera contra um pedestre e a câmera segue o
## corpo, para revisar o ragdoll (BodyRagdoll3D) contra o voo antigo. Com tela (nunca --headless):
##   "$GODOT" --path . --script res://tests/capture/capture_ragdoll_runover.gd -- --no-save --label=ragdoll [--speed=14]
## Antes: GETECO_RAGDOLL=0 com --label=antes. PNG em evidence/ragdoll/ (fora do Git).
const ACTOR := preload("res://scripts/Actor.gd")
var world: Node3D
var focus: Node3D

func _initialize() -> void: run.call_deferred()

func shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var camera := root.get_camera_3d()
	if is_instance_valid(focus) and camera != null:
		var scale := Vector2(image.get_size()) / root.get_visible_rect().size
		var center := camera.unproject_position(focus.global_position + Vector3.UP * .5) * scale
		var size := Vector2i(560, 420)
		var origin := Vector2i(clampi(int(center.x) - size.x / 2, 0, image.get_width() - size.x), clampi(int(center.y) - size.y / 2, 0, image.get_height() - size.y))
		image = image.get_region(Rect2i(origin, size))
	image.save_png(ProjectSettings.globalize_path(path))

func run() -> void:
	var label := "ragdoll"
	var speed := 14.0
	var away := 1.0
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--label="): label = argument.trim_prefix("--label=")
		if argument.begins_with("--speed="): speed = float(argument.trim_prefix("--speed="))
		if argument == "--back": away = -1.0
	var folder := "res://evidence/ragdoll"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	for action in InputMap.get_actions(): InputMap.action_erase_events(action)
	DisplayServer.window_set_size(Vector2i(1280, 720))
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	root.add_child(world)
	current_scene = world
	while world.session == null or not world.session.ready_for_play: await process_frame
	world.gameplay.health = 1000000
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	world.session.weather.time_of_day = .5
	# O impacto é o mesmo do atropelamento (BodyFlight3D.launch com o diretor de rua e o carro como fonte), mas
	# disparado direto: dirigir o carro por script parava o carro e o pedestre nascia fora da colisão do chão.
	var car: CharacterBody3D = world.driving.car
	var forward: Vector3 = -world.player.global_basis.z.normalized()
	forward.y = 0
	forward = forward.normalized() * away
	var walker := ACTOR.new()
	walker.controlled_automatically = true
	world.add_child(walker)
	walker.teleport(world.player.global_position + world.player.global_basis.x * 3.0 + Vector3.UP * .05)
	world.player.teleport(world.player.global_position - world.player.global_basis.x * 3.0)
	for frame in 40: await physics_frame
	print("  pedestre no chão ", walker.is_on_floor(), " em ", walker.global_position)
	var director: Node = null
	for node in world.find_children("*", "Node", true, false):
		if node.has_method("on_body_landed") and node.has_method("vehicle_pre_move"):
			director = node
			break
	# A origem do ator só acompanha o corpo ao assentar: a câmera segue a pelve.
	var pelvis: Node3D = preload("res://gameplay/street_physics/BodyRagdoll3D.gd").find_model(walker.visual).pelvis
	world.camera.target = pelvis
	world.camera.target_size = 8
	focus = pelvis
	Engine.time_scale = .25
	for frame in 3: await shot("%s/%s_pre_%d.png" % [folder, label, frame])
	var flight = preload("res://gameplay/street_physics/BodyFlight3D.gd").launch(walker, forward * speed, speed >= 12.5, director, car, true)
	print("  ragdoll ", flight != null and flight.ragdoll != null, " diretor ", director)
	var index := 0
	var last := -1000
	var hit_at := Time.get_ticks_msec()
	while Time.get_ticks_msec() - hit_at < 18000:
		await process_frame
		if Time.get_ticks_msec() - last < 120: continue
		last = Time.get_ticks_msec()
		await shot("%s/%s_%02d.png" % [folder, label, index])
		index += 1
		if not walker.has_meta("street_flying") and Time.get_ticks_msec() - hit_at > 6000: break
	if not walker.dead and walker.has_method("recover_from_injury"):
		walker.recover_from_injury()
		for frame in 8:
			await create_timer(.25 * .25).timeout
			await shot("%s/%s_up_%d.png" % [folder, label, frame])
	print("RAGDOLL_CAPTURE label=", label, " quadros=", index, " morto=", walker.dead)
	Engine.time_scale = 1.0
	quit(0)
