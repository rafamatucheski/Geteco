@tool
extends Control
## Editor-only picking and speculative transforms; a gesture commits once.
const DATA := preload("res://world/editing/WorldEditData.gd")
var editor
var preview
var meshes: Array = []
var groups := {}
var mode := 0
var dragging := false
var start_mouse := Vector2.ZERO
var start_world := Vector3.ZERO
var original := {}
var candidate := {}
var transforms := {}
var axis := ""
var synchronizing := false

func setup(owner_editor, owner_preview) -> void:
	editor = owner_editor
	preview = owner_preview
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	preview.surface.focus_mode = Control.FOCUS_ALL
	preview.surface.set_drag_forwarding(Callable(),can_drop,drop)

func rebuild() -> void:
	cancel()
	meshes.clear()
	groups.clear()
	if is_instance_valid(preview.geometry): index_nodes(preview.geometry,"")
	queue_redraw()

func set_mode(value: int) -> void:
	cancel()
	mode = value
	editor.status.text = ["Arraste o objeto ou as setas X/Z. Shift: passos de 0,5 m.","Arraste o objeto ou o anel para girar. Shift: passos de 15°.","Arraste para cima/direita para aumentar; baixo/esquerda para diminuir."][mode]
	queue_redraw()

func index_nodes(node: Node, inherited: String) -> void:
	var id := str(node.get_meta("editor_id",inherited))
	if node.has_meta("editor_id") and editor.canvas.objects.has(id):
		if not groups.has(id): groups[id] = []
		groups[id].append(node)
	if node is MeshInstance3D and node.mesh != null and node.is_visible_in_tree():
		meshes.append({"node":node,"id":id,"bounds":node.mesh.get_aabb()})
	for child in node.get_children(): index_nodes(child,id)

func pick(at: Vector2) -> String:
	var ray: Vector3 = preview.camera.project_ray_origin(at)
	var end: Vector3 = ray+preview.camera.project_ray_normal(at)*2000
	var nearest := INF
	var found := ""
	for item in meshes:
		var node: Node3D = item.node
		if not is_instance_valid(node) or not node.is_visible_in_tree(): continue
		var inverse := node.global_transform.affine_inverse()
		var hit: Variant = (item.bounds as AABB).intersects_segment(inverse*ray,inverse*end)
		if hit == null: continue
		var distance: float = ray.distance_squared_to(node.global_transform*(hit as Vector3))
		if distance < nearest:
			nearest = distance
			found = item.id if editor.canvas.objects.has(item.id) else ""
	return found

func plane_point(at: Vector2, height: float) -> Variant:
	return Plane(Vector3.UP,height).intersects_ray(preview.camera.project_ray_origin(at),preview.camera.project_ray_normal(at))

func select_id(id: String) -> void:
	synchronizing = true
	editor._select(id)
	synchronizing = false
	editor.canvas.queue_redraw()
	queue_redraw()

func input_event(event: InputEvent) -> bool:
	if editor.junction_editor.input_event(event,true): return true
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			cancel(); editor.canvas.armed = ""; editor.placement_template = {}; return true
		if dragging: return true
		if event.keycode == KEY_DELETE: editor._delete(); return true
		if event.ctrl_pressed and event.keycode == KEY_C: editor._copy(); return true
		if event.ctrl_pressed and event.keycode == KEY_V: editor._paste(); return true
		if event.ctrl_pressed and event.keycode == KEY_Z:
			if event.shift_pressed: editor.redo()
			else: editor.undo()
			return true
		if event.ctrl_pressed and event.keycode == KEY_Y: editor.redo(); return true
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		preview.surface.grab_focus()
		if event.pressed:
			if not editor.canvas.armed.is_empty():
				var point: Variant = plane_point(event.position,preview.focus.y)
				if point != null: editor._place(editor.canvas.armed,Vector2(point.x,point.z))
				return true
			axis = handle_at(event.position)
			var id: String = editor.canvas.selected_id if not axis.is_empty() else pick(event.position)
			select_id(id)
			begin(event.position)
		else: finish()
		return true
	if event is InputEventMouseMotion and dragging:
		update_drag(event.position,event.shift_pressed)
		return true
	return false

