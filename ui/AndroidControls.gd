extends Control
## O multitoque só cuida de dedos que começam nos controles; menus mantêm cliques de toque normais.
var world: Node
var controls: Node
var fingers: Dictionary = {}
var buttons: Dictionary = {}
var move_center := Vector2.ZERO
var aim_center := Vector2.ZERO
var radius := 76.0
var unit := 1.0
var playable := false
var driving := false
var passenger := false
var motocross := false
var motorcycle := false
var skating := false
var fishing := false
var hallucinating := false
var extra := false
var _context := ""
var _layout_extra := false
var _safe := Rect2()
var compact := false
const STICK_DEADZONE := 0.12

func _ready() -> void:
	name = "AndroidControls"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	controls = GameInput
	controls.set_meta("touch_controls_active", true)
	var recorder := preload("res://runtime/FrameStallRecorder.gd").new()
	recorder.world = world
	add_child(recorder)
	if OS.has_feature("android"): get_tree().quit_on_go_back = false
	resized.connect(_refresh)
	var timer := Timer.new()
	timer.wait_time = 0.1
	timer.timeout.connect(_refresh)
	add_child(timer)
	timer.start()
	_refresh()

func _refresh() -> void:
	if not is_instance_valid(world) or world.session == null: return
	var session = world.session
	var paused := get_tree().paused
	var riding: bool = (session.passenger_transport != null and session.passenger_transport.riding) or (session.arrival != null and session.arrival.riding)
	var on_bike: bool = session.motocross != null and session.motocross.mounted
	var on_skate: bool = session.skate != null and session.skate.mounted
	var fishing_controller: Variant = session.get("fishing")
	var on_fishing: bool = is_instance_valid(fishing_controller) and fishing_controller.controls_locked()
	var active: bool = session.ready_for_play and not session.modal and not paused and (not world.player.input_locked or riding or on_bike or on_skate or on_fishing)
	var in_car: bool = world.driving.occupied or on_bike
	var on_motorcycle: bool = on_bike or (world.driving.occupied and is_instance_valid(world.driving.car) and world.driving.car.archetype.begins_with("bike_"))
	var lockpick: bool = session.port_container_loot != null and is_instance_valid(session.port_container_loot.minigame) and session.port_container_loot.minigame.active
	var bank_lock: bool = session.robberies != null and is_instance_valid(session.robberies.lockpick) and session.robberies.lockpick.active
	bank_lock = bank_lock or (session.police_motor_pool != null and is_instance_valid(session.police_motor_pool.lockpick) and session.police_motor_pool.lockpick.active)
	active = active and not lockpick and not bank_lock
	var illusion: Variant = session.get("upside_world")
	hallucinating = is_instance_valid(illusion) and illusion.exploring()
	var can_fight: bool = session.state.weapons_allowed() and not hallucinating
	var safe := Rect2(Vector2.ZERO, size)
	if OS.has_feature("android"):
		var physical := DisplayServer.get_display_safe_area()
		if physical.size.x > 0 and physical.size.y > 0:
			var inverse := get_viewport().get_screen_transform().affine_inverse()
			safe = safe.intersection(Rect2(inverse * Vector2(physical.position), inverse.basis_xform(Vector2(physical.size))))
	var context := str([active, in_car, riding, on_bike, on_motorcycle, on_skate, on_fishing, can_fight, paused, session.modal, session.dialogue_open, lockpick, bank_lock, safe])
	if context == _context and extra == _layout_extra: return
	# Expandir opções não pode soltar um dedo que ainda esterça ou acelera.
	if context != _context: release_all()
	_layout_extra = extra
	_context = context
	playable = active
	# O jogo consome o multitoque cru. A emulação de mouse é só para menus, então
	# tocar um joystick não pode também apertar a ligação de tiro do desktop.
	Input.emulate_mouse_from_touch = not active and not lockpick and not bank_lock
	driving = in_car
	passenger = riding
	motocross = on_bike
	motorcycle = on_motorcycle
	skating = on_skate
	fishing = on_fishing
	_safe = safe
	# Telas externas/retrato de dobráveis e telas internas quase quadradas precisam de alvos maiores para o polegar.
	compact = safe.size.x < safe.size.y * 1.4
	unit = minf(safe.size.x / 720.0, safe.size.y / 900.0) if compact else minf(safe.size.x / 1280.0, safe.size.y / 720.0)
	radius = 76.0 * unit
	buttons.clear()
	move_center = safe.position + Vector2(145 * unit, safe.size.y - 140 * unit)
	aim_center = safe.end - Vector2(145, 140) * unit
	if compact:
		move_center = safe.position + Vector2(110 * unit, safe.size.y - 125 * unit)
		aim_center = safe.end - Vector2(110, 125) * unit
	var top := safe.position + Vector2(safe.size.x * 0.5, 34 * unit)
	if not active:
		if session.modal or paused or lockpick or bank_lock:
			_button("ui_cancel", "Voltar", top, Vector2(108, 52))
		if lockpick:
			var base := safe.position + Vector2(safe.size.x * .5, safe.size.y - 50 * unit)
			_button("move_left", "‹", base - Vector2(150, 0) * unit, Vector2(110, 64))
			_button("interact", "Girar", base, Vector2(150, 64))
			_button("move_right", "›", base + Vector2(150, 0) * unit, Vector2(110, 64))
		if bank_lock:
			_button("ui_accept", "Travar", safe.position + Vector2(safe.size.x * .5, safe.size.y - 50 * unit), Vector2(160, 64))
		if session.dialogue_open:
			_button("interact", "Continuar", safe.position + Vector2(safe.size.x * .5, safe.size.y - 50 * unit), Vector2(160, 64))
		queue_redraw()
		return
	_button("pause_game", "Pausa", top + Vector2(-180, 0) * unit, Vector2(100, 52))
	if hallucinating:
		queue_redraw()
		return
	if fishing:
		# Mantém o lado direito livre para o HUD de tensão/ranking. A pesca consome
		# a mesma ação de interagir segurada/solta usada no teclado e no controle.
		var fishing_bottom := safe.position + Vector2(safe.size.x * .42, safe.size.y - 60 * unit)
		_button("interact", "Pescar", fishing_bottom - Vector2(86, 0) * unit, Vector2(146, 82))
		_button("exit_vehicle", "Sair", fishing_bottom + Vector2(76, 0) * unit, Vector2(120, 82))
		queue_redraw()
		return
	if skating:
		var skate_bottom := safe.end - Vector2(160, 70) * unit
		_button("skate_ollie", "Ollie", skate_bottom + Vector2(0, -145) * unit, Vector2(112, 68))
		_button("skate_flip", "Flip", skate_bottom + Vector2(-130, -70) * unit, Vector2(112, 68))
		_button("skate_shove", "Shove-it", skate_bottom + Vector2(0, -70) * unit, Vector2(112, 68))
		_button("exit_vehicle", "Descer", skate_bottom, Vector2(112, 68))
		queue_redraw()
		return
	if passenger:
		_button("exit_vehicle", "Desembarcar", safe.position + Vector2(safe.size.x * .5, safe.size.y - 48 * unit), Vector2(180, 68))
		queue_redraw()
		return
	_button("world_map", "Mapa", top + Vector2(-65, 0) * unit, Vector2(100, 52))
	_button("inventory", "Inventário", top + Vector2(50, 0) * unit, Vector2(110, 52))
	_button("more", "•••", top + Vector2(165, 0) * unit, Vector2(92, 52))
	var bottom := safe.position + Vector2(safe.size.x * .5, safe.size.y - 48 * unit)
	_button("interact", "Ação", bottom - Vector2(65, 0) * unit, Vector2(112, 68))
	_button("exit_vehicle" if driving else "vehicle_interact", "Sair" if driving else "Entrar", bottom + Vector2(65, 0) * unit, Vector2(112, 68))
	if driving:
		_button("accelerate", "Acelerar", aim_center + Vector2(0, -48) * unit, Vector2(140, 82))
		_button("brake", "Frear / Ré", aim_center + Vector2(0, 50) * unit, Vector2(140, 82))
		_button("handbrake", "Freio mão", aim_center - Vector2(166, 0) * unit, Vector2(122, 70))
		if motorcycle: _button("motorcycle_wheelie", "Empinar", aim_center - Vector2(166, 88) * unit, Vector2(122, 70))
		if not motocross:
			_button("radio_previous", "Rádio ‹", top + Vector2(-120, 72) * unit, Vector2(112, 58))
			_button("radio_toggle", "Liga/desliga", top + Vector2(0, 72) * unit, Vector2(112, 58))
			_button("radio_next", "Rádio ›", top + Vector2(120, 72) * unit, Vector2(112, 58))
	else:
		_button("jump", "Pular", aim_center - (Vector2(0, 300) if compact else Vector2(300, 0)) * unit, Vector2(110, 60))
		if can_fight:
			_button("fire", "Atacar", aim_center - (Vector2(0, 210) if compact else Vector2(160, 0)) * unit, Vector2(116, 82))
			_button("reload", "Recarregar", aim_center - Vector2(152, 112) * unit, Vector2(130, 60))
			_button("weapon_next", "Arma", aim_center - Vector2(0, 132) * unit, Vector2(110, 60))
	if extra:
		var actions: Array = [["journal", "Diário"], ["camera_left", "Girar ‹"], ["camera_right", "Girar ›"], ["trunk", "Bagagem"]]
		if driving:
			actions.append_array([["horn", "Buzina"], ["headlights", "Faróis"], ["siren_toggle", "Sirene"], ["tank_fire", "Canhão"]])
			if is_instance_valid(world.driving.car) and world.driving.car.get_meta("biarticulated", false): actions.append(["bus_doors", "Portas ônibus"])
		else:
			actions.append_array([["unarmed", "Guardar"], ["weapon_flashlight", "Lanterna"], ["surrender", "Render-se"], ["bus_driver_shift", "Dirigir ônibus"]])
			if can_fight: actions.append(["rage", "RAGE"])
		for i in actions.size():
			# Whole-number grouping/index; preserve integer truncation and precision.
			var columns := 3 if compact else 5
			@warning_ignore("integer_division")
			var row: int = i / columns
			_button(actions[i][0], actions[i][1], top + Vector2((i % columns - (columns - 1) * .5) * 120, (144 if driving else 72) + row * 66) * unit, Vector2(112, 58))
	for index in fingers.keys():
		if not str(fingers[index]).ends_with("_stick") and not buttons.has(fingers[index]): _release(index)
	queue_redraw()

