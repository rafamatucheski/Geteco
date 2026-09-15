extends CanvasLayer
## Owns the conversation and ride. Vehicle boarding, signals and collisions stay shared.
var car: CharacterBody2D
var actor: CharacterBody2D
var state := "idle"
var driver_available := true
var panel: PanelContainer
var column: VBoxContainer
var map: Control
var status: Label
var destinations: Array[Dictionary] = []
var roads: Array = []
var buildings: Array = []
var markers := PackedVector2Array()
var place_buttons: Array[Button] = []
var bounds := Rect2()
var selected := -1
var destination := Vector2.ZERO
var destination_name := ""
var route: Array[Dictionary] = []
var leg_index := 0
var follow: PathFollow2D
var source_lane: Path2D
var saved_speed := 105.0
var _owns_dialogue := false
var _old_disabled := false
var _old_dialogue := false
var _stopped := 0.0
var _route_line := PackedVector2Array()

func _ready() -> void:
	layer = 80
	add_to_group("taxi_service")
	var dim := ColorRect.new()
	dim.color = Color(0.01,0.025,0.04,0.72)
	add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.name = "MapBackdrop"
	panel = PanelContainer.new()
	add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.offset_left = -510
	panel.offset_right = 510
	panel.offset_top = -290
	panel.offset_bottom = 290
	var style := StyleBoxFlat.new()
	style.bg_color = Color("101c25")
	style.border_color = Color("ffc526")
	style.set_border_width_all(2)
	style.set_content_margin_all(22)
	panel.add_theme_stylebox_override("panel",style)
	column = VBoxContainer.new()
	column.add_theme_constant_override("separation",12)
	panel.add_child(column)
	status = Label.new()
	add_child(status)
	status.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	status.offset_left = -360
	status.offset_right = 360
	status.offset_top = 92
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status.add_theme_color_override("font_color",Color("ffc526"))
	status.add_theme_color_override("font_shadow_color",Color.BLACK)
	status.add_theme_constant_override("shadow_offset_x",2)
	status.add_theme_constant_override("shadow_offset_y",2)
	hide()

func offer(vehicle: CharacterBody2D, pedestrian: CharacterBody2D) -> void:
	if state != "idle": return
	car = vehicle
	actor = pedestrian
	saved_speed = maxf(car.speed,105.0)
	var original_follow := car.get_parent() as PathFollow2D
	source_lane = original_follow.get_parent() as Path2D if original_follow else null
	state = "offer"
	_lock_dialogue()
	show()
	panel.show()
	get_node("MapBackdrop").show()
	status.hide()
	_clear()
	_title("NYC TAXI  /  LIVRE", "Motorista: Boa! Vai precisar de uma corrida?")
	_button(column,"Entrar como passageiro",_board)
	_button(column,"Roubar o táxi",_steal)
	_button(column,"Cancelar",cancel)

func is_modal() -> bool:
	return state in ["offer","destinations"]

func _lock_dialogue() -> void:
	_old_disabled = actor.is_control_disabled
	_old_dialogue = actor.is_in_dialogue
	actor.is_control_disabled = true
	actor.is_in_dialogue = true
	actor.velocity = Vector2.ZERO
	_owns_dialogue = true

func _unlock_dialogue() -> void:
	if _owns_dialogue and is_instance_valid(actor):
		actor.is_control_disabled = _old_disabled
		actor.is_in_dialogue = _old_dialogue
	_owns_dialogue = false

func _board() -> void:
	_unlock_dialogue()
	panel.hide()
	get_node("MapBackdrop").hide()
	state = "boarding"
	car._enter_vehicle_with_role(actor,true)
	if not car.is_driven_by_player: cancel()

func _steal() -> void:
	_unlock_dialogue()
	state = "idle"
	hide()
	car._enter_vehicle_with_role(actor,false,true)

func _show_destinations() -> void:
	state = "destinations"
	_lock_dialogue()
	panel.show()
	get_node("MapBackdrop").show()
	_clear()
	_title("NYC TAXI  /  ESCOLHA O DESTINO", "Motorista: Para onde vamos? Escolha um lugar no mapa.")
	var world := get_tree().current_scene
	destinations = preload("res://world/shared/traffic/TaxiDestinations.gd").collect(world)
	var minimap := get_tree().get_first_node_in_group("minimap")
	roads = minimap._roads.duplicate() if minimap else []
	buildings = minimap._buildings.duplicate() if minimap else []
	bounds = Rect2(car.global_position-Vector2.ONE*100,Vector2.ONE*200)
	for place in destinations: bounds = bounds.expand(place.position)
	bounds = bounds.grow(450)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation",18)
	column.add_child(row)
	map = Control.new()
	map.custom_minimum_size = Vector2(590,340)
	map.clip_contents = true
	map.draw.connect(_draw_map)
	map.gui_input.connect(_map_input)
	row.add_child(map)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(325,340)
	row.add_child(scroll)
	var places := VBoxContainer.new()
	places.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(places)
	place_buttons.clear()
	for i in destinations.size():
		var button := _button(places,"%02d  %s" % [i+1,destinations[i].label],_select.bind(i))
		place_buttons.append(button)
	var go := _button(column,"Confirmar destino e partir",start_ride)
	go.name = "Depart"
	go.disabled = true
	_button(column,"Descer do táxi  ·  Esc",cancel)
	status.show()
	status.offset_top = 660
	status.text = ""
	selected = -1
	_route_line.clear()

