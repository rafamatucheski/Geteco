@tool
extends Control
const DATA := preload("res://world/editing/WorldEditData.gd")
const MIN_ZOOM := .05
const OVERVIEW_ZOOM := .75
# Keep real geometry around the viewport so crossing a grid edge does not rebuild the map.
const DETAIL_CELL_MARGIN := 2
var road_drawing := preload("res://addons/geteco_world_editor/WorldRoadDrawing.gd").new()
signal selected(id: String)
signal committed(row: Dictionary)
signal placed(type: String, at: Vector2)
var objects: Dictionary = {}
var junction_editor
var land: Array = []
var entries: Array = []
var terrain: Array = []
var land_polygons: Array = []
var context_parts: Array = []
var context_mesh: ArrayMesh
# Triângulos de cada parte de contexto, em coordenadas do mundo; calculados uma vez por carga.
var context_triangles := {}
var mesh_key := []
var polygon_ok := {}
var polygon_meshes := {}
var polygon_mesh_order: Array[int] = []
const POLYGON_MESH_LIMIT := 32768
var road_ready := false
var road_cache_key: Array = []
var context_cells := {}
var visible_part_ids: Array = []
var cached_cells := Rect2i(-999999,-999999,0,0)
var region := "harbor"
var center := Vector2(45,110)
var zoom := 4.0
var selected_id := ""
var selected_point := -1
var edit_points := false
var rotation_enabled := false
var road_snap_enabled := true
const RESIZE_OFFSET := Vector2(-55,55)
var armed := ""
var grid := 1.0
var dragging := false
var drag_origin := Vector2.ZERO
var drag_row := {}
var drag_changed := false
var panning := false
var filter_type := "all"
const AXIS_LENGTH := 64.0
const ROTATE_RADIUS := 82.0
var drag_axis := ""
var drag_pivot := Vector2.ZERO
var drag_angle := 0.0
var drag_turn := 0.0
var context_owners: Array[String] = []
var context_owner_parts := {}
var context_part_cells := {}
var context_free_parts: Array[int] = []
var context_index_revision := 0
var context_index_progress := 1.0
var context_overview_items := {}
var context_overview_mesh: ArrayMesh
var context_overview_dirty := true
var context_overview_excluded := ""
var region_bounds_visible := true
var map_region_bounds := {}
var terrain_hover := Vector2.ZERO
var terrain_hover_valid := false
var overview_layer: Node2D
var detail_object_cells: Dictionary = {}
var detail_object_index_key: Array = []
var detail_rows_key: Array = []
var detail_visible_rows: Array = []
var detail_visible_context_count := 0
var overview_layer_key: Array = []
var overview_revision := 0
var overview_rebuild_ms := 0.0
var overview_command_count := 0
var overview_record_count := 0
var terrain_topographies := {}
var terrain_topography_sources := {}
var terrain_topography_foregrounds := {}
var terrain_topography_foreground_meshes := {}
var terrain_topography_visible := true
var terrain_topography_revision := 0
func _ready() -> void:
	clip_contents = true
	focus_mode = Control.FOCUS_ALL
	mouse_default_cursor_shape = Control.CURSOR_CROSS
	resized.connect(queue_redraw)
	focus_exited.connect(cancel_drag)
func screen(p: Vector2) -> Vector2: return (p-center)*zoom+size*.5
func world(p: Vector2) -> Vector2: return (p-size*.5)/zoom+center
func snapped_point(p: Vector2) -> Vector2: return p.snapped(Vector2.ONE*grid) if grid > 0 else p
func allowed(row: Dictionary) -> bool: return filter_type == "all" or row.type == filter_type or row.id == selected_id
func local_outline(row: Dictionary) -> Array:
	if row.type == "terrain":
		var radius := float(row.get("radius",12))
		return [[-radius,-radius],[radius,-radius],[radius,radius],[-radius,radius]]
	if row.get("outline",[]).size() >= 3: return row.outline.duplicate(true)
	if row.get("default_outline",[]).size() >= 3: return row.default_outline.duplicate(true)
	var half := DATA.point(row.size)*.5
	return [[-half.x,-half.y],[half.x,-half.y],[half.x,half.y],[-half.x,half.y]]

func corners(row: Dictionary) -> PackedVector2Array:
	var factor := DATA.point(row.get("stretch",[1.0,1.0]))*float(row.get("scale",1.0))
	var result := PackedVector2Array()
	for offset in local_outline(row):
		result.append(DATA.point(row.position)+(DATA.point(offset)*factor).rotated(-deg_to_rad(float(row.get("rotation",0)))))
	return result

func shape_points(row: Dictionary) -> PackedVector2Array:
	if row.type != "road": return corners(row)
	var result := PackedVector2Array()
	for point in row.points: result.append(DATA.point(point))
	return result

func world_bounds() -> Rect2:
	var rectangles: Array[Rect2] = []
	for tile in terrain_topography_tiles(): rectangles.append(tile.bounds)
	for item in land: rectangles.append(Rect2(float(item[0])/16.0,float(item[1])/16.0,float(item[2])/16.0,float(item[3])/16.0))
	for item in terrain: rectangles.append(Rect2(item[0],item[1],item[2],item[3]))
	for polygon in land_polygons:
		if polygon.is_empty(): continue
		var rect := Rect2(DATA.point(polygon[0]),Vector2.ZERO)
		for point in polygon: rect=rect.expand(DATA.point(point))
		rectangles.append(rect)
	for row in objects.values():
		if row.type=="road":
			if row.get("points",[]).is_empty(): continue
			var rect := Rect2(DATA.point(row.points[0]),Vector2.ZERO)
			for point in row.points: rect=rect.expand(DATA.point(point))
			rectangles.append(rect.grow(float(row.get("width",0))*.5))
		elif row.has("size"):
			var polygon := corners(row)
			if polygon.is_empty(): continue
			var rect := Rect2(polygon[0],Vector2.ZERO)
			for point in polygon: rect=rect.expand(point)
			rectangles.append(rect)
		elif row.has("position"):
			rectangles.append(Rect2(DATA.point(row.position),Vector2.ZERO).grow(float(row.radius) if row.type == "terrain" else 2*float(row.get("scale",1))))
	for point in entries: rectangles.append(Rect2(DATA.point(point),Vector2.ZERO).grow(1))
	if rectangles.is_empty(): return Rect2(center-Vector2(25,25),Vector2(50,50))
	var bounds: Rect2 = rectangles[0]
	for rect in rectangles: bounds=bounds.merge(rect)
	return bounds

func _point_hit(at: Vector2) -> int:
	if not objects.has(selected_id): return -1
	var row: Dictionary = objects[selected_id]
	if row.get("locked",false) or row.get("paving",false): return -1
	if row.type != "road" and not (edit_points and (row.type == "ground" or row.get("shape_editable",false))): return -1
	var points := shape_points(row)
	for i in points.size():
		if at.distance_to(screen(points[i])) <= 10: return i
	return -1

func _draw() -> void:
	# Both levels retain world-space draw commands. Detail keeps the actual
	# visible context triangles; only the distant overview uses footprints.
	_draw_cached_overview()

