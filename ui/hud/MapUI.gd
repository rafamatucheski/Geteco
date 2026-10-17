extends Control
## Full-world cartography. All map geometry is a read-only production snapshot.
const STYLE := preload("res://ui/GameStyle.gd")
const ART := preload("res://ui/hud/Cartography.gd")
const DATA := preload("res://ui/hud/WorldMapData.gd")
const SYMBOLS := preload("res://ui/hud/MapSymbols.gd")
const BIOMES := {"city":Color("3c4141"),"forest":Color("384739"),"mountain":Color("394d50"),"desert":Color("796749"),"water":Color("203f50")}
class Canvas extends Control:
	var owner_map: Control
	func _draw() -> void: owner_map.draw_map(self)
	func _gui_input(event: InputEvent) -> void: owner_map.map_input(event)
class Terrain extends Node2D:
	var owner_map: Control
	func _draw() -> void: owner_map.draw_terrain(self)
class Geography extends Node2D:
	var owner_map: Control
	func _draw() -> void: owner_map.draw_geography(self)
var controller
var canvas: Control
var terrain: Node2D
var geography: Node2D
var _geometry_scale := 0.0
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
var _hovered := -1
var _hints: Label
var _objective_button: Button
var _zoom_pad_held := {"weapon_previous":false,"weapon_next":false}
var atlas := DATA.new()
var _area: Control
var _legend: PanelContainer
var _legend_scroll: ScrollContainer
var _legend_buttons := {}
var _tabs := {}
var _header: Panel
var _footer: Panel
var _tab_row: HBoxContainer
var _close: Button
var _zoom_controls: HBoxContainer
var _filter := ""
var _region := "world"
var _drawn_markers: Array[int]=[]
var _marker_order: Array[int]=[]
var _insets: Array[Dictionary]=[]
var _inset_cache := {}
var _last_actor := Vector2.INF
var _last_heading := INF
var _waypoint := Vector2.INF
var _mark_button: Button
var _clear_button: Button

func _ready() -> void:
	name="MapUI"; mouse_filter=MOUSE_FILTER_STOP; theme=STYLE.create_theme()
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	var background := ColorRect.new(); background.color=Color("112530"); background.mouse_filter=MOUSE_FILTER_IGNORE
	add_child(background); background.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_area=Control.new(); _area.clip_contents=true; add_child(_area)
	terrain=Terrain.new(); terrain.owner_map=self
	var ink := ShaderMaterial.new(); ink.shader=preload("res://ui/hud/map_terrain.gdshader"); terrain.material=ink
	_area.add_child(terrain)
	geography=Geography.new(); geography.owner_map=self; _area.add_child(geography)
	canvas=Canvas.new(); canvas.owner_map=self; _area.add_child(canvas); canvas.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_header=Panel.new(); _header.add_theme_stylebox_override("panel",STYLE.compact(false,0)); add_child(_header)
	var brand := STYLE.label("GETECO",28); brand.position=Vector2(22,23); _header.add_child(brand)
	_tab_row=HBoxContainer.new(); _tab_row.position=Vector2(164,8); _tab_row.add_theme_constant_override("separation",6); _header.add_child(_tab_row)
	for id in ["world","harbor","mountain","desert"]:
		var title: String={"world":"Mundo","harbor":"Cidade","mountain":"Montanha","desert":"Deserto"}[id]
		_tabs[id]=_button(_tab_row,title,focus_region.bind(id))
	_close=_button(_header,"Fechar",controller.session.close_menu)
	_zoom_controls=HBoxContainer.new(); _zoom_controls.position=Vector2(18,16); _zoom_controls.add_theme_constant_override("separation",5); _area.add_child(_zoom_controls)
	_button(_zoom_controls,"−",change_zoom.bind(.8)).tooltip_text="Afastar"
	_button(_zoom_controls,"+",change_zoom.bind(1.25)).tooltip_text="Aproximar"
	_button(_zoom_controls,"◎",recenter).tooltip_text="Centralizar no jogador"
	_objective_button=_button(_zoom_controls,"◇",_focus_objective); _objective_button.tooltip_text="Objetivo"
	_build_legend()
	sidebar=PanelContainer.new(); sidebar.add_theme_stylebox_override("panel",STYLE.compact(true,4)); add_child(sidebar)
	var column := VBoxContainer.new(); column.add_theme_constant_override("separation",8); sidebar.add_child(column)
	marker_title=STYLE.label("",19); marker_title.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; column.add_child(marker_title)
	detail=STYLE.label("",14,STYLE.MUTED); detail.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; column.add_child(detail)
	var actions := HBoxContainer.new(); column.add_child(actions)
	_button(actions,"Localizar",_locate_selected)
	_mark_button=_button(actions,"Marcar",_mark_selected)
	sidebar.hide()
	_footer=Panel.new(); _footer.add_theme_stylebox_override("panel",STYLE.compact(false,0)); add_child(_footer)
	_hints=STYLE.label("",13,STYLE.MUTED); _hints.position=Vector2(20,12); _footer.add_child(_hints)
	_clear_button=_button(_footer,"Limpar destino",_clear_waypoint); _clear_button.hide()
	_cache(); _objective_button.disabled=_markers.is_empty() or not _markers[0].objective
	get_viewport().size_changed.connect(_layout); resized.connect(_layout)
	get_node("/root/GameInput").device_changed.connect(_update_hints)
	get_node("/root/GameInput").bindings_changed.connect(_update_hints)
	_update_hints(); _layout(); focus_region("world"); center=target_center; zoom=target_zoom; _redraw()

