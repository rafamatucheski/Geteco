@tool
extends Control
const DATA := preload("res://world/editing/WorldEditData.gd")
const MIN_ZOOM := .05
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
			rectangles.append(Rect2(DATA.point(row.position),Vector2.ZERO).grow(2*float(row.get("scale",1))))
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
	draw_rect(Rect2(Vector2.ZERO,size),Color("152b38"))
	for rect in land:
		draw_rect(Rect2(screen(Vector2(rect[0],rect[1])/16.0),Vector2(rect[2],rect[3])*zoom/16.0),Color("293b35"))
	for tile in terrain:
		draw_rect(Rect2(screen(Vector2(tile[0],tile[1])),Vector2(tile[2],tile[3])*zoom),Color(tile[4]))
	for poly in land_polygons:
		var points := PackedVector2Array()
		for p in poly: points.append(screen(DATA.point(p)))
		if points.size() >= 3: draw_colored_polygon(points,Color("43524b"))
	var previous_cells := cached_cells
	var visible_ids := _visible_parts()
	if context_mesh==null or previous_cells!=cached_cells: _rebuild_context_mesh(visible_ids)
	if context_mesh!=null and not (dragging and drag_row.get("type", "")=="piece"):
		draw_mesh(context_mesh,null,Transform2D(Vector2(zoom,0),Vector2(0,zoom),screen(Vector2.ZERO)))
	_draw_context_fallback()
	_draw_foreground()

func _draw_context_fallback() -> void:
	if context_mesh!=null and not (dragging and drag_row.get("type", "")=="piece"): return
	for part_id in _visible_parts():
		if dragging and drag_row.get("type", "") == "piece" and context_owners[part_id] == selected_id: continue
		var part: Array = context_parts[part_id]
		if part[2]*zoom < .5 and part[3]*zoom < .5: continue
		var rect := Rect2(screen(Vector2(part[0],part[1])),Vector2(part[2],part[3])*zoom)
		if not rect.intersects(Rect2(Vector2.ZERO,size)): continue
		if part.size() > 6:
			var polygon := PackedVector2Array()
			for p in part[6]: polygon.append(screen(DATA.point(p)))
			if polygon.size()>4: draw_colored_polygon(polygon,Color(part[5]))
			else: draw_primitive(polygon,PackedColorArray([Color(part[5])]),PackedVector2Array())
		else: draw_rect(rect,Color(part[5]))

func _draw_foreground() -> void:
	var ground_ids := objects.keys()
	ground_ids.sort_custom(func(a,b):
		var ap := str(a).begins_with("paving/")
		var bp := str(b).begins_with("paving/")
		if ap and bp: return str(a).get_file().to_int() < str(b).get_file().to_int()
		if ap != bp: return ap
		return a < b)
	for id in ground_ids:
		var row: Dictionary = objects[id]
		if row.type != "ground" or not allowed(row): continue
		var polygon := corners(row)
		for i in polygon.size(): polygon[i] = screen(polygon[i])
		if not Geometry2D.triangulate_polygon(polygon).is_empty(): draw_colored_polygon(polygon,Color(row.color) if row.get("paving",false) else preload("res://world/editing/WorldGroundFactory.gd").color(row.surface))
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
		match str(row.type):
			"building", "prop", "piece", "ground":
				var polygon := corners(row)
				for i in polygon.size(): polygon[i] = screen(polygon[i])
				if row.type not in ["piece","ground"]: draw_colored_polygon(polygon,Color(row.get("color","859591")).darkened(.15))
				polygon.append(polygon[0])
				draw_polyline(polygon,Color("e7c678") if active else Color("8a9e9c"),2.5 if active else 1.0,true)
				if row.get("locked",false): draw_circle(p,3,Color("e59889"))
			"tree":
				var radius := maxf(2,1.25*float(row.get("scale",1))*zoom)
				draw_circle(p,radius,Color("c4d8cc") if row.get("snow",false) else Color("56886c"))
				if active: draw_arc(p,radius+3,0,TAU,24,Color("e7c678"),2,true)
			"light":
				if active: draw_circle(p,float(row.range)*zoom,Color(1,.85,.4,.10))
				draw_circle(p,clampf(zoom*1.25,1.2,5),Color(row.get("color","ffe0ab")))
				if active: draw_arc(p,9,0,TAU,20,Color("e7c678"),2,true)
	for entry in entries:
		var p := screen(DATA.point(entry))
		draw_line(p-Vector2(4,0),p+Vector2(4,0),Color("e59889"),1.5)
		draw_line(p-Vector2(0,4),p+Vector2(0,4),Color("e59889"),1.5)
	_draw_gizmo()
	_draw_road_handles()
	draw_string(ThemeDB.fallback_font,Vector2(18,size.y-18),"%s · X %.1f  Z %.1f · %.1f px/m" % [region.capitalize(),center.x,center.y,zoom],HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color("b4c9c6"))
	if junction_editor != null: junction_editor.draw_on(self,false)