func _button(action: String, label: String, center: Vector2, extent: Vector2) -> void:
	buttons[action] = {"rect": Rect2(center - extent * unit * .5, extent * unit), "label": label}

func _input(event: InputEvent) -> void:
	if event is InputEventMouse and event.device == InputEvent.DEVICE_ID_EMULATION and playable:
		get_viewport().set_input_as_handled()
		return
	if event is InputEventScreenTouch:
		if not event.pressed or event.canceled:
			if fingers.has(event.index):
				_release(event.index)
				get_viewport().set_input_as_handled()
			return
		var point: Vector2 = event.position
		var action := ""
		for key in buttons:
			if buttons[key].rect.has_point(point): action = key; break
		if action.is_empty() and playable and not passenger and not fishing:
			if point.distance_to(move_center) < radius * 1.3: action = "move_stick"
			elif not driving and not skating and point.distance_to(aim_center) < radius * 1.3 and world.session.state.weapons_allowed(): action = "aim_stick"
		if action.is_empty(): return
		get_viewport().set_input_as_handled()
		if action == "more":
			extra = not extra
			_refresh()
			return
		if action in fingers.values(): return
		controls.using_gamepad = false
		fingers[event.index] = action
		if action.ends_with("_stick"): _drag(event.index, point)
		else: _send(action, true)
		queue_redraw()
	elif event is InputEventScreenDrag and fingers.has(event.index):
		_drag(event.index, event.position)
		get_viewport().set_input_as_handled()

