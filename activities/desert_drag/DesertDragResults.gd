extends Control
## A finished attempt remains inspectable until the player chooses where to go.
const FONT := preload("res://assets/fonts/barlow/BarlowSemiCondensed-SemiBold.ttf")
const REGULAR := preload("res://assets/fonts/barlow/BarlowSemiCondensed-Regular.ttf")
const INK := Color("11161c")
const TEXT := Color("f5f2ea")
const MUTED := Color("9ba7b0")
const ACCENT := Color("ff633b")
signal action_requested(action: String)
var result: Dictionary = {}
var rival_name := ""
var message := ""
var buttons: Array[Button] = []

func _ready() -> void:
	custom_minimum_size=Vector2(740,480)
	size=custom_minimum_size
	mouse_filter=Control.MOUSE_FILTER_STOP
	for item in [["rematch","REVANCHE"],["entry","VOLTAR À ENTRADA"],["stay","FICAR AQUI"]]:
		var button := Button.new()
		button.name=str(item[0])
		button.text=str(item[1])
		button.position=Vector2(32+buttons.size()*228,366)
		button.size=Vector2(220,62)
		button.add_theme_font_override("font",FONT)
		button.add_theme_font_size_override("font_size",20)
		button.add_theme_color_override("font_color",INK if buttons.is_empty() else TEXT)
		button.add_theme_color_override("font_hover_color",INK)
		button.add_theme_color_override("font_focus_color",INK if buttons.is_empty() else TEXT)
		button.add_theme_color_override("font_pressed_color",INK)
		for state in ["normal","hover","pressed","disabled"]:
			var style := StyleBoxFlat.new()
			style.bg_color=ACCENT if buttons.is_empty() or state in ["hover","pressed"] else Color("222b34")
			if state=="disabled": style.bg_color=Color("222b34")
			style.set_corner_radius_all(3)
			button.add_theme_stylebox_override(state,style)
		var focus := StyleBoxFlat.new()
		focus.bg_color=Color.TRANSPARENT
		focus.border_color=TEXT
		focus.set_border_width_all(2)
		focus.set_corner_radius_all(3)
		button.add_theme_stylebox_override("focus",focus)
		button.pressed.connect(func(): action_requested.emit(str(item[0])))
		add_child(button)
		buttons.append(button)
	for i in buttons.size():
		var next := buttons[(i+1)%buttons.size()]
		var previous := buttons[(i+buttons.size()-1)%buttons.size()]
		buttons[i].focus_neighbor_right=buttons[i].get_path_to(next)
		buttons[i].focus_next=buttons[i].get_path_to(next)
		buttons[i].focus_neighbor_left=buttons[i].get_path_to(previous)
		buttons[i].focus_previous=buttons[i].get_path_to(previous)

func show_result(value: Dictionary, opponent: String) -> void:
	result=value.duplicate(true)
	rival_name=opponent
	message=""
	set_busy(false)
	queue_redraw()
	_focus_primary.call_deferred()

func _focus_primary() -> void:
	if is_visible_in_tree() and not buttons.is_empty(): buttons[0].grab_focus()

func set_busy(busy: bool) -> void:
	for button in buttons: button.disabled=busy
	message="Preparando a entrada…" if busy else ""
	queue_redraw()

func set_message(value: String) -> void:
	message=value
	queue_redraw()

func _label(at: Vector2, value: String, height: int, color := TEXT, strong := true) -> void:
	draw_string(FONT if strong else REGULAR,at,value,HORIZONTAL_ALIGNMENT_LEFT,-1,height,color)

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO,size),INK)
	draw_rect(Rect2(0,0,size.x,4),ACCENT)
	draw_rect(Rect2(0,0,size.x,size.y),Color("35424d"),false,1)
	_label(Vector2(32,40),"ARRANCADA   /   800 M",16,MUTED)
	_label(Vector2(32,109),"VITÓRIA" if result.get("won",false) else "DERROTA",60)
	var player_time := float(result.get("seconds",0.0))
	var opponent_time := float(result.get("rival_seconds",-1.0))
	var gap := absf(player_time-opponent_time)
	var detail := "%.3f s %s"%[gap,"À FRENTE" if result.get("won",false) else "ATRÁS"] if opponent_time>0 else "RIVAL NÃO COMPLETOU"
	_label(Vector2(34,144),detail,20,ACCENT)
	draw_line(Vector2(32,170),Vector2(708,170),Color("35424d"),1)
	_label(Vector2(32,202),"DANTE",18,MUTED)
	_label(Vector2(394,202),rival_name.to_upper(),18,MUTED)
	_label(Vector2(32,257),"%.3f"%player_time,46)
	_label(Vector2(394,257),"%.3f"%opponent_time if opponent_time>0 else "DNF",46)
	_label(Vector2(235,254),"s",22,MUTED)
	if opponent_time>0: _label(Vector2(597,254),"s",22,MUTED)
	draw_line(Vector2(364,190),Vector2(364,268),Color("35424d"),1)
	_label(Vector2(32,307),"SEU RECORDE   %.3f s"%float(result.get("best_seconds",player_time)),19,MUTED)
	if result.get("first_win",false):
		_label(Vector2(394,307),"RIVAL SUPERADO",19,ACCENT)
	elif result.get("won",false):
		_label(Vector2(394,307),"REVANCHE VENCIDA",19,ACCENT)
	if not str(result.get("instrument_unlock","")).is_empty():
		_label(Vector2(32,340),"NOVO PAINEL DISPONÍVEL: "+str(result.instrument_unlock).to_upper(),16,ACCENT)
	_label(Vector2(32,457),message if not message.is_empty() else "Esc / B  Ficar aqui",16,MUTED,false)
