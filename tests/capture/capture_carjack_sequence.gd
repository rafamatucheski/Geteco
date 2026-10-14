extends SceneTree
## Sequência de quadros do motorista puxado do carro (2026-10-14): do agarrão até levantar do chão, para
## revisar o arrasto pela porta, o arremesso e a queda. Com tela (nunca --headless):
##   "$GODOT" --path . --script res://tests/capture/capture_carjack_sequence.gd -- --no-save --label=depois
## Antes: GETECO_CARJACK_THROW=0 com --label=antes. PNG em evidence/carjack/ (fora do Git).
var world: Node3D

func _initialize() -> void: run.call_deferred()

var focus: Node3D

## Recorte em volta do carro: a ação ocupa pouco da tela da câmera alta e o PNG inteiro demorava a salvar.
func shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var camera := root.get_camera_3d()
	if is_instance_valid(focus) and camera != null:
		# A janela tem escala de conteúdo: a posição da câmera vem na área visível, a imagem no tamanho real.
		var scale := Vector2(image.get_size()) / root.get_visible_rect().size
		var center := camera.unproject_position(focus.global_position + Vector3.UP) * scale
		var size := Vector2i(520, 400)
		var origin := Vector2i(clampi(int(center.x) - size.x / 2, 0, image.get_width() - size.x), clampi(int(center.y) - size.y / 2, 0, image.get_height() - size.y))
		image = image.get_region(Rect2i(origin, size))
	image.save_png(ProjectSettings.globalize_path(path))

func run() -> void:
	var label := "medicao"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--label="): label = argument.trim_prefix("--label=")
	var folder := "res://evidence/carjack"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	for action in InputMap.get_actions(): InputMap.action_erase_events(action)
	# Salvar um PNG custa mais que um quadro: a janela menor e o tempo 4x mais lento deixam ver o movimento todo.
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
	var pose: Transform3D = world.driving.car.global_transform
	world.driving.car.position += Vector3(15, 0, 0)
	world.player.teleport(pose.origin + Vector3(12, 0, 12))
	await physics_frame
	await physics_frame
	var car: CharacterBody3D = world.production.spawn_vehicle("sedan_classic", pose.origin, pose.basis.get_euler().y)
	if not is_instance_valid(car):
		print("CARJACK carro não nasceu")
		quit(1)
		return
	car.traffic = true
	world.player.teleport(car.driver_door_anchor(-1) - car.global_basis.x * .15)
	for frame in 30: await physics_frame
	world.camera.target_size = 6
	focus = car
	Engine.time_scale = .25
	if not world.driving.interact():
		print("CARJACK sem interação")
		quit(1)
		return
	var body = world.driving.transition
	var theft = body.carjacking
	var victim = theft.victim
	var started := Time.get_ticks_msec()
	var index := 0
	var last := -1000
	# Do começo do puxão até ~3 s depois: a cada 100 ms um quadro, com a câmera seguindo a vítima no fim.
	while Time.get_ticks_msec() - started < 150000:
		await process_frame
		var extracting: bool = is_instance_valid(body) and body._extracting
		var after: bool = theft.released and is_instance_valid(victim)
		if not extracting and not after:
			started = Time.get_ticks_msec()
			continue
		if Time.get_ticks_msec() - last < 200: continue
		last = Time.get_ticks_msec()
		var progress: float = body._extraction_progress if extracting else 1.0
		await shot("%s/%s_%02d_%.2f.png" % [folder, label, index, progress])
		index += 1
		if after and is_instance_valid(victim) and not victim.has_meta("street_down") and index > 30: break
		if index > 60: break
	Engine.time_scale = 1.0
	print("CARJACK quadros=", index)
	quit(0)
