extends Control
## Interactive presentation of the existing region routes, entries and mission.
const STYLE := preload("res://ui/GameStyle.gd")
const ART := preload("res://ui/hud/Cartography.gd")
class Canvas extends Control:
	var owner_map: Control
	func _draw() -> void: owner_map.draw_map(self)
	func _gui_input(event: InputEvent) -> void: owner_map.map_input(event)
var controller
var canvas: Control
var sidebar: PanelContainer
var detail: Label
var marker_title: Label
var center := Vector2.ZERO
var target_center := Vector2.ZERO
var zoom := 1.0
var target_zoom := 1.0
var _base_zoom := 1.0
var _roads: Array[PackedVector2Array]=[]
var _markers: Array[Dictionary]=[]
var _bounds := Rect2()
var _dragging := false
var _press := Vector2.ZERO
var _selected := -1
var _clock := 0.0
var _hints: Label
var _objective_button: Button
func _ready() -> void:
	name="MapUI"; mouse_filter=MOUSE_FILTER_STOP; theme=STYLE.create_theme()
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	canvas=Canvas.new(); canvas.owner_map=self; canvas.clip_contents=true; canvas.mouse_filter=MOUSE_FILTER_STOP; add_child(canvas); canvas.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	var title := STYLE.label("MAPA",18); title.position=Vector2(24,24); add_child(title)
	var close := _button(self,"×",controller.session.close_menu); close.set_anchors_and_offsets_preset(PRESET_TOP_RIGHT); close.offset_left=-64; close.offset_right=-24; close.offset_top=24; close.offset_bottom=64
	var controls := HBoxContainer.new(); controls.position=Vector2(24,60); controls.add_theme_constant_override("separation",8); add_child(controls)
	_button(controls,"−",func(): change_zoom(.8)).tooltip_text="Afastar"
	_button(controls,"+",func(): change_zoom(1.25)).tooltip_text="Aproximar"
	_button(controls,"◎",recenter).tooltip_text="Centralizar no jogador"
	_objective_button=_button(controls,"◇",func(): select_marker(0)); _objective_button.tooltip_text="Objetivo"
	sidebar=PanelContainer.new(); sidebar.add_theme_stylebox_override("panel",STYLE.compact(false,12)); add_child(sidebar)
	var column := VBoxContainer.new(); column.add_theme_constant_override("separation",12); sidebar.add_child(column)
	marker_title=STYLE.label("",19); marker_title.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; marker_title.custom_minimum_size.x=190; column.add_child(marker_title)
	detail=STYLE.label("",15,STYLE.MUTED); detail.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; detail.custom_minimum_size.x=190; column.add_child(detail)
	_button(column,"Localizar",func(): if _selected>=0: target_center=_markers[_selected].point)
	sidebar.hide()
	_hints=STYLE.label("",12,STYLE.MUTED); add_child(_hints)
	_cache(); _objective_button.disabled=_markers.is_empty() or not _markers[0].objective
	recenter(); center=target_center
	get_viewport().size_changed.connect(_layout); resized.connect(_layout)
	get_node("/root/GameInput").device_changed.connect(_update_hints); _update_hints(); _layout()
func _button(parent: Node, text: String, callback: Callable) -> Button:
	var button := Button.new(); button.text=text; button.custom_minimum_size=Vector2(36,34); button.pressed.connect(callback); parent.add_child(button); return button
func _cache() -> void:
	if controller==null: return
	var first := true
	for source in controller.region.map_routes():
		var road := PackedVector2Array()
		for point: Vector3 in source.points:
			var p := Vector2(point.x,point.z); road.append(p); _bounds=Rect2(p,Vector2.ONE) if first else _bounds.expand(p); first=false
		_roads.append(road)
	var target: Vector3=controller.session.mission_world.target_position()
	var has_mission := str(controller.state.intro.stage)!="complete" or not str(controller.state.campaign.active_id).is_empty()
	if controller.session.freight_active: target=controller.session.freight_target; has_mission=true
	if has_mission and target.is_finite() and not target.is_zero_approx():
		_markers.append({"point":Vector2(target.x,target.z),"title":"Objetivo","detail":str(controller.session.objective.text),"objective":true})
	var places := {}
	for place in preload("res://world/places/PlaceCatalog.gd").definitions(): places[place.id]=place.original_name
	for entry in controller.region.entries:
		var p: Vector3=entry.position
		_markers.append({"point":Vector2(p.x,p.z),"title":str(places.get(entry.get("place_id",""),entry.get("label","Destino"))),"detail":"","objective":false})
	if controller.state.region_id=="harbor": _markers.append({"point":Vector2(-224,-37),"title":"Motocross","detail":"","objective":false})
func _layout() -> void:
	if not is_instance_valid(canvas): return
	var view := get_viewport_rect().size
	sidebar.position=Vector2(maxf(24,view.x-248),100); sidebar.size=Vector2(224,0)
	_hints.position=Vector2(24,maxf(64,view.y-32))
	_base_zoom=minf(maxf(100,size.x-80)/maxf(1,_bounds.size.x),maxf(100,size.y-80)/maxf(1,_bounds.size.y))
	canvas.queue_redraw()