func _input(event: InputEvent) -> void:
	if editor != null and editor.junction_editor.dragging and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		editor.junction_editor.finish()
	# A release outside the viewport must not leave an unfinished gesture.
	if dragging and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		if not preview.surface.get_global_rect().has_point(preview.surface.get_global_mouse_position()): finish()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT and dragging: cancel()

func begin(at: Vector2) -> void:
	var row: Dictionary = editor.canvas.objects.get(editor.canvas.selected_id,{})
	if row.is_empty() or row.get("locked",false) or row.type in ["context","road"] or not groups.has(row.id): return
	if preview.desired != preview.submitted or preview.applied_revision != preview.revision:
		editor.status.text = "Aguarde a atualização 3D para arrastar."
		return
	original = row.duplicate(true)
	candidate = original.duplicate(true)
	var point: Variant = plane_point(at,preview.focus.y)
	if point == null: return
	start_world = point
	start_mouse = at
	transforms.clear()
	for node in groups[row.id]: transforms[node] = node.global_transform
	dragging = true

func update_drag(at: Vector2, snap := false) -> void:
	if not dragging: return
	var next := original.duplicate(true)
	var delta := at-start_mouse
	if mode == 0:
		var point: Variant = plane_point(at,preview.focus.y)
		if point == null: return
		var offset: Vector3 = point-start_world
		if axis == "X": offset.z = 0
		if axis == "Z": offset.x = 0
		next.position = [float(original.position[0])+offset.x,float(original.position[1])+offset.z]
		if snap:
			for i in 2: next.position[i] = snappedf(next.position[i],.5)
	elif mode == 1:
		next.rotation = float(original.get("rotation",0))+delta.x*.5
		if snap: next.rotation = snappedf(next.rotation,15)
	else:
		var factor := clampf(exp((delta.x-delta.y)*.006),.1,4)
		if next.type == "piece":
			var stretch: Array = original.get("stretch",[1.0,1.0])
			next.stretch = [clampf(stretch[0]*factor,.1,4),clampf(stretch[1]*factor,.1,4)]
			if next.has("outline"):
				for p in next.outline: p[0] *= next.stretch[0]/stretch[0]; p[1] *= next.stretch[1]/stretch[1]
		elif next.has("scale"): next.scale = clampf(float(original.scale)*factor,.25,3)
		elif next.has("size"):
			for i in 2: next.size[i] = float(original.size[i])*factor
			if next.has("height"): next.height = float(original.height)*factor
			if next.has("outline"):
				for p in next.outline: p[0] *= factor; p[1] *= factor
		elif next.type == "light": next.height = clampf(float(original.height)*factor,1,12)
	if not DATA.validate_entity(next).is_empty(): return
	candidate = next
	apply_visual()
	preview._render_once()
	queue_redraw()

func apply_visual() -> void:
	var ratio := Vector3.ONE
	if mode == 2:
		if original.type == "piece":
			var base: Array = original.get("stretch",[1,1])
			ratio = Vector3(candidate.stretch[0]/base[0],1,candidate.stretch[1]/base[1])
		elif original.has("scale"): ratio = Vector3.ONE*float(candidate.scale)/float(original.scale)
		elif original.has("size"):
			ratio = Vector3(candidate.size[0]/original.size[0],float(candidate.get("height",1))/float(original.get("height",1)),candidate.size[1]/original.size[1])
		elif original.type == "light": ratio.y = candidate.height/original.height
	var pivot := Vector3(original.position[0],preview.focus.y,original.position[1])
	if not transforms.is_empty(): pivot.y = (transforms.values()[0] as Transform3D).origin.y
	var basis := Basis(Vector3.UP,deg_to_rad(float(candidate.get("rotation",0))-float(original.get("rotation",0))))
	var orientation := Basis(Vector3.UP,deg_to_rad(float(original.get("rotation",0))))
	basis = basis*orientation*Basis.from_scale(ratio)*orientation.inverse()
	var move := Vector3(candidate.position[0]-original.position[0],0,candidate.position[1]-original.position[1])
	var change := Transform3D(basis,pivot+move-basis*pivot)
	for node in transforms:
		if is_instance_valid(node): node.global_transform = change*transforms[node]

func cancel() -> void:
	if editor != null: editor.junction_editor.cancel()
	for node in transforms:
		if is_instance_valid(node): node.global_transform = transforms[node]
	transforms.clear()
	dragging = false
	queue_redraw()
	if preview != null: preview._render_once()

