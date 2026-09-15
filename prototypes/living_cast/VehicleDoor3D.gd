extends Node3D
## Splits the authored body/glazing surfaces into a real hinged door. The
## remaining body stays on the car; the cut surfaces share its paint material.
var door_side := -1.0
var hinge: Node3D
var animation: Tween
var moving := false
var extracted_triangles := 0
var cabin_ceiling := 1.25
var entry_center_z := 0.0

func configure(model: Node3D, side_sign: float = -1.0) -> void:
	door_side = side_sign
	if model.get("vehicle_id") == "port_forklift":
		# Open access beside the seat: no body panel is a door on this machine.
		hinge = Node3D.new()
		add_child(hinge)
		hinge.position = Vector3(side_sign * 0.55, 0.65, 0.1)
		entry_center_z = 0.45
		cabin_ceiling = 1.95
		return
	var sources: Array[MeshInstance3D] = []
	var bounds := AABB()
	var first := true
	var glazing: Array = []
	for key in model.materials:
		if "glass" in String(key): glazing.append(model.materials[key])
	for node in model.get_children():
		if not node is MeshInstance3D or node.mesh == null: continue
		var material: Material = node.material_override
		if material != model.paint and material not in glazing: continue
		sources.append(node)
		var box: AABB = node.transform * node.mesh.get_aabb()
		bounds = box if first else bounds.merge(box)
		first = false
	if sources.is_empty(): return
	var length := bounds.size.z
	var front := bounds.position.z + length * 0.29
	var rear := front + minf(1.25, length * 0.29)
	var bottom := maxf(0.40, bounds.position.y)
	var top := bounds.end.y - 0.04
	# Commercial cabs sit farther forward than passenger car front seats.
	var script_path: String = model.get_script().resource_path
	if "Van" in script_path or "Box" in script_path or "Pumper" in script_path or "Tow" in script_path:
		front = bounds.position.z + length * 0.13
		rear = front + 1.15
	# Side glazing locates the cabin independently of cargo, hood and spoilers.
	# Using total body length cut roof/cargo surfaces out as commercial doors.
	var window := _side_window_bounds(sources, glazing, side_sign, bounds.size.x)
	if window.size.length_squared() > 0.01:
		front = window.position.z - 0.05
		rear = minf(window.end.z + 0.05, front + 1.30)
		top = window.end.y + 0.035
		cabin_ceiling = window.end.y - 0.015
	else:
		cabin_ceiling = top - 0.04
	entry_center_z = lerpf(front, rear, 0.62)
	var side := bounds.position.x if door_side < 0 else bounds.end.x
	var cut_width := absf(side)*0.42+0.08
	var cut_x := side-0.08 if door_side < 0 else side+0.08-cut_width
	var cut := AABB(Vector3(cut_x,bottom,front),Vector3(cut_width,top-bottom,rear-front))
	hinge = Node3D.new()
	hinge.name = "DriverDoorHinge" if door_side < 0 else "PassengerDoorHinge"
	hinge.position = Vector3(side,bottom,front)
	add_child(hinge)
	# Authored cab livery follows the moving door without changing cabin bounds.
	for node in model.get_children():
		if not node.get_meta("door_trim",false): continue
		if node is MeshInstance3D and node.mesh != null and not sources.has(node):
			if cut.intersects(node.transform*node.mesh.get_aabb()): sources.append(node)
		elif node is Label3D and cut.has_point(node.position):
			node.reparent(hinge,true)
	for source in sources:
		_split(source, cut, model)
	visible = extracted_triangles > 0

func _side_window_bounds(sources: Array[MeshInstance3D], glazing: Array, side_sign: float, width: float) -> AABB:
	var result := AABB()
	var found := false
	for source in sources:
		if source.material_override not in glazing: continue
		var arrays := source.mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		var count := indices.size() if not indices.is_empty() else vertices.size()
		for offset in range(0, count, 3):
			var triangle: Array[Vector3] = []
			for j in 3:
				triangle.append(source.transform * vertices[indices[offset+j] if not indices.is_empty() else offset+j])
			var normal := (triangle[1]-triangle[0]).cross(triangle[2]-triangle[0]).normalized()
			var center := (triangle[0]+triangle[1]+triangle[2])/3.0
			if absf(normal.x) < 0.65 or center.x * side_sign < width * 0.25: continue
			for point in triangle:
				if not found:
					result = AABB(point, Vector3.ZERO)
					found = true
				else:
					result = result.expand(point)
	return result

