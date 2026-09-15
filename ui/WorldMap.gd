extends CanvasLayer
## Shares the minimap's cached world geometry and street graph.
const INK := Color("67e8cf")
var minimap: Node
var screen: Control
var surface: Control
var status: Label
var view_center := Vector2.ZERO
var zoom := 0.06
var fit_zoom := 0.06
var dragging := false
var drag_distance := 0.0
var old_mouse_mode: int
var places: Array[Dictionary] = []

func _ready() -> void:
	minimap = get_parent()
	layer = 90
	process_mode = Node.PROCESS_MODE_ALWAYS
	screen = Control.new()
	add_child(screen)
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color("101c24")
	screen.add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var title := Label.new()
	title.text = "GETECO / MAPA"
	title.position = Vector2(28,16)
	title.add_theme_font_size_override("font_size",26)
	screen.add_child(title)
	var close := Button.new()
	close.text = "Fechar · Esc"
	screen.add_child(close)
	close.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	close.position += Vector2(-160,16)
	close.size = Vector2(132,38)
	close.pressed.connect(close_map)
	surface = Control.new()
	screen.add_child(surface)
	surface.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	surface.offset_left = 24
	surface.offset_top = 68
	surface.offset_right = -24
	surface.offset_bottom = -100
	surface.clip_contents = true
	surface.draw.connect(_draw_map)
	surface.gui_input.connect(_map_input)
	surface.resized.connect(func(): surface.queue_redraw())
	status = Label.new()
	screen.add_child(status)
	status.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	status.position += Vector2(28,-83)
	var help := Label.new()
	help.text = "Clique: marcar destino   ·   Arraste: mover   ·   Roda: zoom   ·   Botão direito: limpar GPS"
	screen.add_child(help)
	help.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	help.position += Vector2(28,-40)
	var locate := Button.new()
	locate.text = "Minha posição"
	screen.add_child(locate)
	locate.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	locate.position += Vector2(-174,-89)
	locate.size = Vector2(146,36)
	locate.pressed.connect(func(): view_center = minimap.center; surface.queue_redraw())
	screen.hide()
	set_process(false)

func _input(event: InputEvent) -> void:
	if get_node("/root/GameInput").remapping: return
	if event.is_action_pressed("world_map") and not event.is_echo():
		if screen.visible: close_map()
		else: open_map()
		get_viewport().set_input_as_handled()
	elif screen.visible and (event.is_action_pressed("pause_game") or event.is_action_pressed("ui_cancel")):
		close_map()
		get_viewport().set_input_as_handled()

func open_map() -> void:
	var player: Node = minimap.world.get_node("Player")
	if get_tree().paused or player.is_dead or player.is_in_dialogue or player.is_control_disabled: return
	minimap.refresh()
	_cache_places()
	var bounds := Rect2(minimap.center,Vector2.ONE)
	for road in minimap._roads:
		for point: Vector2 in road.points: bounds = bounds.expand(point)
	fit_zoom = minf((surface.size.x-64)/maxf(bounds.size.x,1),(surface.size.y-64)/maxf(bounds.size.y,1))
	zoom = fit_zoom
	view_center = bounds.get_center()
	old_mouse_mode = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = true
	minimap.panel.hide()
	screen.show()
	_update_status()
	surface.queue_redraw()

func close_map() -> void:
	if not screen.visible: return
	screen.hide()
	dragging = false
	Input.mouse_mode = old_mouse_mode
	get_tree().paused = false
	minimap.refresh()

func project(point: Vector2) -> Vector2:
	return surface.size*0.5+(point-view_center)*zoom

func unproject(point: Vector2) -> Vector2:
	return view_center+(point-surface.size*0.5)/zoom

func _map_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				dragging = true
				drag_distance = 0
			else:
				if dragging and drag_distance < 6:
					var target := unproject(event.position)
					var closest := 10.0
					for place in places:
						var distance := project(place.point).distance_to(event.position)
						if distance < closest:
							closest = distance
							target = place.point
					# Mission badges have priority over nearby shops when selecting GPS.
					for mission_target: Vector2 in [minimap.available_mission_target,minimap.objective_target]:
						if mission_target != Vector2.ZERO and project(mission_target).distance_to(event.position) <= 20:
							target = mission_target
					minimap.set_waypoint(target)
					dragging = false
		elif event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
			minimap.clear_waypoint()
		elif event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
			var before := unproject(event.position)
			zoom = clampf(zoom*(1.2 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0/1.2),fit_zoom, maxf(0.5,fit_zoom))
			view_center += before-unproject(event.position)
	elif event is InputEventMouseMotion and dragging:
		if not event.button_mask & MOUSE_BUTTON_MASK_LEFT:
			dragging = false
		else:
			drag_distance += event.relative.length()
			view_center -= event.relative/zoom
	else:
		return
	_update_status()
	surface.queue_redraw()
	surface.accept_event()

func _update_status() -> void:
	status.text = "Selecione um destino"
	if minimap.has_waypoint:
		status.text = "GPS · %d m" % int(minimap.center.distance_to(minimap.waypoint)/16.6)
		if minimap._route_building: status.text += " · Calculando rota…"
		elif minimap.waypoint_route.is_empty(): status.text += " · Sem rota viária neste ponto"

