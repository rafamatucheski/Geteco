extends SceneTree
## Câmera no Túnel do canal, no Main.tscn real (renderizado, nunca headless): ao descer, a
## visão passa a perspectiva atrás do veículo, com teto sólido; ao
## voltar à rua tudo se desfaz (sem nó apagado sobrando, inclinação original).
## Uso: "$GODOT" --path . --script res://tests/test_tunnel_camera.gd -- --no-save --output=<pasta nova>
const TUNNEL := preload("res://world/urban_detail/CanalTunnel3D.gd")
var failures: Array[String] = []
var output := ""

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		push_error(label)

func pitch_degrees(camera: Camera3D) -> float:
	return rad_to_deg(asin(clampf(-(-camera.global_basis.z).y, -1.0, 1.0)))

func settle(world: Node, seconds: float) -> void:
	# Camera blends advance by delta. A fixed number of draw frames at 400 FPS
	# used to assert before boarding and the camera's physical transition ended.
	var deadline := Time.get_ticks_usec() + int(seconds * 1000000.0)
	while Time.get_ticks_usec() < deadline and is_instance_valid(world):
		await physics_frame
		await process_frame

func wait_body_state(world: Node, occupied: bool) -> bool:
	var deadline := Time.get_ticks_msec() + 10000
	while Time.get_ticks_msec() < deadline:
		await physics_frame
		if not world.driving.is_body_transition_active() and world.driving.occupied == occupied:
			return true
	check(false, "Transição física de embarque/desembarque conclui em 10 s (occupied=%s)" % occupied)
	return false

func wait_ground(world: Node, point: Vector3) -> bool:
	world.production._update_physical_residency(point)
	world.production._update_logical_region(point)
	world.production.region.set_focus(point)
	var deadline := Time.get_ticks_msec() + 15000
	while Time.get_ticks_msec() < deadline:
		await physics_frame
		if world.production.region.pending.is_empty() and world.production.region.build_jobs.is_empty(): return true
	check(false, "Streaming da fixture termina antes do teste de câmera")
	return false