func _draw_foreground() -> void:
	# Só os pisos precisam de ordem; ordenar o mapa inteiro a cada quadro custava caro.
	var ground_ids: Array = []
	for id in objects:
		if objects[id].type == "ground": ground_ids.append(id)
	ground_ids.sort_custom(func(a,b):
		var ap := str(a).begins_with("paving/")
		var bp := str(b).begins_with("paving/")
		if ap and bp: return str(a).get_file().to_int() < str(b).get_file().to_int()
		if ap != bp: return ap
		return a < b)
	for id in ground_ids:
		var row: Dictionary = objects[id]
		if not allowed(row): continue
		_fill(corners(row),Color(row.color) if row.get("paving",false) else preload("res://world/editing/WorldGroundFactory.gd").color(row.surface))
	_draw_piece_preview()
	for row in objects.values():
		if row.type != "context": continue
		var area := Rect2(screen(DATA.point(row.position)-DATA.point(row.size)*.5),DATA.point(row.size)*zoom)
		if not area.intersects(Rect2(Vector2.ZERO,size)): continue
		if row.id == selected_id:
			draw_rect(area,Color("e7c678"),false,2)
			draw_string(ThemeDB.fallback_font,screen(DATA.point(row.position)),str(row.label),HORIZONTAL_ALIGNMENT_LEFT,-1,12,Color("e1e7d8"))
	var spacing := 10.0 if zoom >= 2 else 64.0
	var a := world(Vector2.ZERO)
	var b := world(size)
	for x in range(floori(a.x/spacing),ceili(b.x/spacing)+1): draw_line(screen(Vector2(x*spacing,a.y)),screen(Vector2(x*spacing,b.y)),Color(1,1,1,.045))
	for y in range(floori(a.y/spacing),ceili(b.y/spacing)+1): draw_line(screen(Vector2(a.x,y*spacing)),screen(Vector2(b.x,y*spacing)),Color(1,1,1,.045))
	_draw_roads()
	for row in objects.values():
		if row.type == "road" or not allowed(row): continue
		var p := screen(DATA.point(row.position))
		if not Rect2(Vector2(-200,-200),size+Vector2(400,400)).has_point(p): continue
		var active: bool = row.id == selected_id
		if overview_active() and row.type == "piece" and not active: continue
		match str(row.type):
			"terrain":
				var radius := float(row.radius)*zoom
				var tint := Color("79c8b0") if str(row.get("surface","keep")) == "grass" else Color("d2a974")
				draw_circle(p,radius,Color(tint,.06))
				draw_arc(p,radius,0,TAU,64,Color("e7c678") if active else Color(tint,.55),2 if active else 1,true)
				draw_circle(p,3,tint)
			"building", "prop", "piece", "ground":
				var polygon := corners(row)
				if row.type not in ["piece","ground"]: _fill(polygon,Color(row.get("color","859591")).darkened(.15))
				for i in polygon.size(): polygon[i] = screen(polygon[i])
				polygon.append(polygon[0])
				draw_polyline(polygon,Color("e7c678") if active else Color("8a9e9c"),2.5 if active else 1.0,true)
				if row.get("locked",false): draw_circle(p,3,Color("e59889"))
			"tree":
				var radius := maxf(2,1.25*float(row.get("scale",1))*zoom)
				draw_circle(p,radius,Color("c4d8cc") if row.get("snow",false) else Color("56886c"))
				if active: draw_arc(p,radius+3,0,TAU,24,Color("e7c678"),2,true)
			"manhole":
				var radius := clampf(1.05*zoom,6,16)
				var turn := deg_to_rad(float(row.get("rotation",0)))
				draw_circle(p,radius+1.5,Color("0d1214"))
				draw_circle(p,radius,Color("3a4a46"))
				draw_arc(p,radius,0,TAU,24,Color("e7c678") if active else Color("9fc9a8"),2.0 if active else 1.5,true)
				for bar in [-.5,0.0,.5]: draw_line(p+Vector2(-radius*.75,bar*radius),p+Vector2(radius*.75,bar*radius),Color("9fc9a8"),1.0,true)
				draw_line(p,p+Vector2(sin(turn),cos(turn))*(radius+6),Color("e59889"),2.0,true)
				if active or zoom >= 5.0: draw_string(ThemeDB.fallback_font,p+Vector2(radius+4,4),str(row.get("label","Bueiro")),HORIZONTAL_ALIGNMENT_LEFT,-1,12,Color("d9e6e5"))
			"light":
				var angle := deg_to_rad(float(row.get("rotation",0)))
				var arm_tip := p + Vector2(sin(angle),cos(angle)) * maxf(7,1.3*zoom)
				draw_line(p,arm_tip,Color("b5babe"),2,true)
				draw_circle(arm_tip,2.5,Color(row.get("color","ffe0ab")))
				if active: draw_circle(p,float(row.range)*zoom,Color(1,.85,.4,.10))
				draw_circle(p,clampf(zoom*1.25,1.2,5),Color(row.get("color","ffe0ab")))
				if active: draw_arc(p,9,0,TAU,20,Color("e7c678"),2,true)
	for entry in entries:
		var p := screen(DATA.point(entry))
		draw_line(p-Vector2(4,0),p+Vector2(4,0),Color("e59889"),1.5)
		draw_line(p-Vector2(0,4),p+Vector2(0,4),Color("e59889"),1.5)
	_draw_gizmo()
	_draw_road_handles()
	_draw_region_limits()
	if armed == "terrain" and terrain_hover_valid:
		var radius := 12.0
		if junction_editor != null and is_instance_valid(junction_editor.editor): radius = float(junction_editor.editor.terrain_settings.get("radius",12))
		draw_arc(screen(terrain_hover),radius*zoom,0,TAU,64,Color("e7c678"),2,true)
		draw_circle(screen(terrain_hover),3,Color("e7c678"))
	draw_string(ThemeDB.fallback_font,Vector2(18,size.y-18),"%s · X %.1f  Z %.1f · %.1f px/m" % [region.capitalize(),center.x,center.y,zoom],HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color("b4c9c6"))
	if junction_editor != null: junction_editor.draw_on(self,false)
func _draw_roads() -> void:
	# Reconstruir o traçado custa ~19 ms por quadro. Arrastar um objeto que não é rua e mover
	# a câmera não mudam as ruas, então reaproveitam o traçado já calculado.
	var key: Array = [region,filter_type,selected_id if objects.get(selected_id,{}).get("type","") == "road" else ""]
	if not road_ready or (dragging and str(drag_row.get("type","")) == "road") or key != road_cache_key:
		var roads: Array = []
		for row in objects.values():
			if row.type == "road" and allowed(row):
				var source: Dictionary = row.duplicate(true)
				source.surface = row.get("surface","asphalt")
				source.urban = region == "harbor" and not row.get("pathway",false)
				roads.append(source)
		roads.sort_custom(func(a,b): return a.id < b.id)
		road_drawing.configure(roads)
		road_ready = true
		road_cache_key = key
	for polygon in road_drawing.pavement: _fill(PackedVector2Array(polygon),Color("aaa9a1"))
	# Draw the whole network per layer, never a complete street over another one.
	for layer in ["border","fill"]:
		for surface in road_drawing.surfaces:
			var color := Color("596967") if layer == "border" else (Color("3b4852") if surface.surface == "asphalt" else Color("796652"))
			for polygon in surface[layer]: _fill(PackedVector2Array(polygon),color)
	for mark in road_drawing.markings:
		var line := PackedVector2Array()
		for p in mark.points: line.append(screen(p))
		if line.size() >= 2: draw_polyline(line,Color("e7c678") if mark.id == selected_id else Color("b4ac82"),1.5,true)
	for polygon in road_drawing.crossings: _fill(PackedVector2Array(polygon),Color("eeeade"))

