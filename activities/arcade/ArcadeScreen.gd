extends CanvasLayer
## One native 2D canvas; no SubViewport or per-frame node allocation.
const GAMES := {
	"pinball":preload("res://activities/arcade/games/PinballGame.gd"),
	"blocks":preload("res://activities/arcade/games/BlocksGame.gd"),
	"racer":preload("res://activities/arcade/games/RacerGame.gd"),
	"fighter":preload("res://activities/arcade/games/FighterGame.gd"),
}
const ACCENTS := {"pinball":Color("f6b75a"),"blocks":Color("73d9d0"),"racer":Color("ba9bff"),"fighter":Color("ff807c")}
var adapter
var game
var best := 0
var game_id := ""
var playing := false
var suspended := false
var armed := false
var previous: Dictionary = {}
var touch: Dictionary = {}
var root_control: Control
var board: Control
var frame: PanelContainer
var heading: Label
var score_label: Label
var instruction_label: Label
var start_button: Button
var pause_button: Button
var touch_row: HBoxContainer
var accent := Color.WHITE
var cabinet_audio: Node

func _ready() -> void:
	layer = 86
	cabinet_audio = preload("res://activities/arcade/ArcadeAudio.gd").new()
	add_child(cabinet_audio)
	root_control = Control.new()
	root_control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root_control)
	var shade := ColorRect.new()
	shade.color = Color(.008,.01,.025,.94)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root_control.add_child(shade)
	frame = PanelContainer.new()
	root_control.add_child(frame)
	var shell := StyleBoxFlat.new()
	shell.bg_color = Color("141629")
	shell.border_color = Color("41435d")
	shell.set_border_width_all(2)
	shell.set_corner_radius_all(16)
	shell.set_content_margin_all(18)
	frame.add_theme_stylebox_override("panel",shell)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation",10)
	frame.add_child(column)
	var header := HBoxContainer.new()
	column.add_child(header)
	heading = Label.new()
	heading.add_theme_font_size_override("font_size",26)
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(heading)
	score_label = Label.new()
	score_label.add_theme_font_size_override("font_size",19)
	header.add_child(score_label)
	board = Control.new()
	board.clip_contents = true
	board.size_flags_vertical = Control.SIZE_EXPAND_FILL
	board.mouse_filter = Control.MOUSE_FILTER_IGNORE
	board.draw.connect(_draw_board)
	column.add_child(board)
	instruction_label = Label.new()
	instruction_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	instruction_label.add_theme_font_size_override("font_size",16)
	instruction_label.add_theme_color_override("font_color",Color("c3c5d9"))
	column.add_child(instruction_label)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation",12)
	column.add_child(actions)
	start_button = _button("Jogar", start_game, actions)
	pause_button = _button("Pausar", toggle_pause, actions)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(spacer)
	_button("Sair", adapter.close, actions)
	touch_row = HBoxContainer.new()
	touch_row.add_theme_constant_override("separation",10)
	column.add_child(touch_row)
	for entry in [["left","◀"],["right","▶"],["up","▲"],["down","▼"],["action","A"],["action_alt","B"]]:
		var key: String = entry[0]
		var button := _button(entry[1],Callable(),touch_row)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.button_down.connect(func(): touch[key] = true)
		button.button_up.connect(func(): touch[key] = false)
	root_control.resized.connect(_layout)
	_layout()
	dismiss()

func _button(label: String, callback: Callable, parent: Node) -> Button:
	var button := Button.new()
	button.text = label
	button.custom_minimum_size = Vector2(110,38)
	# Gameplay actions never activate a focused UI button a second time.
	button.focus_mode = Control.FOCUS_NONE
	if callback.is_valid(): button.pressed.connect(callback)
	parent.add_child(button)
	return button

func _layout() -> void:
	var available := root_control.size-Vector2(28,28)
	frame.size = Vector2(minf(1040,available.x),minf(720,available.y))
	frame.position = (root_control.size-frame.size)*.5
	if is_instance_valid(board): board.queue_redraw()

func open_game(id: String, high_score: int) -> void:
	game_id = id
	game = GAMES[id].new()
	game.reset(randi())
	best = high_score
	accent = ACCENTS[id]
	heading.text = "FAGULHA  /  "+game.title()
	heading.add_theme_color_override("font_color",accent)
	playing = false
	suspended = false
	armed = false
	previous.clear()
	touch.clear()
	var controls := get_node_or_null("/root/GameInput")
	touch_row.visible = DisplayServer.is_touchscreen_available() or (controls != null and controls.get_meta("touch_controls_active",false))
	show()
	set_process(true)
	_refresh()

func dismiss() -> void:
	hide()
	if is_instance_valid(cabinet_audio): cabinet_audio.stop()
	playing = false
	touch.clear()
	set_process(false)

func start_game() -> void:
	if game == null: return
	if playing and not game.finished: return
	adapter.record_score()
	game.reset(randi())
	playing = true
	cabinet_audio.start(game_id)
	suspended = false
	armed = false
	previous.clear()
	_refresh()