func _button(parent: Node, text: String, callback: Callable) -> Button:
	var button := Button.new(); button.text=text; button.custom_minimum_size=Vector2(36,34)
	button.add_theme_font_size_override("font_size",14); button.pressed.connect(callback); parent.add_child(button)
	return button

func _build_legend() -> void:
	_legend=PanelContainer.new(); _legend.add_theme_stylebox_override("panel",STYLE.compact(false,0)); add_child(_legend)
	var column := VBoxContainer.new(); column.add_theme_constant_override("separation",8); _legend.add_child(column)
	column.add_child(STYLE.label("LEGENDA",16))
	var key := HBoxContainer.new(); key.add_theme_constant_override("separation",10); column.add_child(key)
	for kind in ["player","objective"]:
		var icon := TextureRect.new(); icon.texture=SYMBOLS.texture(kind); icon.modulate=SYMBOLS.tint(kind)
		icon.expand_mode=TextureRect.EXPAND_IGNORE_SIZE; icon.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED; icon.custom_minimum_size=Vector2(18,22)
		key.add_child(icon); key.add_child(STYLE.label(SYMBOLS.LABELS[kind],13))
	_legend_scroll=ScrollContainer.new(); _legend_scroll.size_flags_vertical=SIZE_EXPAND_FILL; _legend_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED; column.add_child(_legend_scroll)
	var list := VBoxContainer.new(); list.size_flags_horizontal=SIZE_EXPAND_FILL; list.add_theme_constant_override("separation",2); _legend_scroll.add_child(list)
	for kind in SYMBOLS.LABELS:
		if kind in ["player","objective","waypoint"]: continue
		var button := _button(list,SYMBOLS.LABELS[kind],_set_filter.bind(kind))
		button.icon=SYMBOLS.texture(kind); button.expand_icon=true; button.add_theme_constant_override("icon_max_width",19)
		button.alignment=HORIZONTAL_ALIGNMENT_LEFT; button.custom_minimum_size.y=30
		for state in ["normal","hover","pressed"]:
			var row_style := STYLE.compact(state!="normal",2,Vector2(6,4))
			row_style.shadow_size=0; row_style.set_border_width_all(0)
			row_style.bg_color=Color(1,1,1,.06) if state!="normal" else Color.TRANSPARENT
			button.add_theme_stylebox_override(state,row_style)
		button.tooltip_text="Filtrar: "+str(SYMBOLS.LABELS[kind]); _legend_buttons[kind]=button