# Triangulate once in stable world coordinates. Re-triangulating screen-space
# slivers at world zoom lost precision and flooded the log with polygon errors.
func _fill(world: PackedVector2Array, color: Color) -> void:
	var mesh := _polygon_mesh(world)
	if mesh != null: draw_mesh(mesh,null,Transform2D(Vector2(zoom,0),Vector2(0,zoom),screen(Vector2.ZERO)),color)

func _polygon_mesh(world: PackedVector2Array) -> ArrayMesh:
	if world.size() < 3: return null
	var key := hash(world)
	if polygon_ok.has(key): return polygon_meshes.get(key)
	if polygon_mesh_order.size() >= POLYGON_MESH_LIMIT:
		var retired: int = polygon_mesh_order.pop_front()
		polygon_meshes.erase(retired)
		polygon_ok.erase(retired)
	polygon_mesh_order.append(key)
	polygon_ok[key] = false
	var points := PackedVector2Array()
	for point in world:
		if not point.is_finite(): return null
		if points.is_empty() or point.distance_squared_to(points[-1]) > 1e-10: points.append(point)
	if points.size() > 1 and points[0].distance_squared_to(points[-1]) <= 1e-10: points.remove_at(points.size()-1)
	if points.size() < 3: return null
	var area := 0.0
	var origin := points[0]
	for i in points.size(): area += (points[i]-origin).cross(points[(i+1)%points.size()]-origin)
	if absf(area) <= 1e-8: return null
	var indices := Geometry2D.triangulate_polygon(points)
	if indices.is_empty(): return null
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = points
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays,[],{},Mesh.ARRAY_FLAG_USE_2D_VERTICES)
	polygon_meshes[key] = mesh
	polygon_ok[key] = true
	return mesh

func pick_candidates(p: Vector2) -> Array[String]:
	var hits: Array = []
	var at := world(p)
	for row in objects.values():
		if not allowed(row): continue
		var hit := false
		var level := 2
		var height := float(row.get("height",0))
		var area := 1.0
		var distance := INF
		if row.type == "road":
			level = 1
			area = INF
			for i in range(row.points.size()-1):
				distance = minf(distance,p.distance_to(Geometry2D.get_closest_point_to_segment(p,screen(DATA.point(row.points[i])),screen(DATA.point(row.points[i+1])))))
			hit = distance < maxf(8,(float(row.width)*.5+float(row.get("sidewalk_width",2.625)))*zoom)
		else:
			distance = p.distance_to(screen(DATA.point(row.position)))
			if row.type == "terrain":
				area = PI*float(row.radius)*float(row.radius)
				hit = distance <= maxf(8,float(row.radius)*zoom)
				level = 3
			if row.has("size"):
				area = DATA.point(row.size).x*DATA.point(row.size).y
				hit = Geometry2D.is_point_in_polygon(at,corners(row))
			if row.type == "context": level = -2
			elif row.type == "ground": level = 0
			elif row.type == "piece":
				# Authored curbs/ramps are visible above the road surface. The road's
				# broad sidewalk click target must not swallow their selection.
				if row.get("ground",false): level = 0 if row.get("parts",[]).is_empty() else 1
				# Exact footprints avoid selecting empty space beside roofs or skew paths.
				if not row.get("parts",[]).is_empty():
					# The footprint bounds every triangle. Avoid traversing all the
					# mountain/harbor geometry for a click far from this object.
					if not hit and not (not row.get("ground",false) and area < 8.0 and distance <= 7.0): continue
					hit = false
					height = -INF
					for part in row.parts:
						var inside := false
						if part.size() > 6:
							var polygon := PackedVector2Array()
							for point in part[6]: polygon.append(DATA.point(point))
							inside = Geometry2D.is_point_in_polygon(at,polygon)
						else: inside = Rect2(Vector2(part[0],part[1]),Vector2(part[2],part[3])).has_point(at)
						if inside:
							hit = true
							height = maxf(height,maxf(float(part[4]),float(row.get("selection_height",-INF))))
					# Small street furniture stays selectable at normal map zoom.
					# Keep large roofs and floor pieces on their exact footprints.
					if not hit and not row.get("ground",false) and area < 8.0 and distance <= 7.0:
						hit = true
						for part in row.parts: height = maxf(height,float(part[4]))
			elif row.type in ["tree","light"]:
				hit = distance < maxf(8,1.25*float(row.get("scale",1))*zoom)
				height = 20.0 if row.type=="tree" else float(row.get("height",4))
				if row.type=="light" and distance<4: level = 3
			if not hit and level == 2 and not row.has("size"): hit = distance < 10
		if hit: hits.append({"id":str(row.id),"level":level,"height":height,"area":area,"distance":distance})
	hits.sort_custom(func(a,b):
		if a.level != b.level: return a.level > b.level
		if a.level == 1 and a.area != b.area: return a.area < b.area
		if not is_equal_approx(a.height,b.height): return a.height > b.height
		if a.level == 0: return a.id > b.id
		if not is_equal_approx(a.area,b.area): return a.area < b.area
		if not is_equal_approx(a.distance,b.distance): return a.distance < b.distance
		return a.id < b.id)
	var result: Array[String] = []
	for hit in hits: result.append(hit.id)
	return result

func _draw_road_handles() -> void:
	if not objects.has(selected_id): return
	var row: Dictionary = objects[selected_id]
	if row.type != "road": return
	for i in row.points.size():
		var at := screen(DATA.point(row.points[i]))
		var color := Color("e7c678")
		if i == 0 or i == row.points.size()-1:
			color = Color("85d9a0") if not road_connection(DATA.point(row.points[i]),row,.01,i).is_empty() else Color("eeaa66")
			draw_arc(at,9,0,TAU,20,color,1.5,true)
		draw_circle(at,6,color)
		if i == selected_point: draw_arc(at,11,0,TAU,24,Color.WHITE,1.5,true)

func pick(p: Vector2) -> String:
	var candidates := pick_candidates(p)
	return candidates[0] if not candidates.is_empty() else ""

func _gui_input(event: InputEvent) -> void:
	if junction_editor != null and junction_editor.input_event(event,false):
		accept_event()
		return
	if event is InputEventMouseButton:
		if event.button_index in [MOUSE_BUTTON_RIGHT,MOUSE_BUTTON_MIDDLE]:
			if dragging: cancel_drag()
			panning = event.pressed
			accept_event()
		elif event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
			if dragging:
				accept_event()
				return
			var anchor := world(event.position)
			zoom = clampf(zoom*(1.2 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1/1.2),MIN_ZOOM,24)
			center += anchor-world(event.position)
			queue_redraw()
			accept_event()
		elif event.button_index == MOUSE_BUTTON_LEFT:
			grab_focus()
			if event.pressed:
				if not armed.is_empty():
					if not _can_edit_world():
						accept_event()
						return
					placed.emit(armed,snapped_point(world(event.position)))
					if armed != "terrain": armed = ""
					accept_event()
					return
				selected_point = -1 if event.alt_pressed else _point_hit(event.position)
				var handle := "" if event.alt_pressed or selected_point >= 0 else gizmo_hit(event.position)
				if not handle.is_empty():
					_start_drag(event.position,handle)
					queue_redraw()
					accept_event()
					return
				var previous_id := selected_id
				if selected_point < 0:
					if event.alt_pressed:
						var candidates := pick_candidates(event.position)
						selected_id = candidates[(candidates.find(selected_id)+1)%candidates.size()] if not candidates.is_empty() else ""
					else: selected_id = pick(event.position)
				if selected_id != previous_id: edit_points = false
				if objects.has(selected_id) and not objects[selected_id].get("locked",false):
					_start_drag(event.position,"")
				selected.emit(selected_id)
			else:
				finish_drag()
			queue_redraw()
			accept_event()
	elif event is InputEventMouseMotion:
		terrain_hover = world(event.position)
		terrain_hover_valid = true
		if armed == "terrain": queue_redraw()
		if panning:
			center -= event.relative/zoom
			queue_redraw()
		elif dragging:
			_update_drag(event.position,event.shift_pressed)
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		armed = ""
		cancel_drag()
		accept_event()