func toggle_pause() -> void:
	if not playing or game.finished: return
	suspended = not suspended
	cabinet_audio.pause_audio(suspended)
	armed = false
	_refresh()

func handle_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause_game") or event.is_action_pressed("ui_cancel"):
		adapter.close()
	elif event.is_action_pressed("interact") or event.is_action_pressed("ui_accept"):
		if not playing or game.finished: start_game()
	elif event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_P:
		toggle_pause()

func controls_now() -> Dictionary:
	var input := {}
	for direction in ["left","right","up","down"]:
		input[direction] = Input.is_action_pressed("move_"+direction) or Input.is_action_pressed("ui_"+direction) or touch.get(direction,false)
	# ui_accept shares Space/gamepad A with handbrake. Keep the two game
	# buttons disjoint so a hard drop cannot also rotate or a kick also punch.
	input.action = Input.is_action_pressed("interact") or Input.is_physical_key_pressed(KEY_ENTER) or Input.is_physical_key_pressed(KEY_KP_ENTER) or touch.get("action",false)
	input.action_alt = Input.is_action_pressed("handbrake") or Input.is_action_pressed("sprint") or Input.is_physical_key_pressed(KEY_X) or touch.get("action_alt",false)
	return input

func _process(delta: float) -> void:
	if not visible or game == null: return
	var controls := controls_now()
	if not armed:
		if not controls.values().has(true): armed = true
		previous = controls
	elif playing and not suspended and not game.finished:
		for key in ["left","right","up","down","action","action_alt"]:
			controls[key+"_pressed"] = controls[key] and not previous.get(key,false)
		game.step(minf(delta,.05),controls)
		for sound in game.sound_events: cabinet_audio.play(sound)
		game.sound_events.clear()
		if game_id == "racer": cabinet_audio.update_engine(game.speed,game.boosting)
		previous = controls
		if game.finished:
			adapter.record_score()
			cabinet_audio.stop()
			cabinet_audio.play("finish")
	_refresh()

func _refresh() -> void:
	score_label.text = String(TranslationServer.translate("%06d   /   REC %06d")) % [game.score,best]
	start_button.text = "Jogar novamente" if playing and game.finished else "Jogar"
	start_button.visible = not playing or game.finished
	pause_button.visible = playing and not game.finished
	pause_button.text = "Continuar" if suspended else "Pausar · P"
	var controls := get_node_or_null("/root/GameInput")
	var action: String = controls.hint("interact") if controls != null else "E"
	var left: String = controls.hint("move_left") if controls != null else "A"
	var right: String = controls.hint("move_right") if controls != null else "D"
	var alternate: String = controls.hint("handbrake") if controls != null else "Espaço"
	instruction_label.text = game.instructions()+String(TranslationServer.translate("\n%s / %s ou direcional · Ação: %s / Enter · Alternativa: %s · Esc / Voltar: sair")) % [left,right,action,alternate]
	board.queue_redraw()

func _draw_board() -> void:
	if game == null: return
	board.draw_rect(Rect2(Vector2.ZERO,board.size),Color("080c18"))
	var factor := minf(board.size.x/800.0,board.size.y/480.0)
	var area := Rect2((board.size-Vector2(800,480)*factor)*.5,Vector2(800,480)*factor)
	game.render(board,area)
	# Clip overscan artwork to the cabinet screen, including letterbox bars.
	var black := Color("080c18")
	if area.position.x > 0:
		board.draw_rect(Rect2(0,0,area.position.x,board.size.y),black)
		board.draw_rect(Rect2(area.end.x,0,board.size.x-area.end.x,board.size.y),black)
	if area.position.y > 0:
		board.draw_rect(Rect2(0,0,board.size.x,area.position.y),black)
		board.draw_rect(Rect2(0,area.end.y,board.size.x,board.size.y-area.end.y),black)
	if not playing or suspended or game.finished:
		board.draw_rect(Rect2(Vector2.ZERO,board.size),Color(.01,.015,.04,.78))
		var font := ThemeDB.fallback_font
		var headline: String = "PAUSADO" if suspended else game.status if playing and game.finished else game.title().to_upper()
		headline = tr(headline)
		var size := 30
		var width := font.get_string_size(headline,HORIZONTAL_ALIGNMENT_LEFT,-1,size).x
		board.draw_string(font,Vector2((board.size.x-width)*.5,board.size.y*.48),headline,HORIZONTAL_ALIGNMENT_LEFT,-1,size,accent)
		var hint := "Continuar · P" if suspended else "Jogar novamente · Enter" if playing else "Jogar · Enter"
		hint = tr(hint)
		width = font.get_string_size(hint,HORIZONTAL_ALIGNMENT_LEFT,-1,18).x
		board.draw_string(font,Vector2((board.size.x-width)*.5,board.size.y*.48+36),hint,HORIZONTAL_ALIGNMENT_LEFT,-1,18,Color("e0e5f2"))
