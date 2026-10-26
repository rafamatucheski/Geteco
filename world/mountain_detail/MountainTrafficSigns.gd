extends RefCounted
## Passive rural signs, derived from the resident road geometry. No frame work,
## lights, speed limits or changes to traffic priority. Front faces use local +Z.
const CONNECTION := preload("res://world/regions/WorldConnection3D.gd")
const JEEP := preload("res://world/mountain_jeep/MountainJeepCourse.gd")
const HEIGHT := 2.85
const CLEARANCE := 2.25
var records: Array[Dictionary] = []
var _region
var _lamps: Array[Vector3] = []
var _meshes: Dictionary = {}

func configure(region, lamps: Array[Vector3] = []) -> void:
	records.clear()
	_region = region
	_lamps = lamps
	for road: Dictionary in region.roads:
		if str(road.get("surface", "asphalt")) != "asphalt": continue
		if road.id == "mountain_turnaround": continue
		var curve := Curve3D.new()
		curve.bake_interval = 1.0
		for point: Vector3 in road.points: curve.add_point(point)
		var length := curve.get_baked_length()
		var half := float(road.width)*.5
		for sense: float in [1.0, -1.0]:
			var last_warning := -INF
			var last_chevron := -INF
			for travelled in range(24, int(length)-24, 8):
				var offset := float(travelled) if sense > 0 else length-float(travelled)
				var point := curve.sample_baked(offset)
				var incoming := curve.sample_baked(offset-12*sense).direction_to(point)
				var outgoing := point.direction_to(curve.sample_baked(offset+12*sense))
				var angle := incoming.signed_angle_to(outgoing,Vector3.UP)
				if absf(angle) < deg_to_rad(25): continue
				var right_turn := angle < 0
				if travelled-last_warning > 65:
					var warning_at := maxf(5, float(travelled)-20)
					var d := warning_at if sense > 0 else length-warning_at
					var forward := _direction(curve,d,sense)
					var right := Vector3(-forward.z,0,forward.x)
					if _add(curve.sample_baked(d)+right*(half+CLEARANCE),-forward,"curve_right" if right_turn else "curve_left",road.id):
						last_warning = travelled
				if travelled-last_chevron > 28:
					# The outside of a right bend lies to the driver's left.
					for shift: float in [-5, 3, 11]:
						var d := offset+shift*sense
						var forward := _direction(curve,d,sense)
						var right := Vector3(-forward.z,0,forward.x)
						_add(curve.sample_baked(d)+right*(-1 if right_turn else 1)*(half+CLEARANCE),-forward,"chevron_right" if right_turn else "chevron_left",road.id)
					last_chevron = travelled
			if road.id != "mountain_pass": continue
			# Functional destination boards belong to actual asphalt access roads.
			for branch: Dictionary in region.roads:
				var destination: String = {"mountain_track_5":"Vila", "mountain_village_return":"Vila", "mountain_track_4":"Summit"}.get(branch.id, "")
				if destination.is_empty(): continue
				var junction := curve.get_closest_offset(branch.points[0])
				var d := junction-22*sense
				if d < 5 or d > length-5: continue
				var forward := _direction(curve,d,sense)
				var right := Vector3(-forward.z,0,forward.x)
				var branch_direction: Vector3 = branch.points[0].direction_to(branch.points[1])
				var arrow := "  →" if branch_direction.dot(right)>0 else "  ←"
				_add(curve.sample_baked(d)+right*(half+CLEARANCE+.5),-forward,"destination",road.id,destination+arrow)

func _direction(curve: Curve3D, offset: float, sense: float) -> Vector3:
	var a := curve.sample_baked(clampf(offset-1*sense,0,curve.get_baked_length()))
	var b := curve.sample_baked(clampf(offset+1*sense,0,curve.get_baked_length()))
	return Vector3(b.x-a.x,0,b.z-a.z).normalized()

func _add(point: Vector3, front: Vector3, kind: String, road_id: String, text := "") -> bool:
	if point.x < CONNECTION.TUNNEL_END_X+4 and absf(point.z-CONNECTION.CENTER_Z)<16: return false
	if _region.route_geometry.contains(point,1.85): return false
	if JEEP.is_reserved(Vector2(point.x,point.z),.4): return false
	for entry: Dictionary in _region.entries:
		var at: Vector3 = entry.get("entry_position",entry.get("position",Vector3.INF))
		if Vector2(point.x,point.z).distance_to(Vector2(at.x,at.z))<6: return false
	for lamp in _lamps:
		if point.distance_to(lamp)<2.0: return false
	for record in records:
		if point.distance_to(record.position)<2.0: return false
	if _region.terrain != null: point.y = _region.terrain.surface_height_at(Vector2(point.x,point.z))
	var basis := Basis(Vector3(front.z,0,-front.x),Vector3.UP,front)
	records.append({"position":point,"basis":basis,"kind":kind,"road":road_id,"text":text})
	return true

