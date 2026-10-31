extends SceneTree
## Main: dirige pela calçada por cima das tampas e depois exercita a entrada F compartilhada.
const SEWERS := preload("res://world/places/sewers/SewerNetwork.gd")
const PLACES := preload("res://world/places/PlaceCatalog.gd")
var world
var failures: Array[String] = []
var folder := "res://output/manhole-session"
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	print(("PASS " if ok else "FAIL ")+label)
	if not ok: failures.append(label)
func frames(count: int) -> void:
	for i in count: await physics_frame
func snapshot(label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(folder.path_join(label+".png"))
func drive_lid(id: String, direction: float) -> void:
	var at: Vector3 = PLACES.get_definition(id).exterior_position
	world.production.region.set_focus(at)
	world.production.region.prepare_collision_at(at)
	var start := at+Vector3(-3*direction, .04, 0)
	var finish := at+Vector3(3*direction, .04, 0)
	world.production.region.prepare_collision_at(start)
	world.production.region.prepare_collision_at(finish)
	# O observador fica longe desta rota, não na frente do carro.
	world.player.teleport(at+Vector3(0, .1, 20))
	await frames(40)
	var hatch: Node3D = world.session._find_sewer_hatch(id)
	check(is_instance_valid(hatch) and is_zero_approx(hatch.open_amount), id+": tampa real fechada")
	var car = preload("res://scripts/Vehicle.gd").new()
	car.archetype = "sport_coupe"
	car.position = start
	world.add_child(car)
	car.set_external_driver(true)
	car.place(start, -PI*.5 if direction > 0 else PI*.5)
	car.brake_input = true
	await frames(30)
	var initial_health: float = car.health
	car.brake_input = false
	car.throttle_input = 1
	var travelled := false
	var walls := {}
	for i in 240:
		await physics_frame
		if (finish.x-car.global_position.x)*direction < .15: travelled = true; break
		if car.is_on_wall():
			for j in car.get_slide_collision_count():
				var hit: KinematicCollision3D = car.get_slide_collision(j)
				if absf(hit.get_normal().y) < .3: walls[str(hit.get_collider().get_path())] = true
	car.throttle_input = 0
	car.brake_input = true
	print("LID_DRIVE ",id," direction=",direction," damage=",initial_health-car.health," position=",car.position," walls=",walls)
	check(travelled and car.health >= initial_health and car.global_position.y > -.1, id+": carro passa sobre tampa sem bater, sentido "+str(direction))
	car.free()
	await physics_frame

func run() -> void:
	if not "--no-save" in OS.get_cmdline_user_args(): quit(2); return
	create_timer(180).timeout.connect(func(): push_error("Manhole session timeout"); quit(3))
	DirAccess.make_dir_recursive_absolute(folder)
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	root.add_child(world)
	for i in 2400:
		await physics_frame
		if world.session != null and world.session.ready_for_play: break
	check(world.session != null and world.session.ready_for_play, "Main inicia com Godot .NET")
	if not failures.is_empty(): world.free(); quit(1); return
	world.player.controlled_automatically = true
	world.camera.set_process_unhandled_input(false)
	# O runner geral de passagem cruza meios-fios, uma árvore e uma barreira costeira em
	# outros locais. Estas três rotas isolam a tampa na cidade integrada.
	var sites: Array = SEWERS.ids() if "--all-manholes" in OS.get_cmdline_user_args() else ["harbor_sewer", "sewer_quay", "sewer_warehouse"]
	if "--input-only" in OS.get_cmdline_user_args(): sites = []
	for id in sites:
		await drive_lid(id, 1)
		await drive_lid(id, -1)
	var session = world.session
	var at: Vector3 = PLACES.get_definition("harbor_sewer").exterior_position
	world.production.region.set_focus(at)
	world.player.teleport(at+Vector3(0,.04,1.25))
	await frames(30)
	check(session.nearest().get("place", "") == "harbor_sewer", "boeiro é a interação disponível")
	check(session.prompt_input_action == "vehicle_interact" and root.get_node("GameInput").hint("vehicle_interact") in session.prompt.text, "indicador usa a mesma tecla de roubar")
	check(world.hud.interaction_label.text == "Descer", "indicador apresenta F e ação Descer sem duplicar a tecla")
	await snapshot("F-prompt")
	var action := InputEventAction.new()
	action.action = "interact"
	action.pressed = true
	Input.parse_input_event(action)
	await frames(3)
	check(session.transition_kind.is_empty() and session.state.place_id.is_empty(), "E não começa a descida")
	action = InputEventAction.new()
	action.action = "interact"
	Input.parse_input_event(action)
	action = InputEventAction.new()
	action.action = "vehicle_interact"
	action.pressed = true
	Input.parse_input_event(action)
	for i in 120:
		await physics_frame
		if not session.transition_kind.is_empty() or session.state.place_id == "harbor_sewer": break
	check(not session.transition_kind.is_empty() or session.state.place_id == "harbor_sewer", "F inicia interação do boeiro")
	action = InputEventAction.new()
	action.action = "vehicle_interact"
	Input.parse_input_event(action)
	for i in 900:
		await physics_frame
		if session.state.place_id == "harbor_sewer" and session.transition_kind.is_empty(): break
	check(session.state.place_id == "harbor_sewer" and not world.driving.occupied, "F leva ao esgoto sem acionar entrada no carro")
	check(await session.leave_place(), "subida retorna à rua e fecha tampa")
	check(not world.player.input_locked and world.player.is_physics_processing(), "controles restaurados na saída")
	await snapshot("returned")
	# Saves existentes podem guardar o jogador dentro da sala subterrânea. Restaurar
	# esse local não pode varrer uma aproximação de rua a partir destas coordenadas distantes.
	session.state.place_id = "harbor_sewer"
	session.ready_for_play = false
	world.player.teleport(Vector3(0,.04,-2400))
	await session.restore_location()
	check(session.ready_for_play and session.state.place_id == "harbor_sewer" and session.room != null, "restauração admite save subterrâneo sem caminhada pela cidade")
	check(not world.player.input_locked and world.player.is_physics_processing(), "restauração libera física e controles")
	check(await session.leave_place(), "saída funciona após restauração")
	print("MANHOLE_SESSION_ACCESS failures=",failures)
	world.free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