func _cache_places() -> void:
	places.clear()
	for path in ["PayNSpray","District/Garage/Entrance/OutsideReturn"]:
		var node: Node2D = minimap.world.get_node_or_null(path)
		if node != null: places.append({"point":node.global_position,"label":"Pay 'n' Spray" if path == "PayNSpray" else "Garagem"})
	for group in ["bank_entrance","fuel_entrance","clothing_shop","weapon_shop","residence_property","chop_shop"]:
		for node in get_tree().get_nodes_in_group(group):
			places.append({"point":node.minimap_position() if group == "residence_property" else node.global_position,"label":{"bank_entrance":"Banco","fuel_entrance":"Posto","clothing_shop":"Roupas","weapon_shop":"Armas","residence_property":"Casa","chop_shop":"Desmanche"}[group]})

func _draw_map() -> void:
	surface.draw_rect(Rect2(Vector2.ZERO,surface.size),Color("263940"))
	for rect: Rect2 in minimap._buildings:
		surface.draw_rect(Rect2(project(rect.position),rect.size*zoom),Color("46595c"))
	for road in minimap._roads:
		var line := PackedVector2Array()
		for point: Vector2 in road.points: line.append(project(point))
		if line.size() > 1: surface.draw_polyline(line,Color("a8b4b0"),maxf(1.3,road.width*zoom*0.45),true)
	for path in minimap._dirt_paths:
		var line := PackedVector2Array()
		for point: Vector2 in path.points: line.append(project(point))
		if line.size() > 1: surface.draw_polyline(line,Color("b18b59"),1.5,true)
	var font := ThemeDB.fallback_font
	var label_bounds: Array[Rect2] = []
	for place in places:
		var p := project(place.point)
		surface.draw_circle(p,4,Color("e8b77d"))
		if zoom > fit_zoom*1.8:
			var label_size := font.get_string_size(place.label,HORIZONTAL_ALIGNMENT_LEFT,-1,14)
			var bounds := Rect2(p+Vector2(8,-20),label_size+Vector2(8,4))
			for occupied in label_bounds:
				if bounds.intersects(occupied): bounds.position.y = occupied.end.y+2
			label_bounds.append(bounds)
			surface.draw_string(font,bounds.position+Vector2(0,14),place.label,HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color("edf4ee"))
	if minimap.show_car:
		var car := project(minimap.car_map_position)
		surface.draw_rect(Rect2(car-Vector2(4,6),Vector2(8,12)),Color("ffaa4e"))
	if minimap.has_waypoint:
		var line := PackedVector2Array()
		for point: Vector2 in minimap.waypoint_route: line.append(project(point))
		if line.size() > 1: surface.draw_polyline(line,INK,3,true)
		var pin := project(minimap.waypoint)
		surface.draw_circle(pin,9,Color("102a29"))
		surface.draw_arc(pin,7,0,TAU,24,INK,2,true)
		surface.draw_circle(pin,3,INK)
	# Fixed screen sizes: missions remain obvious even with the whole city in view.
	if minimap.available_mission_target != Vector2.ZERO:
		_draw_mission_badge(minimap.available_mission_target,false)
	if minimap.objective_target != Vector2.ZERO:
		_draw_mission_badge(minimap.objective_target,true)
	var pointer := PackedVector2Array()
	for p in [Vector2(10,0),Vector2(-7,-6),Vector2(-3,0),Vector2(-7,6)]: pointer.append(project(minimap.center)+p.rotated(minimap.heading))
	surface.draw_colored_polygon(pointer,Color.WHITE)
	surface.draw_string(font,Vector2(18,28),"N ↑",HORIZONTAL_ALIGNMENT_LEFT,-1,18,Color.WHITE)

func _draw_mission_badge(target: Vector2, active: bool) -> void:
	var p := project(target)
	var ink := Color("101820")
	var gold := Color("ffcf4d")
	var font := ThemeDB.fallback_font
	surface.draw_circle(p,19,ink)
	if active:
		surface.draw_colored_polygon(PackedVector2Array([p+Vector2(0,-15),p+Vector2(15,0),p+Vector2(0,15),p+Vector2(-15,0)]),gold)
		surface.draw_circle(p,4,ink)
	else:
		surface.draw_circle(p,15,gold)
		var glyph_width := font.get_string_size("M",HORIZONTAL_ALIGNMENT_LEFT,-1,22).x
		surface.draw_string(font,p+Vector2(-glyph_width*0.5,8),"M",HORIZONTAL_ALIGNMENT_LEFT,-1,22,ink)
	var english := TranslationServer.get_locale().begins_with("en")
	var label := ("Active objective" if english else "Objetivo ativo") if active else ("Mission · Maciota" if english else "Missão · Maciota")
	var label_size := font.get_string_size(label,HORIZONTAL_ALIGNMENT_LEFT,-1,16)
	var label_position := Vector2(clampf(p.x-label_size.x*0.5,6,maxf(6,surface.size.x-label_size.x-6)),p.y+23)
	if label_position.y+24 > surface.size.y: label_position.y = p.y-45
	surface.draw_rect(Rect2(label_position-Vector2(5,2),label_size+Vector2(10,4)),ink)
	surface.draw_string(font,label_position+Vector2(0,16),label,HORIZONTAL_ALIGNMENT_LEFT,-1,16,gold)
