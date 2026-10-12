extends CanvasLayer
const STYLE := preload("res://ui/GameStyle.gd")
const MODE := preload("res://runtime/DeveloperMode.gd")
var world: Node3D
var pause_menu: CanvasLayer
var tools: Node
var surface: Control
var status: Label
var position_label: Label
var enabled_toggle: CheckButton
var god_toggle: CheckButton
var flight_button: Button
var speed: OptionButton
var destinations: OptionButton
var coordinates: Array[SpinBox] = []
var timer: Timer
var _syncing := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 110
	visible = false
	tools = MODE.new()
	tools.world = world
	add_child(tools)
	tools.changed.connect(_refresh)

func _input(event: InputEvent) -> void:
	if world.has_meta("menu_preview") or world.session == null or not world.session.ready_for_play: return
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_F10:
		if visible: close_panel(true)
		else: open_panel()
		get_viewport().set_input_as_handled()
	elif visible and (event.is_action_pressed("pause_game") or event.is_action_pressed("ui_cancel")):
		close_panel(false)
		get_viewport().set_input_as_handled()
	elif tools.flying and not get_tree().paused:
		if event.is_action_pressed("pause_game"):
			open_panel()
		elif event.is_action_pressed("camera_left") or event.is_action_pressed("camera_right"):
			world.camera._unhandled_input(event)
		# Input's pressed state remains available for flight, but gameplay callbacks do not run.
		get_viewport().set_input_as_handled()

func open_panel() -> void:
	if tools.busy or world.session == null or not world.session.ready_for_play: return
	if world.session.modal or world.session.is_transition_blocked(): return
	if pause_menu.settings != null and pause_menu.settings.visible: return
	if surface == null: _build()
	if not pause_menu.visible: pause_menu.pause_game()
	pause_menu.get_node("RootControl").hide()
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_refresh_destinations()
	_refresh()
	timer.start()
	enabled_toggle.grab_focus()

func close_panel(resume: bool) -> void:
	if tools.busy: return
	visible = false
	if timer != null: timer.stop()
	pause_menu.get_node("RootControl").show()
	if resume: pause_menu.resume_game()
	else: pause_menu.pause_game()

