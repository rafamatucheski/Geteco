extends SceneTree
## Câmera no Túnel do canal, no Main.tscn real (renderizado, nunca headless): ao descer, a
## visão passa a perspectiva atrás do veículo, com teto sólido; ao
## voltar à rua tudo se desfaz (sem nó apagado sobrando, inclinação original).
## Uso: "$GODOT" --path . --script res://tests/test_tunnel_camera.gd -- --no-save
const TUNNEL := preload("res://world/urban_detail/CanalTunnel3D.gd")
var failures: Array[String] = []

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		push_error(label)

func pitch_degrees(camera: Camera3D) -> float:
	return rad_to_deg(asin(clampf(-(-camera.global_basis.z).y, -1.0, 1.0)))

func settle(world: Node, frames: int) -> void:
	for i in frames:
		await process_frame

func run() -> void:
	if DisplayServer.get_name() == "headless" or "--no-save" not in OS.get_cmdline_user_args():
		quit(2)
		return
	seed(28092026)
	var world: Variant = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	root.add_child(world)
	current_scene = world
	for frame in 1800:
		await process_frame
		if world.production != null and world.production.ready_for_play and world.session != null and world.session.weather != null:
			break
	var camera: Camera3D = world.camera
	camera.set_process_unhandled_input(false)
	var car: CharacterBody3D = world.driving.car
	var street := Vector3(160.0, 0.12, 63.0)
	world.production._update_physical_residency(street)
	world.production._update_logical_region(street)
	car.place(street, -PI * 0.5)
	for i in 3: await physics_frame
	for side in [-1, 1]:
		world.player.teleport(car.to_global(Vector3(side * (car.half_width + .65), .04, .15)))
		await physics_frame
		if world.driving.interact(): break
	car.set_external_driver(true)
	car.place(Vector3(141.0, 0.12, 63.0), -PI * 0.5)
	await settle(world, 90)
	check(camera._tunnel_blend == 0.0, "Fora do túnel a mistura é zero")
	# A inclinação de rua depende da opção de câmera (45° padrão, 37,5° na visão alternativa).
	var street_pitch := pitch_degrees(camera)
	check(street_pitch < 50.0, "Fora do túnel a inclinação é a de rua (%.1f)" % street_pitch)
	check(camera._cutaway.faded_count() == 0, "Fora do túnel nada é apagado")
	var size_outside := camera.size

	# Sob o cais: fundo do túnel.
	var deep := Vector3(190.0, TUNNEL.floor_y(190.0) + 0.12, 63.0)
	world.production._update_physical_residency(deep)
	car.place(deep, -PI * 0.5)
	await settle(world, 240)
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
	await settle(world, 180)
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
	await settle(world, 240)
	check(camera._tunnel_blend == 0.0, "De volta à rua a mistura zera (%.2f)" % camera._tunnel_blend)
	check(camera.projection == Camera3D.PROJECTION_ORTHOGONAL, "Saída restaura projeção de rua")
	check(camera._cutaway.faded_count() == 0, "De volta à rua nada fica apagado (%d)" % camera._cutaway.faded_count())
	check(absf(pitch_degrees(camera) - street_pitch) < 1.0, "De volta à rua a inclinação volta a %.1f° (%.1f)" % [street_pitch, pitch_degrees(camera)])
	check(absf(camera.size - size_outside) < 0.1, "Saída restaura zoom de rua")
	check(not car.get_meta("interior_view", {}).get("low_camera_roof", false), "Saída restaura visual do motorista na câmera de cima")
	await capture("after-street")

	# Desembarque real no túnel: perspectiva acompanha o ator, cujo corpo não gira.
	car.place(deep, -PI * 0.5)
	await settle(world, 180)
	for i in 600:
		await physics_frame
		if world.driving.transition == null and world.driving.occupied: break
	check(world.driving.interact(true), "Desembarque aceito dentro do túnel")
	for i in 600:
		await physics_frame
		if world.driving.transition == null and not world.driving.occupied: break
	check(not world.driving.occupied and camera.target == world.player, "Desembarque transfere câmera para o personagem")
	check(car.get_meta("interior_view", {}).get("low_camera_roof", false), "Carro estacionado conserva cobertura fechada na vista baixa")
	world.player.input_locked = true
	for facing in [-PI * .5, PI * .5]:
		world.player.visual.rotation.y = facing
		await settle(world, 180)
		check(camera.projection == Camera3D.PROJECTION_PERSPECTIVE, "A pé no túnel continua em perspectiva")
		var rear: Vector3 = world.player.visual.global_basis.z
		var behind: Vector3 = camera.global_position - world.player.global_position
		behind.y = 0.0
		check(behind.normalized().dot(rear) > .98, "Câmera gira para ficar atrás do personagem parado")
		check(camera.global_position.y < TUNNEL.ceiling_y(camera.global_position.x), "A pé lente permanece abaixo do teto")
		await capture("on-foot-east" if facing < 0.0 else "on-foot-west")
	world.player.teleport(Vector3(141.0, .12, 63.0))
	await settle(world, 180)
	check(camera.projection == Camera3D.PROJECTION_ORTHOGONAL, "Saída a pé restaura câmera de rua")
	check(camera._cutaway.faded_count() == 0, "Saída a pé restaura materiais")
	check(not car.get_meta("interior_view", {}).get("low_camera_roof", false), "Saída a pé restaura apresentação do carro estacionado")
	world.player.input_locked = false

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
	check(root.get_texture().get_image().save_png("res://evidence/tunnel-chase-20261001/%s.png" % label) == OK, "Captura " + label)
