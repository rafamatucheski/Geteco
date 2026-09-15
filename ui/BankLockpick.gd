extends CanvasLayer
signal unlocked
signal cancelled
var angle := 0.0
var target_angle := 1.5
var pins := 0
var mistakes := 0
var active := false
var dial: Control
var info: Label
var panel: PanelContainer
var lock_title := "COFRE"
var instruction_text := "ESPAÇO / CLIQUE — travar na faixa verde\nESC — desistir • O alarme continua!"
var required_pins := 3
var allowed_mistakes := 3

func _ready() -> void:
	layer=75
	panel=PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.offset_left=-190
	panel.offset_top=-180
	panel.offset_right=190
	panel.offset_bottom=180
	var style := StyleBoxFlat.new()
	style.bg_color=Color("172126")
	style.border_color=Color("a99974")
	style.set_border_width_all(2)
	style.content_margin_left=20
	style.content_margin_right=20
	style.content_margin_top=16
	style.content_margin_bottom=16
	panel.add_theme_stylebox_override("panel",style)
	add_child(panel)
	var column := VBoxContainer.new()
	panel.add_child(column)
	info=Label.new()
	info.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(info)
	dial=Control.new()
	dial.custom_minimum_size=Vector2(330,235)
	dial.mouse_filter=Control.MOUSE_FILTER_IGNORE
	dial.draw.connect(_draw_dial)
	column.add_child(dial)
	var instructions := Label.new()
	instructions.text=instruction_text
	instructions.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(instructions)
	hide()
func begin() -> void:
	pins=0
	mistakes=0
	angle=0
	target_angle=randf_range(.8,5.5)
	active=true
	show()
	_refresh()
func _process(delta: float) -> void:
	if not active: return
	angle=fposmod(angle+delta*(1.45+pins*.3),TAU)
	dial.queue_redraw()
func _input(event: InputEvent) -> void:
	if not active: return
	if event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_LEFT:
		attempt()
		get_viewport().set_input_as_handled()
	elif event.is_pressed() and not event.is_echo():
		if event.is_action_pressed("ui_cancel"):
			finish(false)
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("ui_accept"):
			attempt()
			get_viewport().set_input_as_handled()
func attempt() -> void:
	if not active: return
	if absf(angle_difference(angle,target_angle))<=.32:
		pins+=1
		if pins==required_pins:
			finish(true)
			return
		target_angle=fposmod(target_angle+randf_range(1.2,3.6),TAU)
	else:
		mistakes+=1
		if mistakes>=allowed_mistakes:
			finish(false)
			return
	_refresh()
func finish(success: bool) -> void:
	active=false
	hide()
	if success: unlocked.emit()
	else: cancelled.emit()
func _refresh() -> void:
	info.text="%s — TRAVAS %d/%d • ERROS %d/%d"%[lock_title,pins,required_pins,mistakes,allowed_mistakes]
func _draw_dial() -> void:
	var center := dial.size*.5
	dial.draw_circle(center,91,Color("333f42"))
	dial.draw_arc(center,80,0,TAU,64,Color("879397"),3,true)
	dial.draw_arc(center,80,target_angle-.32,target_angle+.32,16,Color("82c69b"),12,true)
	for i in 24:
		var direction := Vector2.from_angle(float(i)*TAU/24)
		dial.draw_line(center+direction*65,center+direction*71,Color("7e898c"),1,true)
	dial.draw_line(center,center+Vector2.from_angle(angle)*85,Color("f0db9e"),4,true)
	dial.draw_circle(center,9,Color("ad9a75"))