func _update_hints() -> void:
	var controls := get_node("/root/GameInput")
	_hints.text="%s  mover   ·   %s / %s  zoom   ·   %s  selecionar"%[controls.prompt("move_up"),controls.prompt("weapon_previous"),controls.prompt("weapon_next"),controls.prompt("ui_accept")] if controls.using_gamepad else "Arrastar  mover   ·   Roda  zoom   ·   Clique  selecionar"
	if controls.get_meta("touch_controls_active",false): _hints.text="Arraste para mover · + / − para zoom · Toque para selecionar"
func recenter() -> void:
	if controller==null: return
	var point: Vector3=controller.world.player.global_position
	target_center=Vector2(point.x,point.z); target_zoom=1.6
func project(point: Vector2) -> Vector2: return size*.5+(point-center)*_base_zoom*zoom
func change_zoom(factor: float) -> void: target_zoom=clampf(target_zoom*factor,.65,12)
func map_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index==MOUSE_BUTTON_WHEEL_UP and event.pressed: change_zoom(1.2)
		elif event.button_index==MOUSE_BUTTON_WHEEL_DOWN and event.pressed: change_zoom(1/1.2)
		elif event.button_index==MOUSE_BUTTON_LEFT:
			_dragging=event.pressed
			if event.pressed: _press=event.position
			elif _press.distance_to(event.position)<6: _pick(event.position)
	elif event is InputEventMouseMotion and _dragging:
		target_center-=event.relative/(_base_zoom*zoom)
	canvas.accept_event()
func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not controller.session.modal: return
	if event.is_action_pressed("world_map"):
		controller.session.close_menu(); get_viewport().set_input_as_handled()
	elif event is InputEventJoypadButton and event.pressed:
		if event.button_index==JOY_BUTTON_LEFT_SHOULDER: change_zoom(.8)
		elif event.button_index==JOY_BUTTON_RIGHT_SHOULDER: change_zoom(1.25)
		elif event.button_index==JOY_BUTTON_A and not _markers.is_empty(): select_marker((_selected+1)%_markers.size())
		else: return
		get_viewport().set_input_as_handled()
func _pick(point: Vector2) -> void:
	var nearest := -1; var distance := 18.0
	for i in _markers.size():
		var d := project(_markers[i].point).distance_to(point)
		if d<distance: distance=d; nearest=i
	select_marker(nearest)
func select_marker(index: int) -> void:
	_selected=index if index>=0 and index<_markers.size() else -1
	sidebar.visible=_selected>=0
	if _selected>=0:
		marker_title.text=_markers[index].title; detail.text=_markers[index].detail; detail.visible=not detail.text.is_empty()
	canvas.queue_redraw()
func _process(delta: float) -> void:
	if not is_visible_in_tree(): return
	var controls := get_node("/root/GameInput")
	if controls.using_gamepad:
		var motion: Vector2=controls.movement()
		if motion.length()>.1: target_center+=motion*300*delta/(_base_zoom*zoom)
	var moved := center.distance_to(target_center)>.02 or absf(zoom-target_zoom)>.001
	if moved:
		center=center.lerp(target_center,1-exp(-14*delta)); zoom=lerpf(zoom,target_zoom,1-exp(-14*delta))
	_clock+=delta
	if moved or _clock>.2: _clock=0; canvas.queue_redraw()
func draw_map(target: Control) -> void:
	target.draw_rect(Rect2(Vector2.ZERO,size),STYLE.INK)
	ART.contours(target,size,center,_base_zoom*zoom)
	for road in _roads:
		var points := PackedVector2Array()
		for point in road: points.append(project(point))
		if points.size()>1: target.draw_polyline(points,STYLE.MAP_ROAD,clampf(zoom,1,3),true)
	var occupied: Array[Vector2]=[]
	for i in _markers.size():
		var marker: Dictionary=_markers[i]; var p := project(marker.point)
		if not Rect2(Vector2(6,6),size-Vector2(12,12)).has_point(p): continue
		var crowded := false
		for other in occupied:
			if p.distance_to(other)<28: crowded=true; break
		if crowded and not marker.objective and i!=_selected: continue
		occupied.append(p)
		if marker.objective: ART.diamond(target,p)
		else: target.draw_circle(p,3.0,STYLE.MUTED)
		if i==_selected: target.draw_circle(p,11,STYLE.ACCENT,false,1.5,true)
	var actor: Node3D=controller.world.player
	var point: Vector3=actor.global_position
	var forward := -actor.global_basis.z
	ART.player(target,project(Vector2(point.x,point.z)),Vector2(forward.x,forward.z).angle())
	target.draw_string(STYLE.STRONG,Vector2(size.x-94,50),"N",HORIZONTAL_ALIGNMENT_LEFT,-1,14,STYLE.ACCENT)