func _draw_roads() -> void:
	var roads: Array = []
	for row in objects.values():
		if row.type == "road" and allowed(row):
			var source: Dictionary = row.duplicate(true)
			source.surface = row.get("surface","asphalt")
			source.urban = region == "harbor" and not row.get("pathway",false)
			roads.append(source)
	roads.sort_custom(func(a,b): return a.id < b.id)
	road_drawing.configure(roads)
	for polygon in road_drawing.pavement:
		var points := PackedVector2Array()
		for p in polygon: points.append(screen(p))
		if points.size() >= 3: draw_colored_polygon(points,Color("aaa9a1"))
	# Draw the whole network per layer, never a complete street over another one.
	for layer in ["border","fill"]:
		for surface in road_drawing.surfaces:
			var color := Color("596967") if layer == "border" else (Color("3b4852") if surface.surface == "asphalt" else Color("796652"))
			for polygon in surface[layer]:
				var points := PackedVector2Array()
				for p in polygon: points.append(screen(p))
				if points.size() >= 3: draw_colored_polygon(points,color)
	for mark in road_drawing.markings:
		var line := PackedVector2Array()
		for p in mark.points: line.append(screen(p))
		if line.size() >= 2: draw_polyline(line,Color("e7c678") if mark.id == selected_id else Color("b4ac82"),1.5,true)
	for polygon in road_drawing.crossings:
		var points := PackedVector2Array()
		for p in polygon: points.append(screen(p))
		if points.size() >= 3: draw_colored_polygon(points,Color("eeeade"))

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
			if row.has("size"):
				area = DATA.point(row.size).x*DATA.point(row.size).y
				hit = Geometry2D.is_point_in_polygon(at,corners(row))
			if row.type == "context": level = -2
			elif row.type == "ground": level = 0
			elif row.type == "piece":
				# Authored curbs/ramps are visible above the road surface. The road's
				# broad sidewalk click target must not swallow their selection.
				if row.get("ground",false): level = 1
				# Exact footprints avoid selecting empty space beside roofs or skew paths.
				if not row.get("parts",[]).is_empty():
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
					placed.emit(armed,snapped_point(world(event.position)))
					armed = ""
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
	if rotation_enabled and row.type != "light" and not row.get("paving",false) and absf(offset.length()-ROTATE_RADIUS) <= 7: return "rotate"
	return ""

func _start_drag(at: Vector2,axis: String) -> void:
	dragging = true
	drag_changed = false
	drag_axis = axis
	drag_origin = world(at)
	drag_row = objects[selected_id].duplicate(true)
	drag_pivot = pivot(drag_row)
	drag_angle = (at-screen(drag_pivot)).angle()
	drag_turn = 0.0

func _update_drag(at: Vector2,snap_rotation: bool) -> void:
	var row := drag_row.duplicate(true)
	if drag_axis == "resize":
		var start := drag_origin-drag_pivot
		var offset := world(at)-drag_pivot
		var ratio := maxf(.05,offset.dot(start)/maxf(.0001,start.length_squared()))
		if row.type == "piece":
			var factor := DATA.point(drag_row.get("stretch",[1.0,1.0]))*ratio
			row.stretch = [clampf(factor.x,.1,4.0),clampf(factor.y,.1,4.0)]
		elif row.type == "prop": row.scale = clampf(float(drag_row.get("scale",1))*ratio,.25,3.0)
		else:
			var minimum := .25 if row.get("paving",false) else (1.0 if row.type == "ground" else 3.0)
			var maximum := 512.0 if row.get("paving",false) else (64.0 if row.type == "ground" else 40.0)
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
	if rotation_enabled and row.type != "light" and not row.get("paving",false):
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
	if row.has("outline"):
		var outline := corners(row)
		for i in outline.size(): outline[i] = screen(outline[i])
		if not Geometry2D.triangulate_polygon(outline).is_empty(): draw_colored_polygon(outline,Color("827e6c"))
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
	context_parts.clear()
	context_owners.clear()
	var ordered: Array = []
	for row in objects.values():
		if row.type in ["context","piece"]:
			for part in row.get("parts",[]): ordered.append({"part":part,"owner":row.id})
	ordered.sort_custom(func(a,b): return float(a.part[4]) < float(b.part[4]))
	for entry in ordered:
		context_parts.append(entry.part)
		context_owners.append(entry.owner)
	context_cells.clear()
	cached_cells = Rect2i(-999999,-999999,0,0)
	for index in context_parts.size():
		var part: Array = context_parts[index]
		for x in range(floori(part[0]/64),floori((part[0]+part[2])/64)+1):
			for z in range(floori(part[1]/64),floori((part[1]+part[3])/64)+1):
				var key := Vector2i(x,z)
				if not context_cells.has(key): context_cells[key] = []
				context_cells[key].append(index)

	context_mesh=null

func _rebuild_context_mesh(ids: Array) -> void:
	# Cache visible static triangles in height order; pan within a cell reuses them.
	var vertices := PackedVector2Array()
	var colors := PackedColorArray()
	for id in ids:
		var part: Array = context_parts[id]
		var polygon := PackedVector2Array()
		if part.size()>6:
			for point in part[6]: polygon.append(DATA.point(point))
		else:
			polygon=PackedVector2Array([Vector2(part[0],part[1]),Vector2(part[0]+part[2],part[1]),Vector2(part[0]+part[2],part[1]+part[3]),Vector2(part[0],part[1]+part[3])])
		for index in Geometry2D.triangulate_polygon(polygon):
			vertices.append(polygon[index])
			colors.append(Color(part[5]))
	context_mesh=null
	if not vertices.is_empty():
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX]=vertices
		arrays[Mesh.ARRAY_COLOR]=colors
		context_mesh=ArrayMesh.new()
		context_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays,[],{},Mesh.ARRAY_FLAG_USE_2D_VERTICES)

func _visible_parts() -> Array:
	var start := world(Vector2.ZERO)/64
	var finish := world(size)/64
	var first := Vector2i(floori(start.x),floori(start.y))
	var last := Vector2i(floori(finish.x),floori(finish.y))
	var cells := Rect2i(first,last-first+Vector2i.ONE)
	if cells == cached_cells: return visible_part_ids
	cached_cells = cells
	var found := {}
	for x in range(first.x,last.x+1):
		for z in range(first.y,last.y+1):
			for index in context_cells.get(Vector2i(x,z),[]): found[index] = true
	visible_part_ids = found.keys()
	visible_part_ids.sort()
	return visible_part_ids
