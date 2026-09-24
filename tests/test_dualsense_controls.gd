extends SceneTree
## Contrato de controle: gameplay, menus e troca de dispositivo sem hardware físico.
var failures := 0

func check(ok: bool,message: String) -> void:
	print(("PASS " if ok else "FAIL ")+message)
	if not ok: failures += 1

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var controls := root.get_node("GameInput")
	controls.reset_bindings()
	check(_has_button("interact",JOY_BUTTON_X),"□ executa a ação geral")
	check(_has_button("reload",JOY_BUTTON_X),"□ recarrega a arma equipada")
	check(_has_button("vehicle_interact",JOY_BUTTON_Y),"△ entra ou rouba um veículo")
	check(not _has_button("interact",JOY_BUTTON_Y) and not _has_button("vehicle_interact",JOY_BUTTON_X),"ação e roubo de veículo não disparam juntos")
	check(_has_button("exit_vehicle",JOY_BUTTON_Y) and not _has_button("exit_vehicle",JOY_BUTTON_B),"△ também sai do veículo; ○ fica para voltar")
	check(_has_button("handbrake",JOY_BUTTON_A),"✕ aciona o freio de mão")
	check(_has_button("horn",JOY_BUTTON_RIGHT_STICK) and _has_button("siren_toggle",JOY_BUTTON_RIGHT_STICK),"R3 aciona buzina ou sirene")
	check(_has_button("radio_previous",JOY_BUTTON_LEFT_SHOULDER) and _has_button("radio_next",JOY_BUTTON_RIGHT_SHOULDER),"L1 volta e R1 avança a estação")
	check(_has_button("world_map",JOY_BUTTON_TOUCHPAD),"touchpad abre o mapa")
	check(_has_button("weapon_flashlight",JOY_BUTTON_MISC1),"botão de microfone controla a lanterna")
	check(_has_axis("fire",JOY_AXIS_TRIGGER_RIGHT,1.0) and _has_axis("aim",JOY_AXIS_TRIGGER_LEFT,1.0),"R2 e L2 controlam disparo e mira")
	check(_has_axis("accelerate",JOY_AXIS_TRIGGER_RIGHT,1.0) and _has_axis("brake",JOY_AXIS_TRIGGER_LEFT,1.0),"R2 acelera e L2 freia no veículo")
	check(_has_axis("move_left",JOY_AXIS_LEFT_X,-1.0) and _has_axis("move_up",JOY_AXIS_LEFT_Y,-1.0),"analógico esquerdo controla movimento")
	check(_has_button("ui_accept",JOY_BUTTON_A) and _has_button("ui_cancel",JOY_BUTTON_B),"menus aceitam ✕ e ○")
	check(_has_button("pause_game",JOY_BUTTON_START) and not _has_button("pause_game",JOY_BUTTON_B),"somente Options abre a pausa")
	check(_has_button("ui_up",JOY_BUTTON_DPAD_UP) and _has_axis("ui_right",JOY_AXIS_LEFT_X,1.0),"menus aceitam direcional e analógico")
	var pad := InputEventJoypadButton.new()
	pad.device = 7
	pad.button_index = JOY_BUTTON_A
	pad.pressed = true
	controls._input(pad)
	check(controls.using_gamepad and controls.active_joypad == 7,"último controle usado vira o controle ativo")
	var l3 := InputEventJoypadButton.new()
	l3.device = 7
	l3.button_index = JOY_BUTTON_LEFT_STICK
	l3.pressed = true
	controls._input(l3)
	check(controls.sprinting(),"primeiro clique no L3 ativa a corrida")
	controls._input(l3)
	check(not controls.sprinting(),"segundo clique no L3 desativa a corrida")
	var mouse := InputEventMouseButton.new()
	mouse.button_index = MOUSE_BUTTON_LEFT
	mouse.pressed = true
	controls._input(mouse)
	check(not controls.using_gamepad,"clique restaura dicas de teclado e mouse")
	controls.using_gamepad = true
	controls.active_joypad = -1
	check(controls.hint("fire") == "RT" and controls.hint("ui_cancel") == "B","fallback genérico mantém prompts legíveis sem hardware")
	check(controls._pad_button_hint(JOY_BUTTON_A,true) == "✕" and controls._pad_button_hint(JOY_BUTTON_B,true) == "○","layout PlayStation usa os símbolos do DualSense")
	controls.aim_direction = Vector2.RIGHT
	check(controls._update_gamepad_aim(Vector2.LEFT,1.0/60.0) and controls.aim_direction.x>0.95,"mira não salta instantaneamente para a direção oposta")
	for frame in 45: controls._update_gamepad_aim(Vector2.LEFT,1.0/60.0)
	check(controls.aim_direction.x < -0.95,"mira ainda alcança rapidamente a direção desejada")
	var aim_before_deadzone: Vector2 = controls.aim_direction
	check(not controls._update_gamepad_aim(Vector2(0.1,0.05),1.0/60.0) and controls.aim_direction.is_equal_approx(aim_before_deadzone),"zona morta evita tremor fino na mira")
	Input.action_press("accelerate",0.85)
	check(controls.vehicle_input().y>0.8,"gatilho R2 produz aceleração analógica")
	Input.action_release("accelerate")
	Input.action_press("brake",0.7)
	check(controls.vehicle_input().y < -0.65,"gatilho L2 produz frenagem analógica")
	Input.action_release("brake")
	var pause_scene: PackedScene = load("res://ui/PauseMenu.tscn")
	var pause_menu: CanvasLayer = pause_scene.instantiate()
	root.add_child(pause_menu)
	await process_frame
	paused = false
	pause_menu.visible = false
	var circle := InputEventJoypadButton.new()
	circle.button_index = JOY_BUTTON_B
	circle.pressed = true
	pause_menu._unhandled_input(circle)
	check(not pause_menu.visible and not paused,"○ não abre a pausa durante o jogo")
	var options := InputEventJoypadButton.new()
	options.button_index = JOY_BUTTON_START
	options.pressed = true
	pause_menu._unhandled_input(options)
	check(pause_menu.visible and paused,"Options abre a pausa")
	pause_menu._unhandled_input(circle)
	check(not pause_menu.visible and not paused,"○ volta ao jogo quando a pausa já está aberta")
	pause_menu.queue_free()
	await process_frame
	controls.reset_bindings()
	check(_count_button("ui_accept",JOY_BUTTON_A) == 1,"reinicializar controles não duplica atalhos de menu")
	print("DUALSENSE CONTROLS: ",failures," falha(s)")
	quit(0 if failures == 0 else 1)

func _has_button(action: StringName,button: JoyButton) -> bool:
	return _count_button(action,button)>0

func _count_button(action: StringName,button: JoyButton) -> int:
	var count := 0
	for event in InputMap.action_get_events(action):
		if event is InputEventJoypadButton and event.button_index == button: count += 1
	return count

func _has_axis(action: StringName,axis: JoyAxis,value: float) -> bool:
	for event in InputMap.action_get_events(action):
		if event is InputEventJoypadMotion and event.axis == axis and is_equal_approx(event.axis_value,value): return true
	return false