func finish() -> void:
	if not dragging: return
	var row := candidate.duplicate(true)
	var changed := row != original
	cancel()
	if changed:
		synchronizing = true
		editor._commit(row)
		synchronizing = false
		# Validation may reject the gesture; only display the accepted result.
		if editor.document.regions.get(editor.region,{}).has(row.id):
			var accepted: Dictionary = editor.document.regions[editor.region][row.id]
			var matches := true
			var fields := ["position","rotation","stretch","outline"] if row.type == "piece" else ["position","rotation","size","height","scale","outline"]
			for key in fields:
				if accepted.get(key) != row.get(key): matches = false
			if matches:
				for node in groups.get(row.id,[]): transforms[node] = node.global_transform
				apply_visual()
				transforms.clear()
		preview.request(editor.document,Vector2(preview.focus.x,preview.focus.z),editor.region)
	preview._render_once()
	editor._apply_layout()

func handles() -> Dictionary:
	var row: Dictionary = editor.canvas.objects.get(editor.canvas.selected_id,{})
	if row.is_empty() or not row.has("position") or row.get("locked",false): return {}
	if dragging: row = candidate
	var point := Vector3(row.position[0],preview.focus.y+.15,row.position[1])
	var length: float = preview.view_size*.1
	return {"O":preview.camera.unproject_position(point),"X":preview.camera.unproject_position(point+Vector3.RIGHT*length),"Z":preview.camera.unproject_position(point+Vector3.BACK*length)}

func handle_at(at: Vector2) -> String:
	var points := handles()
	if points.is_empty(): return ""
	if mode == 1: return "R" if absf(at.distance_to(points.O)-36)<9 else ""
	if mode == 2: return "S" if at.distance_to(points.O+Vector2(45,-45))<12 else ""
	for key in ["X","Z"]:
		if points.has(key) and Geometry2D.get_closest_point_to_segment(at,points.O,points[key]).distance_to(at)<9: return key
	return ""

func _draw() -> void:
	if preview == null or editor == null: return
	if editor.junction_editor.enabled:
		editor.junction_editor.draw_on(self,true)
		return
	var id: String = editor.canvas.selected_id
	var envelope := AABB()
	var found := false
	for item in meshes:
		if item.id != id or id.is_empty() or not is_instance_valid(item.node): continue
		var bounds: AABB = item.bounds
		var world_bounds: AABB = item.node.global_transform*bounds
		envelope = envelope.merge(world_bounds) if found else world_bounds
		found = true
	if found:
		var corners: Array[Vector2] = []
		for i in 8: corners.append(preview.camera.unproject_position(envelope.get_endpoint(i)))
		for edge in [[0,1],[0,2],[0,4],[1,3],[1,5],[2,3],[2,6],[3,7],[4,5],[4,6],[5,7],[6,7]]:
			draw_line(corners[edge[0]],corners[edge[1]],Color(1,.8,.2,.65),1,true)
	var points := handles()
	if not points.is_empty():
		if mode == 0:
			for key in ["X","Z"]:
				var color := Color("ff7065") if key=="X" else Color("65baff")
				draw_line(points.O,points[key],color,3,true)
				draw_circle(points[key],6,color)
				draw_string(ThemeDB.fallback_font,points[key]+Vector2(8,0),key,HORIZONTAL_ALIGNMENT_LEFT,-1,16,color)
		elif mode == 1:
			draw_arc(points.O,36,0,TAU,48,Color("74d79a"),3,true)
		else:
			var end: Vector2 = points.O+Vector2(45,-45)
			draw_line(points.O,end,Color("ffcf65"),2,true)
			draw_rect(Rect2(end-Vector2(6,6),Vector2(12,12)),Color("ffcf65"))

func can_drop(_at: Vector2, data: Variant) -> bool:
	return data is Dictionary and data.get("geteco_asset",false) and data.get("item",{}).get("action","") != "select"

func drop(at: Vector2, data: Variant) -> void:
	if not can_drop(at,data): return
	var point: Variant = plane_point(at,preview.focus.y)
	if point == null: return
	editor.placement_template = data.item.row.duplicate(true)
	editor._place(data.item.row.type,Vector2(point.x,point.z))