func _cache() -> void:
	if controller==null: return
	atlas.collect(controller); _bounds=atlas.bounds
	for road in atlas.roads: _roads.append(road.points)
	var target: Vector3=controller.session.mission_world.target_position()
	var has_mission := str(controller.state.intro.stage)!="complete" or not str(controller.state.campaign.active_id).is_empty()
	if controller.session.freight_active: target=controller.session.freight_target; has_mission=true
	if controller.state.region_id=="desert" and controller.session.desert!=null: target=controller.session.desert.target_position(); has_mission=true
	if has_mission and target.is_finite() and not target.is_zero_approx():
		_markers.append({"id":"objective","point":Vector2(target.x,target.z),"title":"Objetivo","detail":str(controller.session.objective.text),"objective":true,"kind":"objective","region":str(controller.state.region_id)})
	_markers.append_array(atlas.markers)
	if controller.world is Node and controller.session.desert!=null and is_instance_valid(controller.session.desert.extras):
		for activity in controller.session.desert.extras.map_markers():
			if _markers.any(func(marker): return marker.title==activity.title): continue
			_markers.append({"id":str(activity.title),"point":DATA.planar(activity.point),"title":activity.title,"detail":"","objective":false,"kind":"objective","region":"desert"})
	for i in _markers.size(): _marker_order.append(i)
	_marker_order.sort_custom(func(a,b):
		var first := _priority(_markers[a].kind); var second := _priority(_markers[b].kind)
		return a<b if first==second else first<second)
	if controller.world is Node: _waypoint=controller.world.get_meta("map_waypoint",Vector2.INF)
	_clear_button.visible=_waypoint.is_finite()
	for kind in _legend_buttons:
		_legend_buttons[kind].visible=_markers.any(func(marker): return marker.kind==kind)
	for region in ["harbor","mountain"]:
		if not atlas.region_bounds.has(region): continue
		var clipping := DATA.rectangle(atlas.region_bounds[region])
		var shapes: Array[Dictionary]=[]
		for land in atlas.lands:
			if region=="mountain" and land.biome not in ["mountain","water"]: continue
			if region=="harbor" and land.biome not in ["city","forest"]: continue
			for piece in Geometry2D.intersect_polygons(land.polygon,clipping): shapes.append({"points":piece,"color":BIOMES[land.biome]})
		for polygon in atlas.buildings:
			for piece in Geometry2D.intersect_polygons(polygon,clipping): shapes.append({"points":piece,"color":Color("69716d")})
		_inset_cache[region]=shapes

func _layout() -> void:
	if not is_instance_valid(canvas): return
	var narrow := size.x<850
	var side_width := 210.0 if narrow else 238.0
	_header.position=Vector2.ZERO; _header.size=Vector2(size.x,110 if narrow else 70)
	_tab_row.position=Vector2(16,64) if narrow else Vector2(164,22)
	_close.position=Vector2(size.x-_close.size.x-20,23)
	_footer.position=Vector2(0,size.y-44); _footer.size=Vector2(size.x,44)
	_clear_button.position=Vector2(size.x-155,4)
	_area.position=Vector2(0,_header.size.y); _area.size=Vector2(maxf(200,size.x-side_width),maxf(150,size.y-_header.size.y-44))
	_legend.position=Vector2(_area.size.x,_header.size.y); _legend.size=Vector2(side_width,_area.size.y)
	sidebar.position=Vector2(maxf(12,_area.size.x-side_width-12),_header.size.y+64); sidebar.size=Vector2(side_width,0)
	_base_zoom=minf(maxf(100,_area.size.x-60)/maxf(1,_bounds.size.x),maxf(100,_area.size.y-60)/maxf(1,_bounds.size.y))
	_update_hints()
	_redraw()

func _priority(kind: String) -> int:
	if kind=="objective": return 0
	if kind=="lock": return 1
	if kind in ["workshop","race","ski","lift","mine","plane","forge","jeep","train"]: return 2
	if kind in ["home","place"]: return 4
	return 3

func _update_hints() -> void:
	var controls := get_node("/root/GameInput")
	_close.text=controls.prompt("world_map")+"  Fechar"
	_hints.text="Arrastar  Mover    ·    Roda  Zoom    ·    Clique  Selecionar    ·    Duplo clique  Marcar"
	if size.x<1000: _hints.text="Arrastar  Mover   ·   Roda  Zoom   ·   Clique  Selecionar"
	if controls.using_gamepad: _hints.text=String(TranslationServer.translate("%s  Mover    ·    %s / %s  Zoom    ·    %s  Selecionar    ·    %s  Marcar"))%[controls.prompt("move_up"),controls.prompt("weapon_previous"),controls.prompt("weapon_next"),controls.prompt("ui_accept"),controls.prompt("interact")]
	if controls.get_meta("touch_controls_active",false): _hints.text="Arraste  Mover    ·    + / −  Zoom    ·    Toque  Selecionar"

func focus_region(id: String) -> void:
	_region=id if atlas.region_bounds.has(id) else "world"
	var extent: Rect2=_bounds if _region=="world" else atlas.region_bounds[_region]
	target_center=extent.get_center()
	var fit := minf((_area.size.x-70)/maxf(1,extent.size.x),(_area.size.y-70)/maxf(1,extent.size.y))
	target_zoom=clampf(fit/maxf(.0001,_base_zoom),.65,50)
	for key in _tabs: _tabs[key].modulate=Color("edc45a") if key==_region else Color.WHITE
	_redraw()