func _input(event: InputEvent) -> void:
	if junction_editor == null or not junction_editor.dragging: return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed: junction_editor.finish()

func pivot(row: Dictionary) -> Vector2:
	if row.type != "road": return DATA.point(row.position)
	var result := Vector2.ZERO
	for point in row.points: result += DATA.point(point)
	return result / row.points.size()

func gizmo_hit(at: Vector2) -> String:
	if not armed.is_empty() or not objects.has(selected_id): return ""
	var row: Dictionary = objects[selected_id]
	if row.get("locked",false) or row.type == "context": return ""
	var offset := at-screen(pivot(row))
	if row.type in ["piece","ground","building","prop"] and offset.distance_to(RESIZE_OFFSET) < 11: return "resize"
	if offset.x >= 18 and offset.x <= AXIS_LENGTH+9 and absf(offset.y) <= 9: return "x"
	if offset.y >= 18 and offset.y <= AXIS_LENGTH+9 and absf(offset.x) <= 9: return "z"
	if rotation_enabled and row.type != "terrain" and not row.get("paving",false) and absf(offset.length()-ROTATE_RADIUS) <= 7: return "rotate"
	return ""

func _start_drag(at: Vector2,axis: String) -> void:
	if not _can_edit_world(): return
	dragging = true
	drag_changed = false
	drag_axis = axis
	drag_origin = world(at)
	drag_row = objects[selected_id].duplicate(true)
	drag_pivot = pivot(drag_row)
	drag_angle = (at-screen(drag_pivot)).angle()
	drag_turn = 0.0

func _can_edit_world() -> bool:
	if junction_editor != null and is_instance_valid(junction_editor.editor):
		var owner_editor: Object = junction_editor.editor
		if owner_editor.has_method("can_edit_world") and not owner_editor.can_edit_world():
			owner_editor._report("Indexando objetos. Aguarde para editar; a câmera continua disponível.")
			return false
	return true

func _update_drag(at: Vector2,snap_rotation: bool) -> void:
	if not _can_edit_world(): cancel_drag(); return
	var row := drag_row.duplicate(true)
	if drag_axis == "resize":
		var start := drag_origin-drag_pivot
		var offset := world(at)-drag_pivot
		var ratio := maxf(.05,offset.dot(start)/maxf(.0001,start.length_squared()))
		if row.type == "piece":
			var factor := DATA.point(drag_row.get("stretch",[1.0,1.0]))*ratio
			row.stretch = [clampf(factor.x,.02,30.0),clampf(factor.y,.02,30.0)]
		elif row.type == "prop": row.scale = clampf(float(drag_row.get("scale",1))*ratio,.05,30.0)
		else:
			var minimum := .25 if row.type == "ground" else 1.0
			var maximum := 2000.0 if row.type == "ground" else 1000.0
			var extent := DATA.point(drag_row.size)*ratio
			row.size = [clampf(extent.x,minimum,maximum),clampf(extent.y,minimum,maximum)]
			if row.has("outline"):
				var factor := DATA.point(row.size)/DATA.point(drag_row.size)
				for i in row.outline.size():
					var point := DATA.point(drag_row.outline[i])*factor
					row.outline[i] = [point.x,point.y]
	elif drag_axis == "rotate":
		var angle := (at-screen(drag_pivot)).angle()
		drag_turn += angle_difference(drag_angle,angle)
		drag_angle = angle
		var degrees := float(drag_row.get("rotation",0))-rad_to_deg(drag_turn)
		if snap_rotation: degrees = snappedf(degrees,15.0)
		var delta := deg_to_rad(float(drag_row.get("rotation",0))-degrees)
		row.rotation = wrapf(degrees,-180,180)
		if row.type == "road":
			for i in row.points.size():
				var point := drag_pivot+(DATA.point(drag_row.points[i])-drag_pivot).rotated(delta)
				row.points[i] = [point.x,point.y]
	else:
		var offset := world(at)-drag_origin
		if drag_axis == "x": offset.y = 0
		elif drag_axis == "z": offset.x = 0
		if row.type == "road":
			# Whole-road movement is rigid: preserve the relative positions of bends.
			if selected_point < 0: offset = snapped_point(offset)
			for i in row.points.size():
				if selected_point >= 0 and selected_point != i: continue
				var point := DATA.point(drag_row.points[i])+offset
				if selected_point >= 0: point = snapped_point(point)
				if road_snap_enabled and selected_point >= 0 and (i == 0 or i == row.points.size()-1):
					var join := road_connection(point,row,minf(6,maxf(1.5,14.0/zoom)),i)
					if not join.is_empty(): point = join.point
				row.points[i] = [point.x,point.y]
		elif selected_point >= 0 and edit_points and (row.type == "ground" or row.get("shape_editable",false)):
			row.outline = local_outline(drag_row)
			var point := snapped_point(corners(drag_row)[selected_point]+offset)
			var factor := DATA.point(drag_row.get("stretch",[1.0,1.0]))*float(drag_row.get("scale",1.0))
			var local := (point-DATA.point(drag_row.position)).rotated(deg_to_rad(float(drag_row.get("rotation",0))))/factor
			row.outline[selected_point] = [local.x,local.y]
		else:
			var point := snapped_point(DATA.point(drag_row.position)+offset)
			if drag_axis == "x": point.y = float(drag_row.position[1])
			elif drag_axis == "z": point.x = float(drag_row.position[0])
			row.position = [point.x,point.y]
	objects[selected_id] = row
	drag_changed = row != drag_row
	queue_redraw()

func finish_drag() -> void:
	if dragging and not _can_edit_world(): cancel_drag(); return
	var changed := dragging and drag_changed and objects.has(selected_id)
	dragging = false
	drag_axis = ""
	if changed: committed.emit(objects[selected_id].duplicate(true))
	else: selected.emit(selected_id)
	queue_redraw()

# Projection stays exact even with the grid enabled. Ignore the edge being dragged.
func road_connection(at: Vector2, source: Dictionary, radius: float, endpoint: int = -1) -> Dictionary:
	if source.get("pathway",false) or float(source.get("width",0)) < 5: return {}
	var best := radius
	var result := {}
	for target in objects.values():
		if target.type != "road" or target.get("deleted",false) or target.get("pathway",false) or float(target.width) < 5: continue
		for i in range(target.points.size()-1):
			if target.id == source.id and (i == endpoint or i+1 == endpoint): continue
			var a := DATA.point(target.points[i])
			var b := DATA.point(target.points[i+1])
			var point := Geometry2D.get_closest_point_to_segment(at,a,b)
			var distance := at.distance_to(point)
			if distance <= best:
				best = distance
				result = {"point":point,"id":target.id}
	return result

