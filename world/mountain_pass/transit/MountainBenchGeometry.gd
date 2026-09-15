extends RefCounted
## Geometry-derived blockers and ground anchors for the mountain's existing props.

static func install_prop(prop: Node2D, kind: String) -> void:
	if kind not in ["PatrolShelter3D", "TrailSignAndBench3D", "LumberjackCabin3D", "CoveredWoodpile3D"]:
		return
	for child in prop.get_children():
		if child is StaticBody2D:
			prop.remove_child(child)
			child.free()
	var meshes: Array[MeshInstance3D] = []
	_collect_meshes(prop.model, meshes)
	if kind == "PatrolShelter3D":
		_shelter(prop, meshes)
	elif kind == "TrailSignAndBench3D":
		var bench: Array[MeshInstance3D] = []
		var sign_nodes: Array[MeshInstance3D] = []
		for mesh in meshes:
			if mesh.position.x < 0.4 and mesh.position.y < 1.1:
				bench.append(mesh)
			else:
				sign_nodes.append(mesh)
		var body := _solid(prop, "TrailBenchGeodata", _points(prop, bench))
		_solid(prop, "TrailSignGeodata", _points(prop, sign_nodes))
		for side in [-1.0, 1.0]:
			var floor_point := Vector3(-0.35 + side * 7.0 / 18.0, 0, 0)
			seat(prop, prop.project(floor_point), prop.project(floor_point + Vector3.UP * 0.45), body, 0.45, "shelter", Vector2(0,28))
	else:
		# Foundations and doorsteps remain walkable; elevated geometry protects
		# the visible north roof and facades as well as the physical floor volume.
		var structural: Array[MeshInstance3D] = []
		for mesh in meshes:
			if mesh.position.y + mesh.mesh.get_aabb().size.y * 0.5 > 0.30:
				structural.append(mesh)
		_solid(prop, "BuildingGeodata", _points(prop, structural))
	prop.set_meta("geometry_contract", "projected_mesh_volume")

static func _shelter(prop: Node2D, meshes: Array[MeshInstance3D]) -> void:
	var rear: Array[MeshInstance3D] = []
	var left: Array[MeshInstance3D] = []
	var right: Array[MeshInstance3D] = []
	var front_left: Array[MeshInstance3D] = []
	var front_right: Array[MeshInstance3D] = []
	var bench: Array[MeshInstance3D] = []
	for mesh in meshes:
		var top := mesh.position.y + mesh.mesh.get_aabb().size.y * 0.5
		if top < 0.30:
			continue
		if mesh.position.z < -0.58 and mesh.position.z > -1.0 and top < 0.95:
			bench.append(mesh)
		elif mesh.position.y > 2.4 or mesh.position.z <= -1.0:
			rear.append(mesh)
		elif mesh.position.z > 0.9 and mesh.position.x < -0.4:
			front_left.append(mesh)
		elif mesh.position.z > 0.9 and mesh.position.x > 0.4:
			front_right.append(mesh)
		elif mesh.position.x <= -1.25:
			left.append(mesh)
		elif mesh.position.x >= 1.0:
			right.append(mesh)
	# The roof silhouette extends north of the floor. Its projected northern
	# volume is solid, but the actual open room and its door stay walkable.
	var rear_hull := Geometry2D.convex_hull(_points(prop, rear))
	var room_back: float = prop.project(Vector3(0,0,-1.0)).y
	var northern_half := PackedVector2Array([Vector2(-200,-200),Vector2(200,-200),Vector2(200,room_back),Vector2(-200,room_back)])
	for polygon in Geometry2D.intersect_polygons(rear_hull, northern_half):
		_solid(prop, "ShelterRearGeodata", polygon)
	_solid(prop, "ShelterLeftGeodata", _points(prop,left))
	_solid(prop, "ShelterRightGeodata", _points(prop,right))
	# Front posts stand ahead of the room: keep their floor obstruction while
	# allowing occupants behind them to use the open shelter's interior.
	var front_y: float = prop.project(Vector3(0,0,0.91)).y
	var front_half := PackedVector2Array([Vector2(-200,front_y),Vector2(200,front_y),Vector2(200,200),Vector2(-200,200)])
	for pair in [["ShelterDoorLeftGeodata",front_left],["ShelterDoorRightGeodata",front_right]]:
		for polygon in Geometry2D.intersect_polygons(Geometry2D.convex_hull(_points(prop,pair[1])),front_half):
			_solid(prop,pair[0],polygon)
	var bench_body := _solid(prop, "ShelterBenchGeodata", _points(prop,bench))
	for side in [-1.0,1.0]:
		var anchor_3d := Vector3(side*8.0/18.0,0,-0.40)
		var hip_3d := Vector3(anchor_3d.x,0.45,-0.80)
		var anchor: Vector2 = prop.project(anchor_3d)
		var approach := Vector2(-anchor.x,34)
		var marker := seat(prop,anchor,prop.project(hip_3d),bench_body,0.45,"shelter",approach)
		marker.set_meta("route_hint",[approach,Vector2(-anchor.x,8),Vector2.ZERO])
		marker.set_meta("occlusion_z_index",prop.z_index-1)

static func seat(parent: Node2D, floor_point: Vector2, projected_seat: Vector2, body: StaticBody2D, height: float, scope: String, approach := Vector2(0,28)) -> Marker2D:
	var marker := Marker2D.new()
	marker.name = "BenchSeat%d" % parent.get_child_count()
	marker.position = floor_point
	marker.add_to_group("mountain_bench_seat")
	marker.set_meta("approach_offset", approach)
	marker.set_meta("facing",Vector2.DOWN)
	marker.set_meta("seat_height",height)
	marker.set_meta("seat_height_pixels",18.0*height)
	marker.set_meta("visual_seat_offset",projected_seat-floor_point)
	marker.set_meta("bench_body",body)
	marker.set_meta("scope",scope)
	marker.set_meta("bench_scope",scope)
	marker.set_meta("bench_group",scope)
	parent.add_child(marker)
	return marker

static func _solid(prop: Node2D, label: String, points: PackedVector2Array) -> StaticBody2D:
	if points.size() < 3:
		return null
	var body := StaticBody2D.new()
	body.name = label
	body.collision_layer = 1
	body.collision_mask = 0
	body.add_to_group("mountain_geodata")
	body.set_meta("geometry_contract","projected_mesh_volume")
	var shape := CollisionPolygon2D.new()
	shape.polygon = Geometry2D.convex_hull(points)
	body.add_child(shape)
	prop.add_child(body)
	return body

static func _collect_meshes(node: Node, target: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D and node.mesh != null:
		target.append(node)
	for child in node.get_children():
		_collect_meshes(child,target)

static func _points(prop: Node2D, meshes: Array[MeshInstance3D]) -> PackedVector2Array:
	var points := PackedVector2Array()
	for mesh in meshes:
		var bounds: AABB = mesh.mesh.get_aabb()
		var transform: Transform3D = prop.model.global_transform.affine_inverse() * mesh.global_transform
		for index in 8:
			points.append(prop.project(transform * bounds.get_endpoint(index)))
	return points
