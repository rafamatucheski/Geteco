extends CanvasLayer
## Perfil horizontal de toque, ativado em mobile ou com --touch-ui para revisão.
var canvas: Control
var left_id := -1
var right_id := -1
var left_center := Vector2.ZERO
var right_center := Vector2.ZERO
var left_tip := Vector2.ZERO
var right_tip := Vector2.ZERO
var touches := {}
var buttons := {}
var _blocked := true
var _touch_firing := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 85
	canvas = Control.new()
	canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(canvas)
	canvas.draw.connect(_draw)

func _process(_delta: float) -> void:
	var player := get_tree().get_first_node_in_group("player")
	_blocked = player == null or get_tree().paused or bool(player.get("is_in_dialogue")) or bool(player.get("is_control_disabled")) or bool(player.get("is_dead"))
	canvas.visible = not _blocked
	if _blocked:
		_release_all()
		return
	var rect := get_viewport().get_visible_rect()
	var margin := Vector2(28,28)
	if DisplayServer.get_name() != "headless" and OS.has_feature("mobile"):
		var safe := DisplayServer.get_display_safe_area()
		var ratio: Vector2 = rect.size/Vector2(DisplayServer.screen_get_size())
		margin.x += maxf(safe.position.x,DisplayServer.screen_get_size().x-safe.end.x)*ratio.x
		margin.y += maxf(safe.position.y,DisplayServer.screen_get_size().y-safe.end.y)*ratio.y
	left_center = Vector2(margin.x+80,rect.size.y-margin.y-80)
	right_center = Vector2(rect.size.x-margin.x-100,rect.size.y-margin.y-80)
	buttons = {"interact":Vector2(rect.size.x-margin.x-80,rect.size.y-margin.y-205),"weapon_next":Vector2(rect.size.x-margin.x-195,rect.size.y-margin.y-160),"pause_game":Vector2(rect.size.x*0.5,margin.y+32)}
	var car: Node = get_node("/root/RegionTravel").controlled_car()
	if car != null:
		buttons.erase("weapon_next")
		buttons["handbrake"] = Vector2(rect.size.x-margin.x-195,rect.size.y-margin.y-160)
	canvas.queue_redraw()

func _input(event: InputEvent) -> void:
	if _blocked: return
	if event is InputEventScreenTouch:
		if event.pressed:
			for action in buttons:
				if event.position.distance_to(buttons[action])<36:
					touches[event.index] = action
					_action(action,true)
					get_viewport().set_input_as_handled()
					return
			if event.position.distance_to(left_center)<95 and left_id<0: left_id = event.index
			elif event.position.distance_to(right_center)<95 and right_id<0: right_id = event.index
		else:
			if touches.has(event.index):
				_action(touches[event.index],false)
				touches.erase(event.index)
			if event.index == left_id:
				left_id = -1
				left_tip = Vector2.ZERO
				get_node("/root/GameInput").touch_move = Vector2.ZERO
			if event.index == right_id:
				right_id = -1
				right_tip = Vector2.ZERO
				get_node("/root/GameInput").touch_aim = Vector2.ZERO
				_action("fire",false)
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		if event.index == left_id:
			left_tip = (event.position-left_center).limit_length(55)
			get_node("/root/GameInput").touch_move = left_tip/55
		elif event.index == right_id:
			right_tip = (event.position-right_center).limit_length(55)
			get_node("/root/GameInput").touch_aim = right_tip/55
			if get_node("/root/RegionTravel").controlled_car() == null: _action("fire",right_tip.length()>20)
		get_viewport().set_input_as_handled()

func _draw() -> void:
	for center in [left_center,right_center]:
		canvas.draw_circle(center,66,Color(0.06,0.09,0.12,0.65))
		canvas.draw_arc(center,66,0,TAU,48,Color("85949c"),2,true)
	canvas.draw_circle(left_center+left_tip,26,Color(0.9,0.85,0.75,0.75))
	canvas.draw_circle(right_center+right_tip,26,Color("ff914d"))
	for action in buttons:
		var center: Vector2 = buttons[action]
		canvas.draw_circle(center,34,Color("19242d"))
		canvas.draw_arc(center,34,0,TAU,32,Color("ff914d"),2,true)
		var text: String = {"interact":"A","weapon_next":"↻","pause_game":"Ⅱ","handbrake":"B"}[action]
		canvas.draw_string(ThemeDB.fallback_font,center+Vector2(-9,8),text,HORIZONTAL_ALIGNMENT_LEFT,-1,23,Color("efe7d8"))

func _action(action: String,pressed: bool) -> void:
	if action == "fire":
		if _touch_firing == pressed: return
		_touch_firing = pressed
	var e := InputEventAction.new()
	e.action = action
	e.pressed = pressed
	Input.parse_input_event(e)

func _release_all() -> void:
	for action in touches.values(): _action(action,false)
	touches.clear()
	left_id = -1
	right_id = -1
	left_tip = Vector2.ZERO
	right_tip = Vector2.ZERO
	get_node("/root/GameInput").touch_move = Vector2.ZERO
	get_node("/root/GameInput").touch_aim = Vector2.ZERO
	if _touch_firing: _action("fire",false)

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and is_inside_tree(): _release_all()