func _drag(index: int, point: Vector2) -> void:
	var action: String = fingers[index]
	if action == "move_stick":
		var vector := _stick_vector(point, move_center)
		controls.touch_move = Vector2(vector.x, 0) if driving and not motocross else vector
		# Curso interno anda; curso externo corre com o mesmo polegar. A histerese
		# evita piscar entre andar/correr perto da fronteira enquanto mira com a outra mão.
		controls.touch_sprint = not driving and vector.length() >= (.72 if controls.touch_sprint else .85)
	elif action == "aim_stick":
		controls.touch_aim = _stick_vector(point, aim_center)
		if not controls.touch_aim.is_zero_approx(): controls.aim_direction = controls.touch_aim.normalized()
		if not Input.is_action_pressed("aim"): _send("aim", true)
	queue_redraw()

func _stick_vector(point: Vector2, center: Vector2) -> Vector2:
	var vector := ((point - center) / radius).limit_length()
	return Vector2.ZERO if vector.length() < STICK_DEADZONE else vector

func _release(index: int) -> void:
	var action: String = fingers[index]
	fingers.erase(index)
	if action == "move_stick":
		controls.touch_move = Vector2.ZERO
		controls.touch_sprint = false
	elif action == "aim_stick":
		controls.touch_aim = Vector2.ZERO
		_send("aim", false)
	else: _send(action, false)
	queue_redraw()