func build(parent: Node3D) -> void:
	_prepare_meshes()
	var cells := {}
	for record in records:
		var key := Vector2i(floori(record.position.x/64),floori(record.position.z/64))
		if not cells.has(key): cells[key] = []
		cells[key].append(record)
	for key in cells:
		var owner := Node3D.new()
		owner.name = "MountainSigns_%d_%d"%[key.x,key.y]
		parent.add_child(owner)
		var rows: Array = cells[key]
		var posts: Array[Transform3D] = []
		var groups := {}
		var body := StaticBody3D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		owner.add_child(body)
		var post_shape := CylinderShape3D.new()
		post_shape.height = HEIGHT
		post_shape.radius = .045
		for row in rows:
			posts.append(Transform3D(row.basis,row.position+Vector3.UP*HEIGHT*.5))
			if not groups.has(row.kind): groups[row.kind] = []
			groups[row.kind].append(Transform3D(row.basis,row.position+Vector3.UP*HEIGHT))
			var collision := CollisionShape3D.new()
			collision.shape = post_shape
			collision.position = row.position+Vector3.UP*HEIGHT*.5
			body.add_child(collision)
			if row.kind == "destination":
				var label := Label3D.new()
				label.text = row.text
				label.font_size = 72
				label.pixel_size = .0065
				label.outline_size = 0
				label.no_depth_test = false
				label.shaded = true
				label.transform = Transform3D(row.basis,row.position+Vector3.UP*HEIGHT+row.basis.z*.035)
				label.visibility_range_end = 180
				owner.add_child(label)
		_batch(owner,"Posts",_meshes.post,posts)
		for kind in groups: _batch(owner,kind,_meshes[kind],groups[kind])

func _batch(parent: Node3D, title: String, mesh: Mesh, poses: Array) -> void:
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = mesh
	multi.instance_count = poses.size()
	for i in poses.size(): multi.set_instance_transform(i,poses[i])
	var visual := MultiMeshInstance3D.new()
	visual.name = title
	visual.multimesh = multi
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visual.visibility_range_end = 240
	visual.visibility_range_end_margin = 20
	parent.add_child(visual)

func _material(color: String) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(color)
	material.roughness = .5
	return material

func _prepare_meshes() -> void:
	if not _meshes.is_empty(): return
	var metal := _material("8b969c")
	metal.metallic = .65
	var post := CylinderMesh.new()
	post.height = HEIGHT
	post.top_radius = .035
	post.bottom_radius = .045
	post.radial_segments = 8
	post.rings = 1
	post.material = metal
	_meshes.post = post
	var black := _material("11151a")
	var amber := _material("ffc635")
	for kind in ["curve_left","curve_right","chevron_left","chevron_right","destination"]:
		var mesh := ArrayMesh.new()
		var warning: bool = kind.begins_with("curve")
		var outline := PackedVector2Array([Vector2(-.64,0),Vector2(0,.64),Vector2(.64,0),Vector2(0,-.64)]) if warning else PackedVector2Array([Vector2(-.4,-.5),Vector2(.4,-.5),Vector2(.4,.5),Vector2(-.4,.5)])
		if kind == "destination": outline = PackedVector2Array([Vector2(-1.25,-.36),Vector2(1.25,-.36),Vector2(1.25,.36),Vector2(-1.25,.36)])
		# Metal back and front paint are opaque surfaces; no alpha or viewport.
		_polygon(mesh,outline,-.025,metal,true)
		_polygon(mesh,outline,0,black if kind != "destination" else _material("e3e8dc"))
		var inset := outline.duplicate()
		for i in inset.size(): inset[i] *= .88 if warning else .90
		_polygon(mesh,inset,.008,amber if kind != "destination" else _material("175a40"))
		if kind == "destination": _meshes[kind] = mesh; continue
		var symbol: PackedVector2Array
		if warning:
			symbol = PackedVector2Array([Vector2(-.24,-.32),Vector2(-.09,-.32),Vector2(-.09,.06),Vector2(.11,.06),Vector2(.11,-.05),Vector2(.37,.14),Vector2(.11,.36),Vector2(.11,.21),Vector2(-.24,.21)])
		else:
			symbol = PackedVector2Array([Vector2(-.27,-.36),Vector2(-.06,-.36),Vector2(.27,0),Vector2(-.06,.36),Vector2(-.27,.36),Vector2(.06,0)])
		if kind.ends_with("left"):
			for i in symbol.size(): symbol[i].x *= -1
		_polygon(mesh,symbol,.016,black)
		_meshes[kind] = mesh

func _polygon(mesh: ArrayMesh, polygon: PackedVector2Array, depth: float, material: Material, back := false) -> void:
	var indices := Geometry2D.triangulate_polygon(polygon)
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	for triangle in range(0,indices.size(),3):
		var corners := [indices[triangle],indices[triangle+1],indices[triangle+2]]
		# Godot front faces use clockwise winding when viewed from the front.
		var a := polygon[corners[0]]
		var b := polygon[corners[1]]
		var c := polygon[corners[2]]
		if ((b-a).cross(c-a)>0) != back: corners.reverse()
		for index in corners:
			vertices.append(Vector3(polygon[index].x,polygon[index].y,depth))
			normals.append(Vector3.BACK if not back else Vector3.FORWARD)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	mesh.surface_set_material(mesh.get_surface_count()-1,material)