func _button(parent: Node, text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 38
	parent.add_child(button)
	button.pressed.connect(callback)
	return button

func _section(parent: Node, text: String) -> void:
	parent.add_child(STYLE.label(text,20,STYLE.ACCENT))

func _build() -> void:
	surface = Control.new()
	surface.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	surface.theme = STYLE.create_theme(18)
	add_child(surface)
	var dim := ColorRect.new()
	dim.color = Color(0,0,0,.7)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	surface.add_child(dim)
	var outer := MarginContainer.new()
	outer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left","right","top","bottom"]: outer.add_theme_constant_override("margin_"+side,28)
	surface.add_child(outer)
	var panel := PanelContainer.new()
	outer.add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation",12)
	scroll.add_child(column)
	var heading := HBoxContainer.new()
	column.add_child(heading)
	var title := STYLE.label("DESENVOLVEDOR",28)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(title)
	_button(heading,"Voltar à pausa",func(): close_panel(false))
	_button(heading,"Jogar · F10",func(): close_panel(true))
	enabled_toggle = CheckButton.new()
	enabled_toggle.text = "Modo desenvolvedor · suspende o salvamento"
	column.add_child(enabled_toggle)
	enabled_toggle.toggled.connect(func(value):
		if not _syncing: tools.set_active(value); _refresh())
	position_label = STYLE.label("",16,STYLE.MUTED)
	column.add_child(position_label)
	_section(column,"MOVIMENTO")
	var movement := HBoxContainer.new()
	column.add_child(movement)
	movement.add_child(STYLE.label("Velocidade a pé",18))
	speed = OptionButton.new()
	for multiplier in [1,2,5,10]: speed.add_item("%d×" % multiplier,multiplier)
	movement.add_child(speed)
	speed.item_selected.connect(func(index): tools.set_speed(float(speed.get_item_id(index))))
	god_toggle = CheckButton.new()
	god_toggle.text = "Invulnerável"
	movement.add_child(god_toggle)
	god_toggle.toggled.connect(func(value):
		if not _syncing: tools.set_invincible(value))
	flight_button = _button(movement,"Ativar voo sem colisão",func():
		if tools.flying: tools.land()
		elif tools.begin_flight(): close_panel(true))
	_button(movement,"Voltar ao início do voo",func(): await tools.return_to_anchor())
	var flight_row := HBoxContainer.new()
	column.add_child(flight_row)
	flight_row.add_child(STYLE.label("Voo (m/s)",18))
	var flight_rate := SpinBox.new()
	flight_rate.min_value = 5; flight_rate.max_value = 100; flight_rate.step = 5; flight_rate.value = 25
	flight_row.add_child(flight_rate)
	flight_rate.value_changed.connect(func(value): tools.flight_speed = value)
	flight_row.add_child(STYLE.label("WASD move · Espaço sobe · Ctrl desce · Shift acelera",16,STYLE.MUTED))
	_section(column,"TELETRANSPORTE")
	var travel := HBoxContainer.new()
	column.add_child(travel)
	destinations = OptionButton.new()
	destinations.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	travel.add_child(destinations)
	_button(travel,"Ir ao destino",_travel_selected)
	var xyz := HBoxContainer.new()
	column.add_child(xyz)
	for axis in ["X","Y","Z"]:
		xyz.add_child(STYLE.label(axis,18))
		var coordinate := SpinBox.new()
		coordinate.min_value = -10000; coordinate.max_value = 10000; coordinate.step = .1
		coordinate.custom_minimum_size.x = 125
		xyz.add_child(coordinate)
		coordinates.append(coordinate)
	_button(xyz,"Usar posição atual",_copy_position_to_fields)
	_button(xyz,"Teleportar",func(): await tools.teleport_to(Vector3(coordinates[0].value,coordinates[1].value,coordinates[2].value)))
	_section(column,"PESSOAS DE TESTE")
	var people := HBoxContainer.new()
	column.add_child(people)
	_button(people,"+ Criar civil próximo",func(): tools.spawn_civilian())
	_button(people,"Remover último",func(): tools.remove_last_civilian())
	_button(people,"Limpar civis de teste",func(): tools.clear_civilians())
	_section(column,"DIAGNÓSTICO")
	var diagnostics := HBoxContainer.new()
	column.add_child(diagnostics)
	_button(diagnostics,"Copiar coordenadas",func(): DisplayServer.clipboard_set(str(world.player.global_position)))
	_button(diagnostics,"Abrir logs",func(): OS.shell_open(ProjectSettings.globalize_path("user://session-logs")))
	status = STYLE.label("",18,STYLE.ACCENT)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(status)
	timer = Timer.new()
	timer.wait_time = .3
	timer.timeout.connect(_refresh)
	add_child(timer)
	_copy_position_to_fields()
	STYLE.trap_focus(surface)

func _copy_position_to_fields() -> void:
	var point: Vector3 = world.player.global_position
	for index in 3: coordinates[index].value = point[index]

func _refresh_destinations() -> void:
	destinations.clear()
	for pair in [["Harbor","harbor"],["Montanha","mountain"],["Deserto · requer campanha","desert"]]:
		destinations.add_item(pair[0])
		destinations.set_item_metadata(destinations.item_count-1,{"region":pair[1]})
	for entry in world.production.region.entries:
		if not entry.has("return_position"): continue
		destinations.add_item(str(entry.get("name",entry.get("id","Ponto"))))
		destinations.set_item_metadata(destinations.item_count-1,{"point":entry.return_position})

func _travel_selected() -> void:
	var entry: Dictionary = destinations.get_selected_metadata()
	if entry.has("region"): await tools.travel_to(entry.region)
	else: await tools.teleport_to(entry.point)
	_refresh_destinations()

func _refresh() -> void:
	if surface == null: return
	_syncing = true
	enabled_toggle.set_pressed_no_signal(tools.active)
	enabled_toggle.disabled = tools.busy
	god_toggle.set_pressed_no_signal(tools.invincible)
	god_toggle.disabled = not tools.active
	speed.disabled = not tools.active
	for index in speed.item_count:
		if speed.get_item_id(index) == int(tools.speed_multiplier): speed.select(index)
	flight_button.text = "Pousar e restaurar colisão" if tools.flying else "Ativar voo sem colisão"
	flight_button.disabled = not tools.active or tools.busy
	status.text = tools.message
	var point: Vector3 = world.player.global_position
	position_label.text = String(TranslationServer.translate("%s · X %.1f  Y %.1f  Z %.1f · %d FPS · %d civis de teste")) % [world.session.state.region_id,point.x,point.y,point.z,Engine.get_frames_per_second(),tools.civilians.size()]
	_syncing = false