func _send(action: String, pressed: bool) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = pressed
	# Dispara depois do toque original para o estado tratado não consumir a ação.
	Input.parse_input_event.call_deferred(event)

func release_all() -> void:
	for index in fingers.keys(): _release(index)
	if is_instance_valid(controls):
		controls.touch_move = Vector2.ZERO
		controls.touch_sprint = false
		controls.touch_aim = Vector2.ZERO

func _notification(what: int) -> void:
	if OS.has_feature("android") and (what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED):
		release_all()
		if is_instance_valid(world) and world.pause_panel != null and playable:
			world.pause_panel.pause_game()
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		release_all()
		_send("ui_cancel" if not playable else "pause_game", true)
		_send("ui_cancel" if not playable else "pause_game", false)

func _exit_tree() -> void:
	release_all()
	Input.emulate_mouse_from_touch = true
	if is_instance_valid(controls): controls.remove_meta("touch_controls_active")

func _draw() -> void:
	var font := ThemeDB.fallback_font
	var font_size := maxi(12, int(18 * unit))
	for action in buttons:
		var item: Dictionary = buttons[action]
		var rect: Rect2 = item.rect
		var held: bool = action in fingers.values()
		draw_style_box(_style(held), rect)
		var caption := tr(str(item.label))
		var text_size := font.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
		draw_string(font, rect.get_center() + Vector2(-text_size.x * .5, font_size * .35), caption, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.WHITE)
	if playable and not passenger and not fishing:
		_stick(move_center, controls.touch_move, "Direção" if driving else "Correr" if controls.touch_sprint else "Andar", font, font_size)
		if not driving: draw_arc(move_center, radius * .85, 0, TAU, 48, Color(1,.6,.25,.7), unit, true)
		if not driving and not skating and world.session.state.weapons_allowed(): _stick(aim_center, controls.touch_aim, "Olhar" if hallucinating else "Mirar", font, font_size)

func _style(held: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(.75,.36,.12,.8) if held else Color(.04,.06,.08,.65)
	style.border_color = Color(1,1,1,.45)
	style.set_border_width_all(1)
	style.set_corner_radius_all(int(14 * unit))
	style.corner_detail = 12
	return style

func _stick(center: Vector2, vector: Vector2, label: String, font: Font, font_size: int) -> void:
	label = tr(label)
	draw_circle(center, radius, Color(.03,.05,.07,.5), true, -1, true)
	draw_arc(center, radius, 0, TAU, 48, Color(1,1,1,.45), 2 * unit, true)
	draw_circle(center + vector * radius * .65, 27 * unit, Color(1,1,1,.45), true, -1, true)
	var text_size := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	draw_string(font, center + Vector2(-text_size.x * .5, radius + 24 * unit), label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