func cancel_drag() -> void:
	if junction_editor != null: junction_editor.cancel()
	if dragging and objects.has(selected_id): objects[selected_id] = drag_row
	dragging = false
	drag_axis = ""
	drag_changed = false
	queue_redraw()

func _draw_gizmo() -> void:
	if not armed.is_empty() or not objects.has(selected_id): return
	var row: Dictionary = objects[selected_id]
	if row.get("locked",false) or row.type == "context": return
	if edit_points and not row.get("paving",false) and (row.type == "ground" or row.get("shape_editable",false)):
		var points := corners(row)
		for i in points.size():
			draw_circle(screen(points[i]),7,Color("142027"))
			draw_circle(screen(points[i]),5,Color("fff3bd") if i == selected_point else Color("e7c678"))
	var origin := screen(pivot(row))
	if row.type in ["piece","ground","building","prop"]:
		var handle := origin+RESIZE_OFFSET
		draw_line(origin,handle,Color("e7c678"),1,true)
		draw_rect(Rect2(handle-Vector2(6,6),Vector2(12,12)),Color("e7c678"))
		draw_string(ThemeDB.fallback_font,handle+Vector2(-35,24),"tamanho",HORIZONTAL_ALIGNMENT_LEFT,-1,13,Color("e7c678"))
	var red := Color("ff7771")
	var blue := Color("78bcff")
	var green := Color("85d9a0")
	if rotation_enabled and row.type != "terrain" and not row.get("paving",false):
		draw_arc(origin,ROTATE_RADIUS,0,TAU,96,Color("142027"),6,true)
		draw_arc(origin,ROTATE_RADIUS,0,TAU,96,green,3 if drag_axis == "rotate" else 2,true)
		draw_circle(origin+Vector2(-ROTATE_RADIUS,0),5,green)
		draw_string(ThemeDB.fallback_font,origin+Vector2(-21,-ROTATE_RADIUS-10),"Y · girar",HORIZONTAL_ALIGNMENT_LEFT,-1,13,green)
	for axis in [[Vector2.RIGHT,red,"X"],[Vector2.DOWN,blue,"Z"]]:
		var direction: Vector2 = axis[0]
		var tip := origin+direction*AXIS_LENGTH
		var normal := direction.orthogonal()
		draw_line(origin+direction*10,tip,Color("142027"),7,true)
		draw_line(origin+direction*10,tip,axis[1],3,true)
		draw_colored_polygon(PackedVector2Array([tip+direction*7,tip-direction*7+normal*6,tip-direction*7-normal*6]),axis[1])
		draw_string(ThemeDB.fallback_font,tip+normal*14,axis[2],HORIZONTAL_ALIGNMENT_LEFT,-1,14,axis[1])
	draw_circle(origin,5,Color("f1e9cf"))
	if dragging:
		var text := "%.1f°" % float(row.get("rotation",0)) if drag_axis == "rotate" else "X %.2f  Z %.2f" % [pivot(row).x,pivot(row).y]
		draw_string(ThemeDB.fallback_font,origin+Vector2(16,-24),text,HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color("ffffff"))

func _draw_piece_preview() -> void:
	if not dragging or drag_row.get("type","") != "piece" or not objects.has(selected_id): return
	var row: Dictionary = objects[selected_id]
	if overview_active():
		var footprint := overview_footprint(row)
		for i in range(0,footprint.get("triangles",[]).size(),3):
			var triangle := PackedVector2Array()
			for j in 3: triangle.append(screen(footprint.triangles[i+j]))
			draw_primitive(triangle,PackedColorArray([Color("827e6c")]),PackedVector2Array())
		return
	if row.has("outline"):
		_fill(corners(row),Color("827e6c"))
		return
	var previous_angle := deg_to_rad(float(drag_row.get("rotation",0)))
	var angle := -deg_to_rad(float(row.get("rotation",0)))
	var factor := DATA.point(row.get("stretch",[1.0,1.0]))/DATA.point(drag_row.get("stretch",[1.0,1.0]))
	for part in drag_row.get("parts",[]):
		if part.size() <= 6: continue
		var polygon := PackedVector2Array()
		for point in part[6]: polygon.append(screen(pivot(row)+((DATA.point(point)-drag_pivot).rotated(previous_angle)*factor).rotated(angle)))
		draw_primitive(polygon,PackedColorArray([Color(part[5])]),PackedVector2Array())

func rebuild_context() -> void:
	invalidate_overview()
	context_index_revision += 1
	context_parts.clear()
	context_owners.clear()
	context_owner_parts.clear()
	context_part_cells.clear()
	context_free_parts.clear()
	context_overview_items.clear()
	for row in objects.values():
		if row.type in ["context","piece"]:
			var overview := overview_footprint(row)
			if not overview.is_empty(): context_overview_items[str(row.id)] = overview
			for part in row.get("parts",[]):
				context_parts.append(part)
				context_owners.append(str(row.id))
	context_cells.clear()
	context_triangles.clear()
	mesh_key = []
	road_ready = false
	cached_cells = Rect2i(-999999,-999999,0,0)
	for index in context_parts.size():
		_index_context_part(index)

	context_mesh=null
	context_index_progress = 1.0
	context_overview_dirty = true

func _index_context_part(index: int) -> void:
	var owner: String = context_owners[index]
	if not context_owner_parts.has(owner): context_owner_parts[owner] = []
	context_owner_parts[owner].append(index)
	var part: Array = context_parts[index]
	var cells: Array[Vector2i] = []
	for x in range(floori(part[0]/64),floori((part[0]+part[2])/64)+1):
		for z in range(floori(part[1]/64),floori((part[1]+part[3])/64)+1):
			var key := Vector2i(x,z)
			if not context_cells.has(key): context_cells[key] = []
			context_cells[key].append(index)
			cells.append(key)
	context_part_cells[index] = cells

## Stable slots keep triangulation and cell lists for every untouched object.
## Editing one bin must not sort and re-index the entire world.
func update_context(changed_ids: Array) -> void:
	invalidate_overview()
	context_index_revision += 1
	for owner in changed_ids:
		for index in context_owner_parts.get(owner,[]):
			for key in context_part_cells.get(index,[]):
				if context_cells.has(key):
					context_cells[key].erase(index)
					if context_cells[key].is_empty(): context_cells.erase(key)
			context_parts[index] = null
			context_owners[index] = ""
			context_triangles.erase(index)
			context_part_cells.erase(index)
			context_free_parts.append(index)
		context_owner_parts.erase(owner)
		context_overview_items.erase(owner)
		var row: Dictionary = objects.get(owner,{})
		if row.get("type","") not in ["piece","context"]: continue
		var overview := overview_footprint(row)
		if not overview.is_empty(): context_overview_items[str(owner)] = overview
		for part in row.get("parts",[]):
			var index: int = context_free_parts.pop_back() if not context_free_parts.is_empty() else context_parts.size()
			if index == context_parts.size():
				context_parts.append(part)
				context_owners.append(str(owner))
			else:
				context_parts[index] = part
				context_owners[index] = str(owner)
			_index_context_part(index)
	mesh_key = []
	cached_cells = Rect2i(-999999,-999999,0,0)
	context_mesh = null
	context_index_progress = 1.0
	context_overview_dirty = true
	queue_redraw()

