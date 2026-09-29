extends SceneTree
var failures: Array[String] = []
var checks := 0
var world
var touch
var controls

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	print(("PASS " if ok else "FAIL ") + label)
	if not ok: failures.append(label)

func finger(index: int, position: Vector2, pressed: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = position
	event.pressed = pressed
	# Positions below are viewport coordinates, independent of window scaling.
	root.push_input(event, true)
	await process_frame
	await process_frame

func button(action: String, index: int, pressed: bool) -> void:
	await finger(index, touch.buttons[action].rect.get_center(), pressed)

func run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	world = load("res://Main.tscn").instantiate()
	root.add_child(world)
	current_scene = world
	for i in 1800:
		await process_frame
		if world.session != null and world.session.ready_for_play: break
	if world.session == null or not world.session.ready_for_play: quit(3); return
	# Start away from the automatic garage entrance; real rendered frames let
	# movement travel farther than a headless input-only check.
	world.player.teleport(Vector3(132, .15, 72))
	for i in 12: await physics_frame
	touch = world.find_child("AndroidControls", true, false)
	check(touch != null, "overlay criado com --touch-controls")
	if touch == null: quit(1); return
	controls = root.get_node("GameInput")
	touch._refresh()
	print("TOUCH_CONTEXT ", touch.playable, " size=", touch.size, " input=", touch.is_processing_input(), " locked=", world.player.input_locked)
	await finger(1, touch.move_center + Vector2(touch.radius * .8, 0), true)
	check(controls.movement().x > .5, "dedo 1 movimenta")
	check(not controls.sprinting(), "curso interno do analógico anda")
	var drag := InputEventScreenDrag.new()
	drag.index = 1
	drag.position = touch.move_center + Vector2(touch.radius,0)
	root.push_input(drag,true)
	await process_frame
	check(controls.sprinting() and controls.movement().x > .9, "mesmo dedo corre ao levar analógico à borda")
	await finger(2, touch.aim_center + Vector2(0, -touch.radius * .8), true)
	check(controls.touch_aim.y < -.5 and Input.is_action_pressed("aim"), "dedo 2 mira simultaneamente")
	check(not Input.is_action_pressed("fire"), "toque no analógico não dispara pelo mouse emulado")
	await button("fire", 3, true)
	check(Input.is_action_pressed("fire") and controls.movement().x > .5, "dedo 3 ataca mantendo movimento")
	check(controls.sprinting(), "corrida funciona junto de mira e ataque")
	await button("fire", 3, false)
	await finger(2, Vector2.ZERO, false)
	await finger(1, Vector2.ZERO, false)
	check(controls.touch_move.is_zero_approx() and controls.touch_aim.is_zero_approx() and not Input.is_action_pressed("fire") and not Input.is_action_pressed("aim"), "soltar dedos libera todos os estados")
	check(controls.aim_direction.y < -.9, "última direção da mira é preservada")
	check(not controls.touch_sprint, "soltar analógico encerra corrida")
	await button("inventory", 4, true)
	touch._refresh()
	check(world.session.modal and not touch.playable and Input.emulate_mouse_from_touch, "mochila abre e devolve toque aos menus")
	await button("ui_cancel", 5, true)
	await create_timer(.2).timeout
	check(not world.session.modal, "Voltar fecha a mochila")
	await button("pause_game", 6, true)
	touch._refresh()
	check(paused and not touch.playable, "pausa funciona e desativa comandos")
	await button("ui_cancel", 7, true)
	await create_timer(.2).timeout
	check(not paused, "Voltar retoma o jogo")
	# Passenger/motocross deliberately lock the pedestrian; their mobile UI
	# must remain reachable. Restore the fixture before simulation advances.
	world.player.input_locked = true
	world.session.passenger_transport.riding = true
	touch._refresh()
	check(touch.buttons.has("exit_vehicle") and touch.playable and touch.passenger, "passageiro pode pedir desembarque com pedestre travado")
	world.session.passenger_transport.riding = false
	world.session.motocross.mounted = true
	touch._refresh()
	check(touch.buttons.has("accelerate") and touch.buttons.has("exit_vehicle") and touch.motocross, "motocross mantém pedais e saída com pedestre travado")
	world.session.motocross.mounted = false
	world.player.input_locked = false
	touch._refresh()
	var cargo_lock = world.session.port_container_loot.minigame
	world.session.modal = true
	cargo_lock.begin(2, 0)
	touch._refresh()
	check(touch.buttons.has("move_left") and touch.buttons.has("interact") and not Input.emulate_mouse_from_touch, "gazua recebe controles próprios sem clique duplicado")
	await button("move_right", 20, true)
	await create_timer(.2).timeout
	await button("move_right", 20, false)
	check(cargo_lock.angle > 0, "seta de toque ajusta gazua")
	await button("ui_cancel", 21, true)
	await create_timer(.2).timeout
	check(not cargo_lock.active and not world.session.modal, "Voltar cancela gazua")
	var bank_lock = world.session.robberies.lockpick
	world.session.modal = true
	bank_lock.begin()
	touch._refresh()
	check(touch.buttons.has("ui_accept"), "cofre recebe botão Travar")
	await button("ui_accept", 22, true)
	await button("ui_accept", 22, false)
	check(bank_lock.pins + bank_lock.mistakes == 1, "toque no cofre produz uma única tentativa")
	await button("ui_cancel", 23, true)
	await create_timer(.2).timeout
	check(not bank_lock.active and not world.session.modal, "Voltar cancela cofre")
	# A troca de contexto libera toques antes de permitir dirigir ou abrir menus.
	await finger(8, touch.move_center + Vector2(touch.radius, 0), true)
	touch.release_all()
	await process_frame
	check(touch.fingers.is_empty() and controls.touch_move.is_zero_approx(), "troca de contexto não deixa aceleração/movimento presos")
	var old_place: String = world.session.state.place_id
	world.session.state.set_location("harbor", "maciota")
	touch._refresh()
	check(not touch.buttons.has("fire") and not touch.buttons.has("weapon_next"), "garagem não oferece ataque nem troca de arma")
	world.session.state.set_location("harbor", old_place)
	touch._refresh()
	var joystick_bounds := Rect2(touch.move_center - Vector2.ONE * touch.radius, Vector2.ONE * touch.radius * 2)
	check(not world.hud.minimap.get_global_rect().intersects(joystick_bounds), "minimapa não cobre o analógico")
	# Layout responde aos dois formatos sem depender de resolução fixa.
	for extent in [Vector2(1280, 540), Vector2(1280, 1180)]:
		touch.size = extent
		touch._refresh()
		var inside := true
		for item in touch.buttons.values(): inside = inside and Rect2(Vector2.ZERO, extent).encloses(item.rect)
		check(inside, "botões dentro da tela " + str(extent))
	if DisplayServer.get_name() != "headless":
		touch.size = root.get_visible_rect().size
		touch._refresh()
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute("res://evidence/android-20260928")
		root.get_texture().get_image().save_png("res://evidence/android-20260928/controls.png")
	var original = world.driving.car
	var route: Curve3D = world.production.traffic_routes.route_near(original.position)
	var offset: float = route.get_closest_offset(original.position)
	var point: Vector3 = route.sample_baked(offset, true)
	var direction: Vector3 = route.sample_baked(offset + 1, true) - point
	original.collision_layer = 0
	original.collision_mask = 0
	original.set_physics_process(false)
	original.remove_from_group("drivable")
	var car = world.production.spawn_vehicle("sport_coupe", point + Vector3.UP * .15, atan2(-direction.x, -direction.z))
	for i in 4: await physics_frame
	world.player.teleport(car.to_global(Vector3(-(car.half_width + .65), .05, .15)))
	var admitted: bool = await world.session.restore_garage_driver(car)
	check(admitted and world.driving.occupied, "jogador assume veículo real")
	if admitted:
		touch._refresh()
		check(touch.buttons.has("accelerate") and touch.buttons.has("brake"), "contexto de direção oferece pedais")
		await finger(9, touch.move_center + Vector2(touch.radius, 0), true)
		await button("accelerate", 10, true)
		check(controls.vehicle_input().x > .5 and controls.vehicle_input().y > .5, "direção e acelerador simultâneos")
		await button("more", 30, true)
		check(controls.vehicle_input().x > .5 and controls.vehicle_input().y > .5, "abrir opções preserva direção e acelerador")
		var audio = world.production.world_audio
		var station: int = audio.radio_index
		await button("radio_next",31,true)
		await button("radio_next",31,false)
		check(audio.radio_index == posmod(station+1,audio.STATIONS.size()), "rádio avança pelo toque real")
		await button("radio_previous",32,true)
		await button("radio_previous",32,false)
		check(audio.radio_index == station, "rádio volta pelo toque real")
		await button("radio_toggle",33,true)
		await button("radio_toggle",33,false)
		check(audio.radio_index == -1 and not audio.radio.playing, "rádio desliga diretamente")
		await button("radio_toggle",34,true)
		await button("radio_toggle",34,false)
		check(audio.radio_index == station and audio.radio.playing, "rádio religa na estação anterior")
		check(controls.vehicle_input().x > .5 and controls.vehicle_input().y > .5, "sintonizar não interrompe direção e acelerador")
		await button("accelerate", 10, false)
		await button("brake", 11, true)
		check(controls.vehicle_input().y < -.5, "freio/ré pelo toque")
		touch.release_all()
		await process_frame
		check(controls.vehicle_input().is_zero_approx(), "pedais liberados após cancelamento")
	world.queue_free()
	await process_frame
	check(not controls.has_meta("touch_controls_active") and Input.emulate_mouse_from_touch, "saída restaura entrada dos menus")
	print("ANDROID_CONTROLS checks=", checks, " failures=", failures)
	quit(0 if failures.is_empty() else 1)