func _split(source: MeshInstance3D, cut: AABB, model: Node3D) -> void:
	var arrays := source.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV] if arrays[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
	var remaining: Array = []
	var door: Array = []
	var count := indices.size() if not indices.is_empty() else vertices.size()
	for offset in range(0,count,3):
		var polygon: Array = []
		for j in 3:
			var index := indices[offset+j] if not indices.is_empty() else offset+j
			polygon.append({"p": source.transform * vertices[index], "n": (source.basis.inverse().transposed() * normals[index]).normalized(), "uv": uvs[index] if not uvs.is_empty() else Vector2.ZERO})
		for plane in [Vector4(1,0,0,cut.position.x),Vector4(-1,0,0,-cut.end.x),Vector4(0,1,0,cut.position.y),Vector4(0,-1,0,-cut.end.y),Vector4(0,0,1,cut.position.z),Vector4(0,0,-1,-cut.end.z)]:
			if polygon.is_empty(): break
			var pieces := _clip(polygon, plane)
			_fan(pieces[1], remaining)
			polygon = pieces[0]
		_fan(polygon, door)
	if door.is_empty(): return
	extracted_triangles += door.size()/3
	if remaining.is_empty():
		source.hide()
	else:
		source.mesh = _mesh(remaining, Vector3.ZERO)
		source.transform = Transform3D.IDENTITY
		if "originals" in model and model.originals.has(source):
			model.originals[source] = source.mesh
			# The clipped surface has a different vertex count/order. A cached
			# pre-door deformation array must never be applied to this topology.
			if "damaged_vertices" in model: model.damaged_vertices.erase(source)
	var panel := MeshInstance3D.new()
	panel.name = "AuthoredDoorSurface"
	panel.mesh = _mesh(door, hinge.position)
	panel.material_override = source.material_override
	hinge.add_child(panel)

func _clip(polygon: Array, plane: Vector4) -> Array:
	var inside: Array = []
	var outside: Array = []
	var normal := Vector3(plane.x,plane.y,plane.z)
	for i in polygon.size():
		var a: Dictionary = polygon[i]
		var b: Dictionary = polygon[(i+1)%polygon.size()]
		var da := normal.dot(a.p)-plane.w
		var db := normal.dot(b.p)-plane.w
		if da >= 0: inside.append(a)
		else: outside.append(a)
		if (da >= 0) != (db >= 0):
			var t := da/(da-db)
			var cross := {"p": (a.p as Vector3).lerp(b.p,t),"n": (a.n as Vector3).lerp(b.n,t).normalized(),"uv": (a.uv as Vector2).lerp(b.uv,t)}
			inside.append(cross)
			outside.append(cross)
	return [inside,outside]

func _fan(polygon: Array, result: Array) -> void:
	for i in range(1,polygon.size()-1):
		result.append_array([polygon[0],polygon[i],polygon[i+1]])

func _mesh(vertices: Array, origin: Vector3) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for vertex in vertices:
		surface.set_normal(vertex.n)
		surface.set_uv(vertex.uv)
		surface.add_vertex(vertex.p-origin)
	return surface.commit()

func play(hold_seconds: float = 0.4) -> void:
	if hinge == null or extracted_triangles == 0: return
	if animation: animation.kill()
	moving = true
	animation = create_tween().set_trans(Tween.TRANS_QUAD)
	animation.tween_property(hinge,"rotation:y",deg_to_rad(65)*door_side,0.25).set_ease(Tween.EASE_OUT)
	animation.tween_interval(hold_seconds)
	animation.tween_property(hinge,"rotation:y",0.0,0.25).set_ease(Tween.EASE_IN)
	animation.tween_callback(func(): moving = false)

func _process(_delta: float) -> void:
	if moving:
		var viewport := get_viewport() as SubViewport
		if viewport: viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