func overview_active() -> bool:
	return zoom <= OVERVIEW_ZOOM

func invalidate_overview() -> void:
	overview_revision += 1

func terrain_topography_tiles() -> Array:
	return terrain_topographies.get(region,[]) if terrain_topography_visible else []

func set_terrain_tiles(area: String, tiles: Array) -> void:
	set_terrain_topography(area,tiles)

func set_terrain_topography(area: String, tiles: Array) -> void:
	var valid: Array = []
	var sources := {}
	var foregrounds := {}
	for value in tiles:
		if not value is Dictionary or not value.get("texture") is Texture2D: continue
		var raw: Variant = value.get("bounds",[])
		var bounds := Rect2()
		if raw is Rect2: bounds = raw
		elif raw is Array and raw.size() == 4 and DATA.number(raw[0]) and DATA.number(raw[1]) and DATA.number(raw[2]) and DATA.number(raw[3]): bounds = Rect2(raw[0],raw[1],raw[2],raw[3])
		else: continue
		if not bounds.position.is_finite() or not bounds.size.is_finite() or bounds.size.x <= 0 or bounds.size.y <= 0: continue
		var ids: Array = value.get("source_ids",[]) if value.get("source_ids",[]) is Array else []
		for id in ids:
			if id is String: sources[id] = true
		var front: Variant = value.get("foreground",{})
		if front is Dictionary:
			for id in front:
				if id is String and front[id] is Dictionary:
					foregrounds[id] = front[id]
					sources[id] = true
		valid.append({"texture":value.texture,"bounds":bounds,"source_ids":ids.duplicate(),"path":value.get("path","")})
	terrain_topographies[area] = valid
	terrain_topography_sources[area] = sources
	terrain_topography_foregrounds[area] = foregrounds
	terrain_topography_foreground_meshes[area] = _topography_foreground_mesh(foregrounds)
	terrain_topography_revision += 1
	if area == region: _invalidate_topography_geometry()

func set_terrain_topography_visible(value: bool) -> void:
	if terrain_topography_visible == value: return
	terrain_topography_visible = value
	_invalidate_topography_geometry()

func _invalidate_topography_geometry() -> void:
	invalidate_overview()
	context_overview_dirty = true
	context_mesh = null
	mesh_key = []
	queue_redraw()

func _draw_terrain_topography(target: CanvasItem, world_space: bool) -> void:
	for tile in terrain_topography_tiles():
		var rect: Rect2 = tile.bounds
		if not world_space: rect = Rect2(screen(rect.position),rect.size*zoom)
		# Alpha is the real triangulated coverage; never fill the tile's whole box.
		target.draw_texture_rect(tile.texture,rect,false)
	if terrain_topography_visible:
		var front: ArrayMesh = terrain_topography_foreground_meshes.get(region)
		if front != null:
			var transform := Transform2D.IDENTITY if world_space else Transform2D(Vector2(zoom,0),Vector2(0,zoom),screen(Vector2.ZERO))
			target.draw_mesh(front,null,transform)

func _terrain_owner_replaced(owner: String) -> bool:
	if not terrain_topography_visible or not terrain_topography_sources.get(region,{}).has(owner): return false
	if terrain_topography_foregrounds.get(region,{}).has(owner): return true
	var row: Dictionary = objects.get(owner,{})
	var parts: Array = row.get("parts",[])
	if not parts.is_empty() and parts.all(func(part): return part is Array and part.size()>7 and part[7]==true): return true
	return "terrain" in str(row.get("kind","")) or row.get("terrain_surface",false)

func _terrain_part_replaced(index: int) -> bool:
	if terrain_topography_tiles().is_empty(): return false
	var part: Array = context_parts[index]
	if part.size() > 7 and part[7] == true: return true
	var owner: String = context_owners[index]
	return _terrain_owner_replaced(owner)

func _topography_foreground_mesh(rows: Dictionary) -> ArrayMesh:
	var parts: Array = []
	for row in rows.values():
		var source: Variant = row.get("parts",[])
		if not source is Array: continue
		for part in source:
			if part is Array and part.size()>=6 and DATA.number(part[4]): parts.append(part)
	parts.sort_custom(func(a,b): return float(a[4])<float(b[4]))
	var vertices := PackedVector2Array()
	var colors := PackedColorArray()
	for part in parts:
		if not part is Array or part.size()<6: continue
		var points := PackedVector2Array()
		if part.size()>6:
			for point in part[6]: points.append(DATA.point(point))
		else: points = PackedVector2Array([Vector2(part[0],part[1]),Vector2(part[0]+part[2],part[1]),Vector2(part[0]+part[2],part[1]+part[3]),Vector2(part[0],part[1]+part[3])])
		if points.size()<3: continue
		var area := 0.0
		for i in points.size(): area += (points[i]-points[0]).cross(points[(i+1)%points.size()]-points[0])
		if absf(area)<1e-8: continue
		for index in Geometry2D.triangulate_polygon(points):
			vertices.append(points[index])
			colors.append(Color(part[5]))
	if vertices.is_empty(): return null
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_COLOR] = colors
	var result := ArrayMesh.new()
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays,[],{},Mesh.ARRAY_FLAG_USE_2D_VERTICES)
	return result

# A retained CanvasItem records geometry once. Pan/zoom change only its transform;
# overlays and precise picking remain live on the parent Control.
func _detail_rows() -> Array:
	var index_key: Array = [overview_revision,context_index_revision,objects.size()]
	if index_key != detail_object_index_key:
		detail_object_index_key = index_key
		detail_object_cells.clear()
		detail_rows_key = []
		for row: Dictionary in objects.values():
			if row.get("type","") in ["piece","context","road"]: continue
			var bounds := Rect2(DATA.point(row.get("position",[0,0])),Vector2.ZERO)
			if row.has("size"):
				for point in corners(row): bounds = bounds.expand(point)
			else: bounds = bounds.grow(float(row.get("radius",row.get("range",2))) if row.type == "terrain" else 4*float(row.get("scale",1)))
			for x in range(floori(bounds.position.x/64),floori(bounds.end.x/64)+1):
				for z in range(floori(bounds.position.y/64),floori(bounds.end.y/64)+1):
					var cell := Vector2i(x,z)
					if not detail_object_cells.has(cell): detail_object_cells[cell] = []
					detail_object_cells[cell].append(str(row.id))
	var key: Array = [cached_cells,index_key]
	if key == detail_rows_key: return detail_visible_rows
	detail_rows_key = key
	var found := {}
	for x in range(cached_cells.position.x,cached_cells.end.x):
		for z in range(cached_cells.position.y,cached_cells.end.y):
			for id in detail_object_cells.get(Vector2i(x,z),[]): found[id] = true
	detail_visible_rows = []
	for id in found:
		if objects.has(id): detail_visible_rows.append(objects[id])
	return detail_visible_rows

func _draw_detail_grid() -> void:
	var spacing := 10.0 if zoom >= 2 else 64.0
	var a := world(Vector2.ZERO)
	var b := world(size)
	for x in range(floori(a.x/spacing),ceili(b.x/spacing)+1): draw_line(screen(Vector2(x*spacing,a.y)),screen(Vector2(x*spacing,b.y)),Color(1,1,1,.045))
	for z in range(floori(a.y/spacing),ceili(b.y/spacing)+1): draw_line(screen(Vector2(a.x,z*spacing)),screen(Vector2(b.x,z*spacing)),Color(1,1,1,.045))