func _select(index: int) -> void:
	selected = index
	for i in place_buttons.size():
		place_buttons[i].modulate = Color("ffc526") if i == index else Color.WHITE
	destination = destinations[index].position
	destination_name = destinations[index].label
	var planner := preload("res://world/shared/traffic/TaxiRoute.gd").new()
	planner.start_lane = source_lane
	route = planner.plan(car,destination).duplicate()
	# A destination must end at a nearby curb, never across the city or indoors.
	if not route.is_empty():
		var last: Dictionary = route.back()
		var endpoint: Vector2 = last.path.to_global(last.path.curve.sample_baked(last.end,true))
		if endpoint.distance_to(destination) > 450.0: route.clear()
	_route_line.clear()
	for leg in route:
		var count := maxi(1,ceili((leg.end-leg.start)/30.0))
		for j in range(count+1):
			_route_line.append(leg.path.to_global(leg.path.curve.sample_baked(lerpf(leg.start,leg.end,float(j)/count),true)))
	column.get_node("Depart").disabled = route.is_empty()
	status.text = "Motorista: Vamos para %s. Pode confirmar." % destination_name if not route.is_empty() else "Motorista: Não tenho uma rota até esse local. Escolha outro destino."
	map.queue_redraw()

func start_ride() -> void:
	if state != "destinations" or route.is_empty(): return
	_unlock_dialogue()
	panel.hide()
	get_node("MapBackdrop").hide()
	state = "riding"
	status.offset_top = 92
	leg_index = 0
	_stopped = 0.0
	car.speed = 165.0
	car._lane_motion_speed = 0.0
	car._lane_motion_initialized = true
	_attach_leg()
	status.text = "Motorista: Pode deixar!  →  %s\nF / Enter — pedir para descer" % destination_name

func _attach_leg() -> void:
	var leg := route[leg_index]
	if not is_instance_valid(leg.path) or not leg.path.can_process():
		cancel()
		return
	var old := follow
	follow = PathFollow2D.new()
	follow.name = "TaxiRideFollow"
	follow.loop = false
	leg.path.add_child(follow)
	follow.progress = leg.start
	car.reparent(follow,true)
	# Connected lane endpoints coincide; preserve a small offset at boarding
	# and ease it out through checked physical motion instead of teleporting.
	car.set_meta("taxi_route_end",float(leg.end))
	car.set_meta("traffic_lane_id",String(leg.path.get_meta("traffic_lane_id","")))
	car._junction_traffic_controller = null
	# The normal junction contract must reserve the same turn as our route.
	if leg_index+1 < route.size():
		var next_path: Path2D = route[leg_index+1].path
		var controller: Node = car._get_junction_traffic_controller()
		if controller != null:
			for connection: Dictionary in controller._connections_from_lane.get(String(leg.path.get_meta("traffic_lane_id","")),[]):
				if connection.get("path") == next_path:
					follow.set_meta("traffic_planned_connection_id",String(connection.connection_id))
					break
	if is_instance_valid(old): old.queue_free()

func physics_tick(delta: float) -> void:
	if state == "boarding":
		_show_destinations()
		return
	if state != "riding": return
	if car.is_broken or not is_instance_valid(actor) or actor.is_dead or actor.is_arrested:
		cancel()
		return
	if not is_instance_valid(follow):
		cancel()
		return
	# Entry keeps world pose. Merge the final few pixels gradually with collision checks.
	if car.position.length() > 0.5 or absf(car.rotation) > 0.02:
		var motion: Vector2 = car.global_position.direction_to(follow.global_position)*minf(car.position.length(),60*delta)
		if not car.test_move(car.global_transform,motion):
			car.global_position += motion
			car.rotation = rotate_toward(car.rotation,0,1.8*delta)
		else:
			_stopped += delta
		if _stopped > 8: cancel()
		return
	car.position = Vector2.ZERO
	car.rotation = 0.0
	var previous: Vector2 = car.global_position
	car.advance_on_lane(delta)
	car.velocity = (car.global_position-previous)/maxf(delta,0.001)
	actor.global_position = car.global_position
	_stopped = _stopped+delta if car.velocity.length()<1 else 0.0
	if _stopped > 12:
		status.text = "Motorista: O trânsito parou. Podemos esperar.\nF / Enter — descer aqui"
	if car.engine_audio:
		car._engine_sound.update(car.engine_audio,car.velocity.length(),car.max_speed,0.4,delta,car.active_archetype_id)
	if follow.progress >= float(route[leg_index].end)-0.5:
		leg_index += 1
		if leg_index >= route.size():
			status.text = "Motorista: Chegamos! %s. Boa caminhada!" % destination_name
			car.exit_vehicle()
		else:
			_attach_leg()

