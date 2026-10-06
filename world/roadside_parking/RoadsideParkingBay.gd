extends RefCounted
## A pull-off is one static top mesh and one collider. No lights or processing.
const LAYOUT := preload("res://world/roadside_parking/RoadsideParkingLayout.gd")
const ROAD := preload("res://world/urban_detail/HarborRoadGeometry3D.gd")
const COLLISION_Y := 0.0
const VISUAL_Y := .030
static var _materials: Dictionary = {}

static func build(parent: Node3D, site: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = "ParkingBay_"+str(site.id)
	root.position = site.edge
	root.set_meta("parking_site_id",site.id)
	parent.add_child(root)
	var outline := _outline(site)
	var core := outline.duplicate()
	var mouth_count := outline.size()-4
	var rim_width := .42 if str(site.region)=="mountain" else .14
	# Finish only the outer perimeter; the whole mouth remains open asphalt.
	for index in range(mouth_count,outline.size()):
		var previous := outline[index-1]
		var next := outline[(index+1)%outline.size()]
		var incoming := (outline[index]-previous).normalized()
		var outgoing := (next-outline[index]).normalized()
		var first_normal := Vector2(-incoming.y,incoming.x)
		var second_normal := Vector2(-outgoing.y,outgoing.x)
		var inward := (first_normal+second_normal).normalized()
		core[index] += inward*rim_width/maxf(.3,inward.dot(first_normal))
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var faces := PackedVector3Array()
	var indices := Geometry2D.triangulate_polygon(core)
	for index in range(0,indices.size(),3):
		var triangle: Array[Vector3] = []
		for corner in 3:
			var p := core[indices[index+corner]]
			triangle.append(site.forward*p.x+site.outward*p.y+Vector3.UP*VISUAL_Y)
		if (triangle[1]-triangle[0]).cross(triangle[2]-triangle[0]).y>0: triangle.reverse()
		for vertex in triangle:
			tool.set_normal(Vector3.UP)
			# Match the road's world-space UV phase and four-metre texture repeat.
			tool.set_uv(Vector2(vertex.x+site.edge.x,vertex.z+site.edge.z)/4.0)
			tool.add_vertex(vertex)
	# The visual paving sits millimetres above the road's .026 overlay. Physical
	# support stays on the same y=0 plane as its terrain/road collider: a raised
	# single-sided triangle edge otherwise blocks the native chassis like a wall.
	indices = Geometry2D.triangulate_polygon(outline)
	for index in range(0,indices.size(),3):
		var triangle: Array[Vector3] = []
		for corner in 3:
			var p := outline[indices[index+corner]]
			triangle.append(site.forward*p.x+site.outward*p.y+Vector3.UP*COLLISION_Y)
		if (triangle[1]-triangle[0]).cross(triangle[2]-triangle[0]).y>0: triangle.reverse()
		faces.append_array(triangle)
	var mesh := MeshInstance3D.new()
	mesh.name = "PullOffSurface"
	mesh.mesh = tool.commit()
	mesh.material_override = _material(str(site.surface))
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mesh)
	_perimeter(root,site,outline,core,mouth_count)
	var body := StaticBody3D.new()
	body.name = "PullOffFloor"
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	var collider := CollisionShape3D.new()
	collider.shape = shape
	body.add_child(collider)
	root.add_child(body)
	# Fine white end marks communicate real 1/2-car bays without explanatory text.
	if site.surface == "asphalt":
		for index in range(site.slots.size()+1):
			var along := (float(index)-float(site.slots.size())*.5)*LAYOUT.SLOT_LENGTH
			_mark(root,site.forward*along+site.outward*2.25+Vector3.UP*(VISUAL_Y+.006),Vector3(2.65,.008,.085),site.yaw)
	return root