func _actor_point() -> Vector2:
	if controller.world is Node and not str(controller.state.place_id).is_empty():
		if controller.state.place_id=="maciota": return DATA.planar(controller.world.maciota_place.exterior_return)
		for marker in _markers:
			if marker.id==controller.state.place_id: return marker.point
	return DATA.planar(controller.world.player.global_position)

func recenter() -> void:
	focus_region(str(controller.state.region_id)); target_center=_actor_point()

func project(point: Vector2) -> Vector2: return _area.size*.5+(point-center)*_base_zoom*zoom
func unproject(point: Vector2) -> Vector2: return center+(point-_area.size*.5)/(_base_zoom*zoom)
func change_zoom(factor: float) -> void: target_zoom=clampf(target_zoom*factor,.65,50)
func _redraw() -> void:
	if not is_instance_valid(canvas): return
	var factor := _base_zoom*zoom
	for layer in [terrain,geography]:
		layer.position=_area.size*.5-center*factor; layer.scale=Vector2.ONE*factor
	# Retained draw commands: panning never retriangulates land or road strokes.
	# Rebuild screen-space casings only when the zoom changes meaningfully.
	if _geometry_scale==0 or absf(factor/_geometry_scale-1)>.08:
		_geometry_scale=factor; geography.queue_redraw()
	canvas.queue_redraw()

func map_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index==MOUSE_BUTTON_WHEEL_UP and event.pressed: change_zoom(1.2)
		elif event.button_index==MOUSE_BUTTON_WHEEL_DOWN and event.pressed: change_zoom(1/1.2)
		elif event.button_index==MOUSE_BUTTON_LEFT:
			_dragging=event.pressed
			if event.double_click and event.pressed and not _insets.any(func(inset): return inset.rect.has_point(event.position)): _set_waypoint(unproject(event.position))
			if event.pressed: _press=event.position; _hovered=-1
			elif _press.distance_to(event.position)<6: _pick(event.position)
	elif event is InputEventMouseMotion:
		if _dragging: target_center-=event.relative/(_base_zoom*zoom); _clamp_center()
		else:
			var hovered := _nearest(event.position)
			if hovered!=_hovered: _hovered=hovered; canvas.queue_redraw()
	elif event is InputEventScreenTouch:
		_dragging=event.pressed
		if event.pressed: _press=event.position
		elif _press.distance_to(event.position)<12: _pick(event.position)
	elif event is InputEventScreenDrag:
		target_center-=event.relative/(_base_zoom*zoom); _clamp_center()
	canvas.accept_event()

func _clamp_center() -> void: target_center=target_center.clamp(_bounds.position-Vector2.ONE*100,_bounds.end+Vector2.ONE*100)
func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not controller.session.modal: return
	get_node("/root/GameInput").observe_event(event)
	if event.is_action_pressed("world_map"):
		controller.session.close_menu(); get_viewport().set_input_as_handled()
	elif event is InputEventJoypadButton or event is InputEventJoypadMotion:
		if event.is_action_pressed("interact") and _selected>=0:
			_mark_selected(); get_viewport().set_input_as_handled(); return
		for action in _zoom_pad_held:
			if not event.is_action(action): continue
			var down := event.is_action_pressed(action)
			if down and not _zoom_pad_held[action]: change_zoom(.8 if action=="weapon_previous" else 1.25)
			_zoom_pad_held[action]=down; get_viewport().set_input_as_handled(); return
		if event.is_action_pressed("ui_accept") and not _drawn_markers.is_empty():
			var slot := _drawn_markers.find(_selected)
			select_marker(_drawn_markers[(slot+1)%_drawn_markers.size()]); get_viewport().set_input_as_handled()

func _nearest(point: Vector2) -> int:
	var nearest := -1; var distance := 18.0
	for i in _drawn_markers:
		var d := project(_markers[i].point).distance_to(point)
		if d<distance: distance=d; nearest=i
	return nearest
func _pick(point: Vector2) -> void:
	for inset in _insets:
		if inset.rect.has_point(point): focus_region(inset.region); return
	select_marker(_nearest(point))
func select_marker(index: int) -> void:
	_selected=index if index>=0 and index<_markers.size() else -1
	sidebar.visible=_selected>=0
	if _selected>=0:
		marker_title.text=_markers[index].title; detail.text=_markers[index].detail; detail.visible=not detail.text.is_empty()
		_mark_button.disabled=_markers[index].kind=="lock"
	canvas.queue_redraw()
