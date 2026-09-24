extends SceneTree
## Independent acceptance for production modal focus/activation.
## Requires --no-save --skip-arrival and never resolves the default save.

var world: Node
var session: Node
var failures: Array[String] = []
var checks := 0
var modal_activated := false

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String, detail := "") -> void:
	checks += 1
	print(("UI_ACCEPT PASS " if ok else "UI_ACCEPT FAIL ") + label + ((" | " + detail) if not detail.is_empty() else ""))
	if not ok:
		failures.append(label)
		push_error(label + ((" | " + detail) if not detail.is_empty() else ""))

func frames(count: int) -> void:
	for _index in count:
		await physics_frame

func wait_until(predicate: Callable, maximum_frames: int) -> bool:
	for _index in maximum_frames:
		if predicate.call(): return true
		await physics_frame
	return false

func focused_button() -> Button:
	var owner := root.get_viewport().gui_get_focus_owner()
	return owner as Button

func send_keyboard_accept() -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = KEY_ENTER
		event.physical_keycode = KEY_ENTER
		event.pressed = pressed
		Input.parse_input_event(event)
		Input.flush_buffered_events()
		await frames(2)

func send_controller_accept() -> void:
	for pressed in [true, false]:
		var event := InputEventJoypadButton.new()
		event.device = 0
		event.button_index = JOY_BUTTON_A
		event.pressed = pressed
		event.pressure = 1.0 if pressed else 0.0
		Input.parse_input_event(event)
		Input.flush_buffered_events()
		await frames(2)

func open_probe_modal() -> void:
	modal_activated = false
	session._menu("Validação independente")
	session._button("Confirmar", func():
		modal_activated = true
		session.close_menu()
	)
	await frames(3)

func ensure_rescued() -> void:
	if session.rescue_pending and not session.respawn_busy:
		session._respawn()
	await wait_until(func(): return not session.rescue_pending and not session.respawn_busy, 300)

func open_rescue() -> bool:
	world.player.receive_damage(500.0)
	var overlay_opened := await wait_until(func(): return is_instance_valid(session.death_presentation), 30)
	var label: Label
	if overlay_opened: label = session.death_presentation.get_node_or_null("WastedLabel") as Label
	var audio: AudioStreamPlayer
	if overlay_opened: audio = session.death_presentation.get_node_or_null("WastedAudio") as AudioStreamPlayer
	check(overlay_opened and label != null and label.text == "SE FODEU", "morte apresenta a mensagem da V1 antes do resgate")
	check(audio != null and audio.stream != null and audio.playing, "morte toca a vinheta sonora da V1")
	return await wait_until(func(): return session.rescue_pending and session.panel.visible, 180)

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if "--no-save" not in args or "--skip-arrival" not in args:
		push_error("UI_ACCEPT validator refuses to run without --no-save --skip-arrival")
		quit(2)
		return
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	root.add_child(world)
	if not await wait_until(func(): return world.session != null and world.session.ready_for_play, 900):
		push_error("Production session did not become ready")
		quit(1)
		return
	session = world.session
	check(world.production.no_save, "sessão produtiva está em --no-save")

	await open_probe_modal()
	check(is_instance_valid(focused_button()) and focused_button().text == "Confirmar", "modal entrega foco ao botão")
	await send_keyboard_accept()
	check(modal_activated and not session.modal, "Enter/ui_accept ativa botão focado do modal")
	if session.modal: session.close_menu()

	await open_probe_modal()
	check(is_instance_valid(focused_button()) and focused_button().text == "Confirmar", "modal recupera foco para controle")
	await send_controller_accept()
	check(modal_activated and not session.modal, "controle A/ui_accept ativa botão focado do modal")
	if session.modal: session.close_menu()

	check(await open_rescue(), "morte real abre o resgate para teclado")
	await frames(3)
	check(is_instance_valid(focused_button()) and focused_button().text == "Continuar", "resgate entrega foco a Continuar")
	await send_keyboard_accept()
	check(await wait_until(func(): return not session.rescue_pending and not session.respawn_busy, 300), "Enter/ui_accept confirma o resgate")
	await ensure_rescued()
	check(preload("res://runtime/GameState.gd").new().restore_snapshot(session.state.snapshot()), "estado posterior ao resgate permanece valido para salvar")

	check(await open_rescue(), "segunda morte real abre o resgate para controle")
	await frames(3)
	check(is_instance_valid(focused_button()) and focused_button().text == "Continuar", "resgate recupera foco para controle")
	await send_controller_accept()
	check(await wait_until(func(): return not session.rescue_pending and not session.respawn_busy, 300), "controle A/ui_accept confirma o resgate")
	await ensure_rescued()

	world.gameplay.stars = 1
	world.gameplay.crime_points = 12
	world.player.velocity = Vector3.ZERO
	var arresting_officer := preload("res://gameplay/PoliceAgent.gd").new()
	arresting_officer.controller = world.gameplay
	world.gameplay.stars = 2
	for index in 360: arresting_officer._update_arrest(true,1.0,true,1.0/60.0)
	check(not session.arrest_pending, "polícia hostil de duas estrelas não prende o jogador")
	world.gameplay.stars = 1
	for index in 301: arresting_officer._update_arrest(true,1.0,false,1.0/60.0)
	arresting_officer.free()
	check(session.arrest_pending and is_instance_valid(session.death_presentation), "policial V1 conclui prisão após aviso e rendição imóvel")
	var arrest_label := session.death_presentation.get_node_or_null("ArrestLabel") as Label
	check(arrest_label != null and arrest_label.text == "PRESO", "prisão apresenta a mensagem PRESO da V1")
	check(await wait_until(func(): return not session.arrest_pending and not session.respawn_busy, 300), "prisão recupera o jogador automaticamente")
	var precinct: Dictionary = preload("res://world/places/PlaceCatalog.gd").get_definition("harbor_police")
	check(world.player.global_position.distance_to(precinct.return_position+Vector3.UP*.1)<1.0, "prisão leva o jogador à delegacia")
	check(world.gameplay.stars==0 and world.gameplay.health==100.0 and not world.player.dead, "custódia limpa procurado e restaura o jogador")

	print("UI_ACCEPT_ACCEPTANCE ", "PASS" if failures.is_empty() else "FAIL", " checks=", checks, " failures=", failures.size())
	world.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