func _draw_cached_overview() -> void:
	if not is_instance_valid(overview_layer):
		overview_layer = Node2D.new()
		overview_layer.name = "RetainedWorldOverview"
		overview_layer.show_behind_parent = true
		add_child(overview_layer)
		overview_layer.draw.connect(_record_overview)
	overview_layer.show()
	overview_layer.transform = Transform2D(Vector2(zoom,0),Vector2(0,zoom),screen(Vector2.ZERO))
	var detailed := not overview_active()
	if detailed: _visible_parts()
	var key := [region,filter_type,overview_revision,context_index_revision,objects.size(),dragging,selected_id if dragging or filter_type != "all" else "",detailed,cached_cells if detailed else Rect2i()]
	if dragging and drag_row.get("type","") == "road":
		key.append(hash(objects.get(selected_id,{})))
		road_ready = false
	if key != overview_layer_key:
		overview_layer_key = key
		overview_layer.queue_redraw()
	# No inventory traversal or road commands on camera movement.
	if detailed: _draw_detail_grid()
	if objects.has(selected_id):
		var row: Dictionary = objects[selected_id]
		if dragging and row.type != "piece":
			if row.has("size"): _fill(corners(row),Color(row.get("color","859591")))
			elif row.type in ["tree","light","manhole"]: draw_circle(screen(DATA.point(row.position)),maxf(2,1.25*float(row.get("scale",1))*zoom),Color("79b18e"))
		if row.type == "terrain":
			draw_arc(screen(DATA.point(row.position)),float(row.radius)*zoom,0,TAU,64,Color("e7c678"),2.5,true)
		elif row.has("size"):
			var polygon := corners(row)
			for i in polygon.size(): polygon[i] = screen(polygon[i])
			polygon.append(polygon[0])
			draw_polyline(polygon,Color("e7c678"),2.5,true)
		else: draw_arc(screen(DATA.point(row.get("position",[0,0]))),8,0,TAU,20,Color("e7c678"),2,true)
	_draw_piece_preview()
	_draw_gizmo()
	_draw_road_handles()
	_draw_region_limits()
	if armed == "terrain" and terrain_hover_valid:
		var radius := 12.0
		if junction_editor != null and is_instance_valid(junction_editor.editor): radius = float(junction_editor.editor.terrain_settings.get("radius",12))
		draw_arc(screen(terrain_hover),radius*zoom,0,TAU,64,Color("e7c678"),2,true)
	draw_string(ThemeDB.fallback_font,Vector2(18,size.y-18),"%s · X %.1f  Z %.1f · %.2f px/m" % [region.capitalize(),center.x,center.y,zoom],HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color("b4c9c6"))
	if junction_editor != null: junction_editor.draw_on(self,false)

func _overview_fill(points: PackedVector2Array, color: Color) -> void:
	var mesh := _polygon_mesh(points)
	if mesh != null:
		overview_layer.draw_mesh(mesh,null,Transform2D.IDENTITY,color)
		overview_command_count += 1

func _record_overview() -> void:
	overview_record_count += 1
	var began := Time.get_ticks_usec()
	overview_command_count = 0
	overview_layer.draw_rect(Rect2(-20000,-20000,40000,40000),Color("152b38"))
	for item in land: overview_layer.draw_rect(Rect2(float(item[0])/16,float(item[1])/16,float(item[2])/16,float(item[3])/16),Color("293b35"))
	for tile in terrain: overview_layer.draw_rect(Rect2(tile[0],tile[1],tile[2],tile[3]),Color(tile[4]))
	for poly in land_polygons:
		var points := PackedVector2Array()
		for p in poly: points.append(DATA.point(p))
		_overview_fill(points,Color("43524b"))
	_draw_terrain_topography(overview_layer,true)
	var excluded := selected_id if dragging and drag_row.get("type","") == "piece" else ""
	var detailed := not overview_active()
	var context: ArrayMesh
	var rows: Array
	if detailed:
		var visible := _visible_parts()
		var detail_key := [cached_cells,excluded,context_index_revision,terrain_topography_revision]
		if detail_key != mesh_key:
			_rebuild_context_mesh(visible,excluded)
			mesh_key = detail_key
		context = context_mesh
		detail_visible_context_count = visible.size()
		rows = _detail_rows()
	else:
		context = _overview_mesh(excluded)
		rows = objects.values()
	if context != null: overview_layer.draw_mesh(context,null)
	var grounds: Array = []
	for row in rows:
		if row.type == "ground" and allowed(row) and not (dragging and row.id == selected_id): grounds.append(row)
	grounds.sort_custom(func(a,b):
		var ap := str(a.id).begins_with("paving/")
		var bp := str(b.id).begins_with("paving/")
		if ap and bp: return str(a.id).get_file().to_int()<str(b.id).get_file().to_int()
		if ap != bp: return ap
		return str(a.id)<str(b.id))
	for row in grounds: _overview_fill(corners(row),Color(row.color) if row.get("paving",false) else preload("res://world/editing/WorldGroundFactory.gd").color(row.surface))
	# Configure only on an actual road invalidation, then retain its whole network.
	var road_key := [region,filter_type,selected_id if objects.get(selected_id,{}).get("type","") == "road" else ""]
	if not road_ready or road_cache_key != road_key:
		var roads: Array = []
		for row in objects.values():
			if row.type != "road" or not allowed(row): continue
			var source: Dictionary = row.duplicate(true)
			source.surface = row.get("surface","asphalt")
			source.urban = region == "harbor" and not row.get("pathway",false)
			roads.append(source)
		roads.sort_custom(func(a,b): return a.id<b.id)
		road_drawing.configure(roads)
		road_ready = true
		road_cache_key = road_key
	for polygon in road_drawing.pavement: _overview_fill(PackedVector2Array(polygon),Color("aaa9a1"))
	for layer in ["border","fill"]:
		for surface in road_drawing.surfaces:
			var color := Color("596967") if layer == "border" else (Color("3b4852") if surface.surface == "asphalt" else Color("796652"))
			for polygon in surface[layer]: _overview_fill(PackedVector2Array(polygon),color)
	for mark in road_drawing.markings:
		if mark.points.size() >= 2: overview_layer.draw_polyline(PackedVector2Array(mark.points),Color("b4ac82"),2,true)
	for polygon in road_drawing.crossings: _overview_fill(PackedVector2Array(polygon),Color("eeeade"))
	for row in rows:
		if not allowed(row) or row.type in ["road","context","piece","ground"]: continue
		if dragging and row.id == selected_id: continue
		var at := DATA.point(row.position)
		match str(row.type):
			"building","prop": _overview_fill(corners(row),Color(row.get("color","859591")).darkened(.15))
			"tree": overview_layer.draw_circle(at,1.25*float(row.get("scale",1)),Color("c4d8cc") if row.get("snow",false) else Color("56886c"))
			"light": overview_layer.draw_circle(at,1.2,Color(row.get("color","ffe0ab")))
			"manhole": overview_layer.draw_circle(at,1.05,Color("9fc9a8"))
			"terrain": overview_layer.draw_arc(at,float(row.radius),0,TAU,48,Color("d2a974"),1.0,true)
	if detailed:
		for row: Dictionary in rows:
			if row.type not in ["building","prop","ground"] or not allowed(row) or (dragging and row.id == selected_id): continue
			var outline := corners(row)
			if outline.size()<3: continue
			outline.append(outline[0])
			overview_layer.draw_polyline(outline,Color("8a9e9c"),-1.0,false)
	for entry in entries:
		var at := DATA.point(entry)
		overview_layer.draw_line(at-Vector2(3,0),at+Vector2(3,0),Color("e59889"),1.5)
		overview_layer.draw_line(at-Vector2(0,3),at+Vector2(0,3),Color("e59889"),1.5)
	overview_rebuild_ms = float(Time.get_ticks_usec()-began)/1000.0