func _locate_selected() -> void:
	if _selected<0: return
	focus_region(_markers[_selected].region); target_center=_markers[_selected].point
func _focus_objective() -> void:
	if _markers.is_empty() or not _markers[0].objective: return
	select_marker(0); _locate_selected()
func _mark_selected() -> void:
	if _selected>=0 and _markers[_selected].kind!="lock": _set_waypoint(_markers[_selected].point)
func _set_waypoint(point: Vector2) -> void:
	_waypoint=point
	if controller.world is Node: controller.world.set_meta("map_waypoint",point)
	_clear_button.show(); canvas.queue_redraw()
func _clear_waypoint() -> void:
	_waypoint=Vector2.INF
	if controller.world is Node: controller.world.remove_meta("map_waypoint")
	_clear_button.hide(); canvas.queue_redraw()
func _set_filter(kind: String) -> void:
	_filter="" if _filter==kind else kind
	for key in _legend_buttons: _legend_buttons[key].modulate=Color("edc45a") if key==_filter else Color.WHITE
	select_marker(-1); _hovered=-1; canvas.queue_redraw()

func _process(delta: float) -> void:
	if not is_visible_in_tree(): return
	var controls := get_node("/root/GameInput")
	if controls.using_gamepad:
		var motion: Vector2=controls.movement()
		if motion.length()>.1: target_center+=motion*300*delta/(_base_zoom*zoom); _clamp_center()
	var moved := center.distance_to(target_center)>.02 or absf(zoom-target_zoom)>.001
	if moved:
		center=center.lerp(target_center,1-exp(-14*delta)); zoom=lerpf(zoom,target_zoom,1-exp(-14*delta)); _redraw()
	var actor: Vector2=_actor_point()
	var forward: Vector3=-controller.world.player.global_basis.z
	var heading := Vector2(forward.x,forward.z).angle()
	if actor.distance_squared_to(_last_actor)>.01 or absf(heading-_last_heading)>.01:
		_last_actor=actor; _last_heading=heading; canvas.queue_redraw()

func draw_terrain(target: CanvasItem) -> void:
	for land in atlas.lands: target.draw_colored_polygon(land.polygon,BIOMES[land.biome])

func draw_geography(target: CanvasItem) -> void:
	var scale_value := maxf(.001,_base_zoom*zoom)
	# Coast casing follows actual land polygons; no generated image used for roads.
	for land in atlas.lands:
		var edge: PackedVector2Array=land.polygon.duplicate()
		if edge.size()<3: continue
		edge.append(edge[0]); target.draw_polyline(edge,Color("627475"),1.1/scale_value,true)
	for polygon in atlas.buildings:
		if scale_value<.45: continue
		target.draw_colored_polygon(polygon,Color("69716d"))
		var edge := polygon.duplicate(); edge.append(edge[0]); target.draw_polyline(edge,Color("8a928a"),.65/scale_value,true)
	for casing in [true,false]:
		for road in atlas.roads:
			var width := maxf(road.width,1.5/scale_value)
			if road.surface=="railway":
				target.draw_polyline(road.points,Color("172b31") if casing else Color("87bdc9"),(4.5 if casing else 2.0)/scale_value,true)
				if not casing:
					for i in range(1,road.points.size()): target.draw_dashed_line(road.points[i-1],road.points[i],Color("d3e8e8"),3.4/scale_value,3.0/scale_value,true)
				continue
			if road.surface in ["cable","ski"]:
				if not casing:
					for i in range(1,road.points.size()): target.draw_dashed_line(road.points[i-1],road.points[i],Color("87b7c7") if road.surface=="ski" else Color("c4cac5"),1.2/scale_value,5/scale_value,true)
				continue
			var dirt: bool=road.surface in ["earth","footpath","dirt"]
			var color := Color("a2997e") if dirt else Color("c4cac5")
			target.draw_polyline(road.points,Color("202c30") if casing else color,width+3.0/scale_value if casing else width,true)