func stop_ride() -> void:
	_unlock_dialogue()
	state = "exiting"
	panel.hide()
	get_node("MapBackdrop").hide()
	car.velocity = Vector2.ZERO
	car.speed = 0.0
	car._lane_motion_speed = 0.0
	car.remove_meta("taxi_route_end")
	for controller in get_tree().get_nodes_in_group("junction_traffic_controller"):
		controller.release_vehicle(car.get_instance_id())
	if is_instance_valid(follow):
		source_lane = follow.get_parent() as Path2D
		car.reparent(get_tree().current_scene,true)
		follow.queue_free()
		follow = null

func finish_exit() -> void:
	state = "idle"
	hide()

func cancel() -> void:
	_unlock_dialogue()
	if car.taxi_passenger:
		car.exit_vehicle()
	else:
		state = "idle"
		car.speed = saved_speed
		hide()

func _process(_delta: float) -> void:
	if state == "idle" or state == "exiting": return
	if not is_instance_valid(actor) or not is_instance_valid(car):
		_unlock_dialogue()
		queue_free()
		return
	if actor.is_dead or actor.is_arrested or car.is_broken:
		cancel()

func _input(event: InputEvent) -> void:
	if not is_modal(): return
	if event.is_action_pressed("ui_cancel"):
		cancel()
		get_viewport().set_input_as_handled()
	elif event.is_action("fire") or event.is_action("interact") or event.is_action("exit_vehicle"):
		get_viewport().set_input_as_handled()

func _clear() -> void:
	for node in column.get_children():
		column.remove_child(node)
		node.queue_free()

func _title(title: String, speech: String) -> void:
	for words in [title,speech]:
		var label := Label.new()
		label.text = words
		label.add_theme_font_size_override("font_size",22 if words == title else 18)
		column.add_child(label)

func _button(parent: Node, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 38
	button.pressed.connect(action)
	parent.add_child(button)
	if parent.get_child_count() == (3 if parent == column else 1): button.grab_focus()
	return button

func project(point: Vector2) -> Vector2:
	var scale := minf(map.size.x/bounds.size.x,map.size.y/bounds.size.y)
	return map.size*0.5+(point-bounds.get_center())*scale

func _draw_map() -> void:
	map.draw_style_box(panel.get_theme_stylebox("panel"),Rect2(Vector2.ZERO,map.size))
	for building: Rect2 in buildings:
		map.draw_rect(Rect2(project(building.position),project(building.end)-project(building.position)),Color("23353f"))
	for road in roads:
		var points := PackedVector2Array()
		for point in road.points: points.append(project(point))
		if points.size()>1: map.draw_polyline(points,Color("647b85"),2,true)
	if _route_line.size()>1:
		var points := PackedVector2Array()
		for point in _route_line: points.append(project(point))
		map.draw_polyline(points,Color("ffc526"),3,true)
	markers.clear()
	for i in destinations.size():
		var original := project(destinations[i].position)
		var at := original
		for attempt in 8:
			var overlaps := false
			for previous in markers:
				if previous.distance_to(at)<28: overlaps = true
			if not overlaps: break
			at = original+Vector2(0,(-1 if attempt%2 == 0 else 1)*(attempt/2+1)*28)
		at = at.clamp(Vector2(15,40),map.size-Vector2(15,15))
		markers.append(at)
		if at.distance_to(original)>2: map.draw_line(original,at,Color("9bacb0"),1,true)
		map.draw_circle(at,12,Color("ffc526") if i == selected else Color("cee2e7"))
		var half_text := ThemeDB.fallback_font.get_string_size(str(i+1),HORIZONTAL_ALIGNMENT_LEFT,-1,14).x*0.5
		map.draw_string(ThemeDB.fallback_font,at+Vector2(-half_text,5),str(i+1),HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color("101c25"))
	map.draw_circle(project(car.global_position),6,Color("54dfc4"))
	map.draw_string(ThemeDB.fallback_font,Vector2(15,25),"N ↑   •   VOCÊ / TÁXI",HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color("54dfc4"))

func _map_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var nearest := -1
		var distance := 18.0
		for i in markers.size():
			var d := markers[i].distance_to(event.position)
			if d < distance:
				distance = d
				nearest = i
		if nearest >= 0: _select(nearest)

func _exit_tree() -> void:
	_unlock_dialogue()
