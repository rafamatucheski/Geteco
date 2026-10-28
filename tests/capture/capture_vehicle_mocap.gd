extends SceneTree
## Quadros dos movimentos com mocap (28/10/2026): roubo de carro (puxão, queda, levantar), entrar e sair do
## carro, e o levantar de quem foi derrubado. Com tela (nunca --headless):
##   tools/run_godot_locked.sh --path . --script res://tests/capture/capture_vehicle_mocap.gd -- --no-save --scene=carjack
## Cenas: carjack, enter, exit, getup. Um PNG a cada `--step` s de jogo (padrão 0,25) em
## evidence/mocap-vehicle-20261028/<cena>/ (fora do Git). GETECO_MOCAP_GETUP=0 / GETECO_MOCAP_BOARDING=0 = antes.
var world: Node3D
var focus: Node3D
var focus_offset := Vector3.UP
var folder := ""
var index := 0

func _initialize() -> void: run.call_deferred()

func shot() -> void:
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var camera := root.get_camera_3d()
	if is_instance_valid(focus) and camera != null:
		var scale := Vector2(image.get_size()) / root.get_visible_rect().size
		var center := camera.unproject_position(focus.global_position + focus_offset) * scale
		var size := Vector2i(560, 420)
		var origin := Vector2i(clampi(int(center.x) - size.x / 2, 0, image.get_width() - size.x), clampi(int(center.y) - size.y / 2, 0, image.get_height() - size.y))
		image = image.get_region(Rect2i(origin, size))
	image.save_png(ProjectSettings.globalize_path("%s/%03d.png" % [folder, index]))
	index += 1

## Fotografa a cada `step` s de jogo enquanto `busy` devolver true (ou até `limit` s de jogo).
func film(step: float, limit: float, busy: Callable) -> void:
	var game_time := 0.0
	var next := 0.0
	_last_ticks = -1
	while game_time < limit and busy.call():
		await process_frame
		game_time += _last_delta()
		if game_time >= next:
			next += step
			await shot()
	await shot()

var _last_ticks := -1
func _last_delta() -> float:
	var now := Time.get_ticks_usec()
	var delta := 0.0 if _last_ticks < 0 else float(now - _last_ticks) / 1000000.0 * Engine.time_scale
	_last_ticks = now
	return delta

func run() -> void:
	var scene := "carjack"
	var step := 0.25
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--scene="): scene = argument.trim_prefix("--scene=")
		if argument.begins_with("--step="): step = float(argument.trim_prefix("--step="))
	folder = "res://evidence/mocap-vehicle-20261028/" + scene
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	for file in DirAccess.get_files_at(ProjectSettings.globalize_path(folder)):
		if file.ends_with(".png"): DirAccess.remove_absolute(ProjectSettings.globalize_path(folder + "/" + file))
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
	var pose: Transform3D = world.driving.car.global_transform
	world.driving.car.position += Vector3(15, 0, 0)
	world.player.teleport(pose.origin + Vector3(12, 0, 12))
	await physics_frame
	await physics_frame
	world.camera.target_size = 7
	# Girado 180°: a câmera do jogo olha de um lado só, e a porta do motorista precisa ficar virada para ela.
	var car: CharacterBody3D = world.production.spawn_vehicle("sedan_classic", pose.origin, pose.basis.get_euler().y + PI)
	if not is_instance_valid(car):
		print("MOCAP carro não nasceu")
		quit(1)
		return
	for frame in 20: await physics_frame
	match scene:
		"carjack": await _carjack(car, step)
		"enter": await _enter(car, step)
		"exit": await _exit(car, step)
		"getup": await _getup(car, step)
	Engine.time_scale = 1.0
	print("MOCAP cena=", scene, " quadros=", index)
	quit(0)

func _carjack(car: CharacterBody3D, step: float) -> void:
	car.traffic = true
	world.player.teleport(car.driver_door_anchor(-1) - car.global_basis.x * .6)
	for frame in 10: await physics_frame
	focus = car
	Engine.time_scale = .5
	if not world.driving.interact():
		print("MOCAP roubo sem interação")
		return
	var body = world.driving.transition
	var victim: Node3D = body.carjacking.victim if body != null and body.carjacking != null else null
	print("MOCAP vítima=", victim)
	await film(step, 9.0, func(): return world.driving.is_body_transition_active())
	if not is_instance_valid(victim): return
	focus = victim
	focus_offset = Vector3.UP * .5
	await film(step, 16.0, func(): return is_instance_valid(victim) and victim.has_meta("street_down"))
	print("MOCAP vítima de pé=", is_instance_valid(victim) and not victim.has_meta("street_down"))

func _enter(car: CharacterBody3D, step: float) -> void:
	world.player.teleport(car.driver_door_anchor(-1) - car.global_basis.x * 1.4 + car.global_basis.z * .4)
	for frame in 10: await physics_frame
	focus = car
	Engine.time_scale = .5
	if not world.driving.interact():
		print("MOCAP entrada sem interação")
		return
	await film(step, 9.0, func(): return world.driving.is_body_transition_active())
	for frame in 20: await physics_frame
	await shot()

func _exit(car: CharacterBody3D, step: float) -> void:
	world.player.teleport(car.driver_door_anchor(-1) - car.global_basis.x * 1.2)
	for frame in 10: await physics_frame
	world.driving.interact()
	var deadline := Time.get_ticks_msec() + 15000
	while world.driving.is_body_transition_active() and Time.get_ticks_msec() < deadline: await process_frame
	for frame in 30: await physics_frame
	focus = car
	Engine.time_scale = .5
	if not world.driving.interact():
		print("MOCAP saída sem interação")
		return
	await film(step, 9.0, func(): return world.driving.is_body_transition_active())
	for frame in 20: await physics_frame
	await shot()

## Pedestre derrubado por um empurrão (o mesmo ragdoll do roubo) até levantar.
func _getup(car: CharacterBody3D, step: float) -> void:
	var person = preload("res://scripts/Actor.gd").new()
	person.identity = 4242
	person.position = car.global_position + car.global_basis.x * 4.0
	world.add_child(person)
	for frame in 20: await physics_frame
	# 70: levanta sozinho (≥ 60) com o clipe machucado (< 75). Abaixo de 60 fica no chão tentando.
	person.health = 70.0
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--health="): person.health = float(argument.trim_prefix("--health="))
	world.player.teleport(person.global_position + car.global_basis.z * 3.0)
	world.camera.target = person
	for frame in 20: await physics_frame
	focus = person
	focus_offset = Vector3.UP * .5
	Engine.time_scale = .5
	var flight = preload("res://gameplay/street_physics/BodyFlight3D.gd").launch(person, car.global_basis.x * 3.4, false, null, null, true, true)
	if is_instance_valid(flight): flight.min_down = 1.3
	await film(step, 30.0, func(): return is_instance_valid(person) and person.has_meta("street_down"))
	print("MOCAP de pé=", is_instance_valid(person) and not person.has_meta("street_down"))
