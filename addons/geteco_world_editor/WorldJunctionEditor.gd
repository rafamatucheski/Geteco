@tool
extends RefCounted
const DATA := preload("res://world/editing/WorldEditData.gd")
var editor
var enabled := false
var toggle: Button
var layouts: Array[Dictionary] = []
var selected := ""
var entry_index := 0
var dragging := false
var start := Vector2.ZERO
var original := 0.0
var proposed := 0.0
var drag_3d := false

func setup(owner_editor) -> void:
	editor = owner_editor
	toggle = editor._button(editor.actions_bar,"Cruzamentos",func(): set_enabled(toggle.button_pressed))
	toggle.toggle_mode = true
	toggle.tooltip_text = "Selecionar cruzamentos e ajustar cada faixa em 2D ou 3D"

func set_enabled(value: bool) -> void:
	cancel()
	enabled = value
	toggle.set_pressed_no_signal(value)
	if value:
		editor.canvas.cancel_drag()
		editor.canvas.armed = ""
		editor.canvas.selected_id = ""
		editor.active_sidebar = "properties"
		editor.properties_requested = true
		rebuild()
	editor._select(editor.canvas.selected_id)
	redraw()

func rebuild() -> void:
	if not enabled: return
	var sources: Array[Dictionary] = []
	for row in editor.canvas.objects.values():
		if row.type != "road" or row.get("editor_region","") != "harbor" or row.get("pathway",false): continue
		var source: Dictionary = row.duplicate(true)
		source.points = PackedVector3Array()
		for point in row.points: source.points.append(DATA.xyz(point))
		sources.append(source)
	sources.sort_custom(func(a,b): return a.id < b.id)
	var joined: Array[Dictionary] = []
	for row in preload("res://world/editing/WorldRoadJoins.gd").resolve(sources): joined.append(row)
	var geometry := preload("res://world/urban_detail/HarborRoadGeometry3D.gd").new()
	geometry.configure(joined,false)
	layouts = geometry.crossing_layout
	if current().is_empty(): selected = ""
	redraw()

func current() -> Dictionary:
	for item in layouts:
		if item.id == selected: return item
	return {}

func entry() -> Dictionary:
	var junction := current()
	if junction.is_empty(): return {}
	entry_index = clampi(entry_index,0,junction.entries.size()-1)
	return junction.entries[entry_index]

func properties() -> void:
	var label := Label.new()
	label.text = "Cruzamento"
	editor.properties.add_child(label)
	var junction := current()
	if junction.is_empty():
		label.text = "Clique em um cruzamento no mapa."
		return
	var options := OptionButton.new()
	options.fit_to_longest_item = false
	for i in junction.entries.size():
		var arm: Dictionary = junction.entries[i]
		options.add_item("%d · %s" % [i+1,str(arm.road_id).get_file().capitalize()])
	options.select(entry_index)
	options.item_selected.connect(func(value): entry_index=value; editor._select(""); redraw())
	editor.properties.add_child(options)
	var arm := entry()
	editor._choice("Faixa",["auto","on","off"],["Faixa automática","Com faixa","Sem faixa"],arm.mode,func(value): change("mode",value))
	editor._number("Afastar faixa (m)",arm.offset,0,arm.max_offset,func(value): change("offset",value),.1)
	editor._number("Profundidade (m)",arm.depth,.5,5,func(value): change("depth",value),.1)
	var stop := CheckButton.new()
	stop.text = "Mostrar linha de parada"
	stop.button_pressed = arm.show_stop
	stop.toggled.connect(func(value): change("stop",value))
	editor.properties.add_child(stop)
	var hint := Label.new()
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.text = arm.reason if not str(arm.reason).is_empty() else "Arraste o marcador da entrada para afastar a faixa. A parada dos carros acompanha."
	editor.properties.add_child(hint)
	editor._button(editor.properties,"Restaurar esta entrada",restore)

func source_row(arm: Dictionary) -> Dictionary:
	return editor.canvas.objects.get("road/"+str(arm.road_id),editor.canvas.objects.get(arm.road_id,{}))

