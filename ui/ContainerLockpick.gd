extends CanvasLayer
## Angle + torque, with an undisclosed sweet spot. No random success roll.
signal resolved(result: String)
const SWEET_SPOT := 7.0
const BREAK_SECONDS := 1.25
var active := false
var angle := 0.0
var target_angle := 0.0
var turn := 0.0
var wear := 0.0
var pick_count := 0
var view: Control
var status: Label
var instructions: Label
var torque_armed := false
var pulse := 0.0

func _ready() -> void:
	layer = 85
	var shade := ColorRect.new()
	shade.color = Color(0.015,.022,.025,.76)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.offset_left = -290
	panel.offset_right = 290
	panel.offset_top = -240
	panel.offset_bottom = 240
	var style := StyleBoxFlat.new()
	style.bg_color = Color("172023")
	style.border_color = Color("a78a58")
	style.set_border_width_all(2)
	style.set_corner_radius_all(10)
	style.set_content_margin_all(20)
	panel.add_theme_stylebox_override("panel",style)
	add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation",12)
	panel.add_child(column)
	status = Label.new()
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status.add_theme_font_size_override("font_size",22)
	column.add_child(status)
	view = Control.new()
	view.custom_minimum_size = Vector2(530,320)
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	view.draw.connect(_draw_lock)
	column.add_child(view)
	instructions = Label.new()
	instructions.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	instructions.add_theme_font_size_override("font_size",17)
	column.add_child(instructions)
	hide()

func begin(count: int, secret_angle: float) -> void:
	pick_count = count
	target_angle = clampf(secret_angle,-75,75)
	angle = 0
	turn = 0
	wear = 0
	torque_armed = false
	active = true
	show()
	_refresh()

func _process(delta: float) -> void:
	if not active: return
	var torque := Input.is_action_pressed("interact") or Input.is_action_pressed("ui_accept") or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	if not torque: torque_armed = true
	var direction := Input.get_axis("move_left","move_right")
	if is_zero_approx(direction): direction = Input.get_axis("ui_left","ui_right")
	step(delta,direction,torque and torque_armed)

func step(delta: float, direction: float, torque: bool) -> void:
	if not active or not is_finite(delta) or delta <= 0: return
	delta = minf(delta,.1)
	pulse += delta
	if not torque:
		angle = clampf(angle+direction*85*delta,-85,85)
		turn = move_toward(turn,0,delta*2.5)
	else:
		var error := absf(angle-target_angle)
		var limit := 1.0 if error <= SWEET_SPOT else clampf(1.0-(error-SWEET_SPOT)/60.0,.04,.92)
		turn = move_toward(turn,limit,delta*.9)
		if turn >= .999: finish("opened"); return
		if error > SWEET_SPOT and turn >= limit-.005:
			wear += delta / BREAK_SECONDS
			if wear >= 1: finish("broken"); return
	_refresh()

func _input(event: InputEvent) -> void:
	if not active: return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause_game"):
		finish("cancelled")
	elif event is InputEventMouseMotion and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and not Input.is_action_pressed("interact") and turn < .02:
		angle = clampf(angle+event.relative.x*.35,-85,85)
	get_viewport().set_input_as_handled()

func finish(result: String) -> void:
	if not active: return
	active = false
	hide()
	resolved.emit(result)

func _refresh() -> void:
	status.text = "ARROMBAR  ·  LOCKPICKS: %d" % pick_count
	var controls := get_node_or_null("/root/GameInput")
	var left: String = controls.hint("move_left") if controls != null else "A"
	var right: String = controls.hint("move_right") if controls != null else "D"
	var action: String = controls.hint("interact") if controls != null else "E"
	instructions.text = "Mouse ou %s / %s — ajustar gazua\nSegure %s ou clique — girar · ESC / Voltar — sair" % [left,right,action]
	view.queue_redraw()

func _draw_lock() -> void:
	var center := view.size*.5+Vector2(0,-3)
	# Steel escutcheon, screws and a brass cylinder; feedback lives in the tools.
	view.draw_style_box(_plate(),Rect2(center-Vector2(119,115),Vector2(238,230)))
	for x in [-1,1]:
		for y in [-1,1]:
			var screw := center+Vector2(x*99,y*94)
			view.draw_circle(screw,6,Color("86908d"))
			view.draw_line(screw-Vector2(3,0),screw+Vector2(3,0),Color("303a3b"),2,true)
	view.draw_circle(center,84,Color("0a1013"))
	view.draw_circle(center,77,Color("ad925e"))
	view.draw_arc(center,73,0,TAU,80,Color("dfc38a"),3,true)
	view.draw_circle(center,58,Color("786643"))
	var axis := Vector2.DOWN.rotated(-turn*PI*.5)
	view.draw_line(center-axis*24,center+axis*28,Color("131a1b"),12,true)
	view.draw_circle(center-axis*23,9,Color("111819"))
	var shake := sin(pulse*65)*wear*3 if turn > .01 else 0.0
	var pick := Vector2.UP.rotated(deg_to_rad(angle+shake))
	view.draw_line(center-pick*9,center+pick*126,Color("c8ced0"),4,true)
	view.draw_line(center+pick*126,center+pick*151,Color("76503a"),10,true)
	view.draw_line(center+axis*5,center+axis*105,Color("a6b0b1"),6,true)
	view.draw_line(center+axis*105,center+axis*105+Vector2(35,0).rotated(-turn*PI*.5),Color("637778"),7,true)
	view.draw_rect(Rect2(115,view.size.y-13,300,5),Color("354043"))
	view.draw_rect(Rect2(115,view.size.y-13,300*(1-wear),5),Color("c78b58") if wear > .5 else Color("b1c0ac"))

func _plate() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("354348")
	style.border_color = Color("617171")
	style.set_border_width_all(3)
	style.set_corner_radius_all(15)
	return style