func draw_map(target: Control) -> void:
	_drawn_markers.clear()
	_insets.clear()
	if _region=="world" and target_zoom<1.5 and _area.size.x>640:
		if atlas.region_bounds.has("harbor"): _insets.append({"region":"harbor","rect":Rect2(16,_area.size.y-210,270,194)})
		if atlas.region_bounds.has("mountain"): _insets.append({"region":"mountain","rect":Rect2(_area.size.x-276,70,260,208)})
	var occupied: Array[Vector2]=[]
	var order: Array[int]=[]
	if _selected>=0: order.append(_selected)
	for i in _marker_order:
		if i!=_selected: order.append(i)
	for i in order:
		var marker: Dictionary=_markers[i]; var point := project(marker.point)
		if not Rect2(Vector2(18,56),_area.size-Vector2(36,76)).has_point(point): continue
		if _insets.any(func(inset): return inset.rect.has_point(point)): continue
		if not _filter.is_empty() and marker.kind!=_filter and not marker.objective: continue
		var crowded := false
		for other in occupied:
			if point.distance_to(other)<34: crowded=true; break
		if crowded and not marker.objective and i!=_selected: continue
		occupied.append(point); _drawn_markers.append(i)
		SYMBOLS.draw(target,point,marker.kind,14,i==_selected)
	if _waypoint.is_finite(): SYMBOLS.draw(target,project(_waypoint),"waypoint",15,true)
	if _last_actor.is_finite(): ART.player(target,project(_last_actor),_last_heading)
	if _hovered in _drawn_markers: _draw_label(target,project(_markers[_hovered].point),_markers[_hovered].title)
	target.draw_string(STYLE.STRONG,Vector2(_area.size.x-37,31),"N",HORIZONTAL_ALIGNMENT_LEFT,-1,17,Color("d9e6e5"))
	target.draw_colored_polygon(PackedVector2Array([Vector2(_area.size.x-32,40),Vector2(_area.size.x-39,55),Vector2(_area.size.x-25,55)]),Color("d9e6e5"))
	for inset in _insets:
		_draw_inset(target,inset.region,"CIDADE" if inset.region=="harbor" else "MONTANHA",inset.rect)
	_draw_scale(target)

func _draw_label(target: Control, point: Vector2, text: String) -> void:
	text = tr(text)
	var width := minf(230,STYLE.STRONG.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,15).x+20)
	var at := Vector2(clampf(point.x+20,8,_area.size.x-width-8),clampf(point.y-16,8,_area.size.y-36))
	target.draw_style_box(STYLE.compact(false,3),Rect2(at,Vector2(width,32)))
	target.draw_string(STYLE.STRONG,at+Vector2(10,22),text,HORIZONTAL_ALIGNMENT_LEFT,width-20,15,STYLE.TEXT)

func _draw_inset(target: Control, region: String, title: String, rect: Rect2) -> void:
	if not atlas.region_bounds.has(region): return
	target.draw_rect(rect,Color("152b36")); target.draw_rect(rect,Color("627b85"),false,1)
	target.draw_string(STYLE.STRONG,rect.position+Vector2(10,20),tr(title),HORIZONTAL_ALIGNMENT_LEFT,-1,13,STYLE.TEXT)
	var extent: Rect2=atlas.region_bounds[region]
	var factor := minf((rect.size.x-20)/extent.size.x,(rect.size.y-40)/extent.size.y)
	var origin := rect.position+Vector2(rect.size.x*.5,28+(rect.size.y-28)*.5)-extent.get_center()*factor
	for shape in _inset_cache.get(region,[]):
		var polygon := PackedVector2Array()
		for point in shape.points: polygon.append(origin+point*factor)
		target.draw_colored_polygon(polygon,shape.color)
	for road in atlas.roads:
		if road.region!=region: continue
		var points := PackedVector2Array()
		for point in road.points: points.append(origin+point*factor)
		target.draw_polyline(points,Color("b5c1be"),maxf(1,road.width*factor),true)
	var occupied: Array[Vector2]=[]
	for marker in _markers:
		if marker.region!=region or marker.kind in ["place","home"]: continue
		var point: Vector2=origin+marker.point*factor
		if not rect.grow(-12).has_point(point): continue
		var crowded := false
		for previous in occupied:
			if point.distance_to(previous)<23: crowded=true; break
		if not crowded: occupied.append(point); SYMBOLS.draw(target,point,marker.kind,8)

func _draw_scale(target: Control) -> void:
	var meters := 100.0
	var factor := _base_zoom*zoom
	while meters*factor>110: meters*=.5
	while meters*factor<45: meters*=2
	var at := Vector2(_area.size.x-135,_area.size.y-22)
	target.draw_line(at,at+Vector2(meters*factor,0),STYLE.MUTED,2)
	target.draw_string(STYLE.FONT,at-Vector2(0,7),"%d m"%roundi(meters),HORIZONTAL_ALIGNMENT_LEFT,-1,12,STYLE.MUTED)