func run() -> void:
	var args := OS.get_cmdline_user_args()
	if DisplayServer.get_name() == "headless" or "--no-save" not in args:
		quit(2)
		return
	for arg in args:
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
	if output.is_empty(): output = OS.get_temp_dir().path_join("geteco-tunnel-camera-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()])
	output = ProjectSettings.globalize_path(output)
	if FileAccess.file_exists(output.path_join("after-east.png")) or DirAccess.make_dir_recursive_absolute(output) != OK:
		push_error("TUNNEL_CAMERA needs a writable, unused capture directory: " + output)
		quit(2)
		return
	seed(28092026)
	var world: Variant = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	root.add_child(world)
	current_scene = world
	var startup_deadline := Time.get_ticks_msec() + 120000
	var ready := false
	while Time.get_ticks_msec() < startup_deadline:
		await process_frame
		if world.production != null and world.production.ready_for_play and world.production.startup_streaming_settled and world.session != null and world.session.ready_for_play and world.session.weather != null:
			ready = true
			break
	check(ready, "Main e sessão ficam prontos, com streaming de startup completo")
	if not ready:
		await finish(world)
		return
	check(world.production.no_save, "Fixture não grava save pessoal")
	var intro: Dictionary = world.session.state.intro.snapshot()
	intro.phase = "complete"
	intro.location_id = "harbor_street"
	intro.inventory = {}
	intro.completed_missions = [preload("res://data/GarageSequence.gd").ID]
	var intro_ready: bool = world.session.state.intro.restore_snapshot(intro)
	check(intro_ready, "Runtime aceita fixture de introdução concluída")
	if not intro_ready or not world.production.no_save:
		await finish(world)
		return
	for action in InputMap.get_actions(): InputMap.action_erase_events(action)
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	var camera: Camera3D = world.camera
	camera.set_process_unhandled_input(false)
	var car: CharacterBody3D = world.driving.car
	# Board the production-admitted starter parking pose. x=160 is already on
	# the canal ramp (below y=0), so the former fixture began above its floor.
	if not await wait_ground(world, car.global_position):
		await finish(world)
		return
	var entered := false
	for side in [-1, 1]:
		var door: Vector3 = car.driver_door_anchor(side)
		if not world.session.position_clear(door): continue
		world.player.teleport(door)
		await settle(world, .15)
		if world.driving.interact():
			entered = true
			break
	check(entered, "Embarque real aceito no carro em piso admitido")
	if not entered or not await wait_body_state(world, true):
		await finish(world)
		return
	check(camera.target == car and car.controlled, "Embarque completo transfere controle e câmera ao carro")
	if camera.target != car or not car.controlled:
		await finish(world)
		return
	car.set_external_driver(true)
	car.throttle_input = 0.0
	car.steer_input = 0.0
	car.brake_input = true
	var street := Vector3(141.0, 0.12, 63.0)
	car.place(street, -PI * 0.5)
	if not await wait_ground(world, street):
		await finish(world)
		return
	await settle(world, 3.0)
	check(camera._tunnel_blend == 0.0, "Fora do túnel a mistura é zero")
	# A inclinação de rua depende da opção de câmera; dirigindo é a câmera de direção (58°),
	# ainda bem abaixo dos ~70° do túnel.
	var street_pitch := pitch_degrees(camera)
	check(street_pitch < 62.0, "Fora do túnel a inclinação é a de rua (%.1f)" % street_pitch)
	check(camera._cutaway.faded_count() == 0, "Fora do túnel nada é apagado")
	var size_outside := camera.size

	# Sob o cais: fundo do túnel.
	var deep := Vector3(190.0, TUNNEL.floor_y(190.0) + 0.12, 63.0)
	world.production._update_physical_residency(deep)
	car.place(deep, -PI * 0.5)
	await settle(world, 4.0)
	check(camera._tunnel_blend > 0.99, "No fundo a mistura chega a 1 (%.2f)" % camera._tunnel_blend)
	check(camera.projection == Camera3D.PROJECTION_PERSPECTIVE, "Dentro do túnel o carro usa perspectiva")
	check(pitch_degrees(camera) < 25.0, "Visão baixa atrás do carro (%.1f°)" % pitch_degrees(camera))
	check((camera.global_position - car.global_position).dot(car.global_basis.z) > 3.0, "Lente atrás do carro indo para leste")
	check(camera.global_position.y < TUNNEL.ceiling_y(camera.global_position.x), "Lente abaixo do teto")
	check(camera.size < size_outside * 0.75, "No fundo o zoom fecha (%.1f -> %.1f)" % [size_outside, camera.size])
	check(camera._cutaway.faded_count() == 0, "Visão traseira conserva teto e cidade sólidos")
	check(car.get_meta("interior_view", {}).get("low_camera_roof", false), "Carro fechado na visão traseira")
	await capture("after-east")
	car.place(deep, PI * 0.5)
	await settle(world, 3.0)
	check((camera.global_position - car.global_position).dot(car.global_basis.z) > 3.0, "Lente atrás do carro indo para oeste")
	await capture("after-west")
	# O carro do jogador não está nos chunks: nunca vira alfa.
	var car_faded := false
	for node in car.find_children("*", "MeshInstance3D", true, false):
		var mesh_node := node as MeshInstance3D
		if mesh_node.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF and mesh_node.material_override is StandardMaterial3D and (mesh_node.material_override as StandardMaterial3D).albedo_color.a < 0.3:
			car_faded = true
	check(not car_faded, "O carro do jogador não é apagado")

	# Volta à rua.
	car.place(Vector3(141.0, 0.12, 63.0), -PI * 0.5)
	await settle(world, 4.0)
	check(camera._tunnel_blend == 0.0, "De volta à rua a mistura zera (%.2f)" % camera._tunnel_blend)
	check(camera.projection == Camera3D.PROJECTION_ORTHOGONAL, "Saída restaura projeção de rua")
	check(camera._cutaway.faded_count() == 0, "De volta à rua nada fica apagado (%d)" % camera._cutaway.faded_count())
	check(absf(pitch_degrees(camera) - street_pitch) < 1.0, "De volta à rua a inclinação volta a %.1f° (%.1f)" % [street_pitch, pitch_degrees(camera)])
	check(absf(camera.size - size_outside) < 0.1, "Saída restaura zoom de rua")
	check(not car.get_meta("interior_view", {}).get("low_camera_roof", false), "Saída restaura visual do motorista na câmera de cima")
	await capture("after-street")

	# Desembarque real no túnel: perspectiva acompanha o ator, cujo corpo não gira.
	car.place(deep, -PI * 0.5)
	await settle(world, 3.0)
	if not await wait_body_state(world, true):
		await finish(world)
		return
	var left: bool = world.driving.interact(true)
	check(left, "Desembarque aceito dentro do túnel")
	if not left or not await wait_body_state(world, false):
		await finish(world)
		return
	check(not world.driving.occupied and camera.target == world.player, "Desembarque transfere câmera para o personagem")
	check(car.get_meta("interior_view", {}).get("low_camera_roof", false), "Carro estacionado conserva cobertura fechada na vista baixa")
	world.player.input_locked = true
	for facing in [-PI * .5, PI * .5]:
		world.player.visual.rotation.y = facing
		await settle(world, 3.0)
		check(camera.projection == Camera3D.PROJECTION_PERSPECTIVE, "A pé no túnel continua em perspectiva")
		var rear: Vector3 = world.player.visual.global_basis.z
		var behind: Vector3 = camera.global_position - world.player.global_position
		behind.y = 0.0
		check(behind.normalized().dot(rear) > .98, "Câmera gira para ficar atrás do personagem parado")
		check(camera.global_position.y < TUNNEL.ceiling_y(camera.global_position.x), "A pé lente permanece abaixo do teto")
		await capture("on-foot-east" if facing < 0.0 else "on-foot-west")
	world.player.teleport(Vector3(141.0, .12, 63.0))
	await settle(world, 3.0)
	check(camera.projection == Camera3D.PROJECTION_ORTHOGONAL, "Saída a pé restaura câmera de rua")
	check(camera._cutaway.faded_count() == 0, "Saída a pé restaura materiais")
	check(not car.get_meta("interior_view", {}).get("low_camera_roof", false), "Saída a pé restaura apresentação do carro estacionado")
	world.player.input_locked = false

	await finish(world)

func finish(world: Node) -> void:
	print("TUNNEL_CAMERA_CAPTURES ", output)
	world.queue_free()
	await process_frame
	if failures.is_empty():
		print("TUNNEL_CAMERA_OK")
		quit(0)
	else:
		print("TUNNEL_CAMERA_FALHOU ", failures.size())
		quit(1)

func capture(label: String) -> void:
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(output.path_join(label + ".png")) == OK, "Captura " + label)