static func _outline(site: Dictionary) -> PackedVector2Array:
	var half: float = site.half_length
	var result := PackedVector2Array()
	var steps := ceili(half*2.0/1.5)
	var points: PackedVector3Array = site.get("road_points",PackedVector3Array())
	for step in range(steps+1):
		var along := lerpf(-half,half,float(step)/steps)
		var wanted: Vector3 = site.edge+site.forward*along
		var edge: Vector3 = wanted-site.outward*.18
		var best := INF
		for index in range(points.size()-1):
			var delta := points[index+1]-points[index]
			if delta.length_squared()<.001: continue
			var nearest := Geometry3D.get_closest_point_to_segment(wanted,points[index],points[index+1])
			var distance := wanted.distance_squared_to(nearest)
			if distance>=best: continue
			best = distance
			var outward := delta.normalized().cross(Vector3.UP)
			if outward.dot(site.outward)<0: outward = -outward
			edge = nearest+outward*(float(site.road_width)*.5-.18)
		var offset: Vector3 = edge-site.edge
		result.append(Vector2(offset.dot(site.forward),offset.dot(site.outward)))
	result.append_array(PackedVector2Array([Vector2(half-2.0,LAYOUT.DEPTH-.6),Vector2(half-2.7,LAYOUT.DEPTH),
		Vector2(-half+2.7,LAYOUT.DEPTH),Vector2(-half+2.0,LAYOUT.DEPTH-.6)]))
	return result

static func _perimeter(parent: Node3D,site: Dictionary,outer: PackedVector2Array,inner: PackedVector2Array,mouth_count: int) -> void:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rural := str(site.region)=="mountain"
	for index in range(mouth_count-1,outer.size()):
		var next := (index+1)%outer.size()
		var quad := [outer[index],outer[next],inner[next],inner[index]]
		for corners in [[0,1,2],[0,2,3]]:
			var triangle: Array[Vector3] = []
			var colors: Array[Color] = []
			for corner: int in corners:
				var p: Vector2 = quad[corner]
				triangle.append(site.forward*p.x+site.outward*p.y+Vector3.UP*VISUAL_Y)
				colors.append(Color(1,1,1,0 if rural and corner<2 else 1))
			if (triangle[1]-triangle[0]).cross(triangle[2]-triangle[0]).length_squared()<.00000001: continue
			if (triangle[1]-triangle[0]).cross(triangle[2]-triangle[0]).y>0:
				triangle.reverse()
				colors.reverse()
			for corner in 3:
				var p := triangle[corner]
				tool.set_normal(Vector3.UP)
				tool.set_color(colors[corner])
				tool.set_uv(Vector2(p.x+site.edge.x,p.z+site.edge.z)/4.0)
				tool.add_vertex(p)
	var mesh := MeshInstance3D.new()
	mesh.name = "PullOffShoulder" if rural else "PullOffEdge"
	mesh.mesh = tool.commit()
	mesh.material_override = _edge_material(rural)
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mesh)

static func _edge_material(rural: bool) -> Material:
	var key := "soft_edge" if rural else "urban_edge"
	if _materials.has(key): return _materials[key]
	var material: StandardMaterial3D
	if rural:
		material = _material("asphalt").duplicate()
		material.vertex_color_use_as_albedo = true
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	else:
		material = ROAD.new()._material(ROAD.SIDEWALK_COLOR)
	_materials[key] = material
	return material

static func _mark(parent: Node3D, point: Vector3, size: Vector3, yaw: float) -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.position = point
	mesh.rotation.y = yaw
	mesh.material_override = _material("paint")
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mesh)

static func _material(kind: String) -> Material:
	if _materials.has(kind): return _materials[kind]
	if kind!="paint":
		if not _materials.has("road"):
			_materials["road"] = ROAD.new()._material(ROAD.ROAD_COLOR)
		return _materials["road"]
	var material := StandardMaterial3D.new()
	material.roughness = .96
	material.albedo_color = Color("eee5c9")
	_materials[kind] = material
	return material