func set_region_bounds_visible(value: bool) -> void:
	region_bounds_visible = value
	if value and map_region_bounds.is_empty() and junction_editor != null and is_instance_valid(junction_editor.editor):
		for area in ["harbor","mountain","desert"]: map_region_bounds[area] = junction_editor.editor.region_bounds(area)
	queue_redraw()

func set_region_bounds(bounds: Dictionary) -> void:
	map_region_bounds = bounds.duplicate()
	queue_redraw()

func _draw_region_limits() -> void:
	if not region_bounds_visible: return
	var colors := {"harbor":Color("79c8b0"),"mountain":Color("b6cae8"),"desert":Color("d8b579")}
	for area in map_region_bounds:
		var rect: Rect2 = map_region_bounds[area]
		if not rect.has_area(): continue
		var display := Rect2(screen(rect.position),rect.size*zoom)
		var tint: Color = colors.get(area,Color.WHITE)
		draw_rect(display,Color(tint,.7),false,1.5)
		if display.intersects(Rect2(Vector2.ZERO,size)):
			var label := "Montanha" if area == "mountain" else ("Deserto" if area == "desert" else "Harbor")
			draw_string(ThemeDB.fallback_font,display.position+Vector2(6,18),label,HORIZONTAL_ALIGNMENT_LEFT,-1,14,tint)

## At world scale a compact footprint carries the object shape; detailed scene
## triangles remain available unchanged as soon as the user zooms in.
func overview_footprint(row: Dictionary) -> Dictionary:
	var parts: Array = row.get("parts",[])
	if parts.is_empty() or not row.has("position") or not row.has("size"): return {}
	var compact := row.duplicate()
	if compact.get("outline",[]).size() > 32: compact.erase("outline")
	if compact.get("default_outline",[]).size() > 32: compact.erase("default_outline")
	var polygon := corners(compact)
	var indices := Geometry2D.triangulate_polygon(polygon)
	if indices.is_empty():
		compact.erase("outline")
		compact.erase("default_outline")
		polygon = corners(compact)
		indices = Geometry2D.triangulate_polygon(polygon)
	var triangles := PackedVector2Array()
	for index in indices: triangles.append(polygon[index])
	var top: Array = parts[-1]
	var label := str(row.get("label","")).to_lower()
	var ground: bool = row.get("ground",false) or "terrain" in label or "terreno" in label
	var layer := -1 if row.type == "context" else (0 if ground else 1)
	return {"triangles":triangles,"color":Color(top[5]),"height":float(row.get("selection_height",top[4])),"layer":layer}

func _overview_mesh(excluded := "") -> ArrayMesh:
	if not context_overview_dirty and context_overview_excluded == excluded: return context_overview_mesh
	var ids: Array = context_overview_items.keys()
	ids.sort_custom(func(a,b):
		var al := int(context_overview_items[a].layer)
		var bl := int(context_overview_items[b].layer)
		if al != bl: return al < bl
		var ah := float(context_overview_items[a].height)
		var bh := float(context_overview_items[b].height)
		return ah < bh if not is_equal_approx(ah,bh) else str(a) < str(b))
	var vertices := PackedVector2Array()
	var colors := PackedColorArray()
	for id in ids:
		if id == excluded: continue
		if _terrain_owner_replaced(str(id)): continue
		var item: Dictionary = context_overview_items[id]
		for point in item.triangles:
			vertices.append(point)
			colors.append(item.color)
	context_overview_mesh = null
	if not vertices.is_empty():
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_COLOR] = colors
		context_overview_mesh = ArrayMesh.new()
		context_overview_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays,[],{},Mesh.ARRAY_FLAG_USE_2D_VERTICES)
	context_overview_dirty = false
	context_overview_excluded = excluded
	return context_overview_mesh

func _rebuild_context_mesh(ids: Array, excluded := "") -> void:
	# Visible static triangles in height order; pan within a cell reuses the per-part cache.
	var vertices := PackedVector2Array()
	var colors := PackedColorArray()
	for id in ids:
		if excluded != "" and context_owners[id] == excluded: continue
		if _terrain_part_replaced(id): continue
		var part: Array = context_parts[id]
		var triangles := _part_triangles(id)
		var color := Color(part[5])
		for vertex in triangles:
			vertices.append(vertex)
			colors.append(color)
	context_mesh=null
	if not vertices.is_empty():
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX]=vertices
		arrays[Mesh.ARRAY_COLOR]=colors
		context_mesh=ArrayMesh.new()
		context_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays,[],{},Mesh.ARRAY_FLAG_USE_2D_VERTICES)

func _part_triangles(id: int) -> PackedVector2Array:
	if context_triangles.has(id): return context_triangles[id]
	var part: Array = context_parts[id]
	var polygon := PackedVector2Array()
	if part.size()>6:
		for point in part[6]: polygon.append(DATA.point(point))
	else:
		polygon=PackedVector2Array([Vector2(part[0],part[1]),Vector2(part[0]+part[2],part[1]),Vector2(part[0]+part[2],part[1]+part[3]),Vector2(part[0],part[1]+part[3])])
	var triangles := PackedVector2Array()
	# Contorno de área zero (linhas colineares) não tem triângulos. Descartá-lo antes evita
	# o erro "triangulation failed" do Godot, que antes saía a cada reconstrução da malha.
	var area := 0.0
	for i in polygon.size(): area += polygon[i].cross(polygon[(i+1)%polygon.size()])
	if polygon.size() >= 3 and absf(area) > 1e-6:
		for index in Geometry2D.triangulate_polygon(polygon): triangles.append(polygon[index])
	context_triangles[id] = triangles
	return triangles

func _visible_parts() -> Array:
	var start := world(Vector2.ZERO)/64
	var finish := world(size)/64
	var first := Vector2i(floori(start.x),floori(start.y))
	var last := Vector2i(floori(finish.x),floori(finish.y))
	var cells := Rect2i(first,last-first+Vector2i.ONE)
	if cells == cached_cells or cached_cells.encloses(cells): return visible_part_ids
	# Hysteresis: keep this complete margin until the view leaves it; do not
	# recenter the cache on every cell crossing or ordinary camera movement.
	cells = cells.grow(DETAIL_CELL_MARGIN)
	first = cells.position
	last = cells.end-Vector2i.ONE
	cached_cells = cells
	var found := {}
	for x in range(first.x,last.x+1):
		for z in range(first.y,last.y+1):
			for index in context_cells.get(Vector2i(x,z),[]): found[index] = true
	visible_part_ids = found.keys()
	visible_part_ids.sort_custom(func(a,b):
		var ah := float(context_parts[a][4])
		var bh := float(context_parts[b][4])
		return ah < bh if not is_equal_approx(ah,bh) else a < b)
	return visible_part_ids