func change(field: String, value: Variant) -> void:
	var arm := entry()
	if arm.is_empty(): return
	var row := source_row(arm).duplicate(true)
	if row.is_empty(): return
	var entries: Dictionary = row.get("crossing_entries",{}).duplicate(true)
	var setting: Dictionary = entries.get(arm.key,{}).duplicate(true)
	setting[field] = value
	entries[arm.key] = setting
	row.crossing_entries = entries
	editor.region = "harbor"
	editor._commit(row)
	editor.canvas.selected_id = ""
	editor._select("")
	redraw()

func restore() -> void:
	var arm := entry()
	if arm.is_empty(): return
	var row := source_row(arm).duplicate(true)
	if not row.get("crossing_entries",{}).has(arm.key): return
	row.crossing_entries = row.crossing_entries.duplicate(true)
	row.crossing_entries.erase(arm.key)
	editor.region = "harbor"
	editor._commit(row)
	editor.canvas.selected_id = ""
	editor._select("")

func project(point: Vector2, view3d: bool) -> Vector2:
	if not view3d: return editor.canvas.screen(point)
	return editor.live_preview.camera.unproject_position(Vector3(point.x,.10,point.y))

func ground(at: Vector2, view3d: bool) -> Variant:
	if not view3d: return editor.canvas.world(at)
	var hit: Variant = editor.live_preview.edit_control.plane_point(at,.10)
	return null if hit == null else Vector2(hit.x,hit.z)

func input_event(event: InputEvent, view3d: bool) -> bool:
	if not enabled: return false
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		cancel(); return true
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if not event.pressed: finish(); return true
		cancel()
		var at: Vector2 = event.position
		var found := false
		var nearest := 15.0
		# Pick approach handles before junction centres.
		for junction in layouts:
			for i in junction.entries.size():
				var distance := project(junction.entries[i].position,view3d).distance_to(at)
				if distance < nearest:
					nearest=distance; selected=junction.id; entry_index=i; found=true
		if not found:
			for junction in layouts:
				var distance := project(junction.position,view3d).distance_to(at)
				if distance < nearest: nearest=distance; selected=junction.id; entry_index=0
		editor.canvas.selected_id = ""
		editor._select("")
		if found:
			var hit: Variant = ground(at,view3d)
			if hit != null and entry().fits:
				start=hit; original=entry().offset; proposed=original; dragging=true; drag_3d=view3d
		redraw()
		return true
	if event is InputEventMouseMotion and dragging:
		var hit: Variant = ground(event.position,drag_3d)
		if hit != null:
			proposed = clampf(original+(hit-start).dot(entry().direction),0,entry().max_offset)
			if event.shift_pressed: proposed=clampf(snappedf(proposed,.5),0,entry().max_offset)
		redraw()
		return true
	return false

func cancel() -> void:
	dragging = false
	redraw()

func finish() -> void:
	if not dragging: return
	dragging = false
	if not is_equal_approx(proposed,original): change("offset",proposed)
	redraw()

func redraw() -> void:
	if editor == null: return
	if is_instance_valid(editor.canvas): editor.canvas.queue_redraw()
	if is_instance_valid(editor.live_preview) and editor.live_preview.edit_control != null: editor.live_preview.edit_control.queue_redraw()

func draw_on(control: Control, view3d: bool) -> void:
	if not enabled: return
	for junction in layouts:
		var at := project(junction.position,view3d)
		if not Rect2(Vector2.ZERO,control.size).grow(100).has_point(at): continue
		control.draw_arc(at,9,0,TAU,24,Color("69d9d0"),2,true)
		if junction.id != selected: continue
		for i in junction.entries.size():
			var arm: Dictionary = junction.entries[i]
			var position: Vector2 = arm.position
			if dragging and i == entry_index: position += arm.direction*(proposed-original)
			var color := Color("ffd36c") if i == entry_index else Color("69d9d0")
			var normal: Vector2 = arm.direction.orthogonal()*arm.width*.5
			control.draw_line(project(position-normal,view3d),project(position+normal,view3d),color,3,true)
			var stop_position: Vector2 = position+arm.direction*(arm.depth*.5+1.0)
			control.draw_line(project(stop_position,view3d),project(stop_position+normal,view3d),Color("ff997c"),2,true)
			var handle := project(position,view3d)
			control.draw_circle(handle,7,color)
			control.draw_string(ThemeDB.fallback_font,handle+Vector2(10,-8),str(i+1),HORIZONTAL_ALIGNMENT_LEFT,-1,16,color)
