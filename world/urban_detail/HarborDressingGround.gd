extends RefCounted
## Authored district ground is composed once, as adjacent surfaces, never stacked boxes.
const MESH_ARRAYS := preload("res://world/chunk_bake/MeshArrayCache.gd")
const CUT := preload("res://world/urban_detail/GroundCut.gd")

static func footprints(zone: String, origin: Vector2) -> Array[PackedVector2Array]:
	var rects: Array[Rect2] = []
	match zone:
		"cobra":
			rects.assign([Rect2(-58.75,-46.25,110,90.625),Rect2(-74.375,-7.5,58.75,15),Rect2(-60.625,-8.625,1.875,17.25)])
		"salvage":
			rects.assign([Rect2(-38.75,-34.375,79.375,70),Rect2(-34.375,28.125,6.25,15.625)])
		"cemetery":
			var outer := Rect2(-30.9375,-28.125,61.875,56.25)
			var inner := Rect2(-24.375,-21.875,48.75,43.75)
			rects.assign([Rect2(outer.position,Vector2(outer.size.x,6.25)),Rect2(outer.position.x,inner.end.y,outer.size.x,6.25),Rect2(outer.position.x,inner.position.y,6.5625,inner.size.y),Rect2(inner.end.x,inner.position.y,6.5625,inner.size.y)])
	var result: Array[PackedVector2Array] = []
	for rect in rects:
		result.append(CUT.rect_polygon(Rect2(rect.position+origin,rect.size)))
	return result

static func compose(parent: Node3D, zone: String) -> void:
	var old_fill := parent.get_node_or_null("ReservedGroundInfill")
	if old_fill != null: old_fill.free()
	var entries: Array[Dictionary] = []
	for node in parent.find_children("*","MeshInstance3D",true,false):
		if node.has_meta("harbor_ground_source_mesh") and (node.mesh == null or (node.has_meta("harbor_ground_composed_mesh") and node.mesh == node.get_meta("harbor_ground_composed_mesh"))):
			node.mesh = node.get_meta("harbor_ground_source_mesh")
		if node.mesh == null: continue
		var label := str(node.get_meta("harbor_ground_label",node.name))
		if not _is_ground(label): continue
		node.set_meta("harbor_ground_source_mesh",node.mesh)
		var points := PackedVector2Array()
		var faces := _render_faces(node.mesh)
		var top := -INF
		for point in faces: top = maxf(top,(node.global_transform*point).y)
		var polygons: Array[PackedVector2Array] = []
		for i in range(0,faces.size(),3):
			var a: Vector3 = node.global_transform*faces[i]
			var b: Vector3 = node.global_transform*faces[i+1]
			var c: Vector3 = node.global_transform*faces[i+2]
			if minf(a.y,minf(b.y,c.y)) < top-.0001: continue
			var triangle := PackedVector2Array([Vector2(a.x,a.z),Vector2(b.x,b.z),Vector2(c.x,c.z)])
			if absf((triangle[1]-triangle[0]).cross(triangle[2]-triangle[0])) < .000001: continue
			polygons.append(CUT.counter_clockwise(triangle))
			points.append_array(triangle)
		if points.is_empty(): continue
		# Boxes and cylinders have a convex top; joint batches contain separate discs.
		if node.mesh is BoxMesh or node.mesh is CylinderMesh:
			var hull := Geometry2D.convex_hull(points)
			if hull.size()>3 and hull[0].is_equal_approx(hull[-1]): hull.remove_at(hull.size()-1)
			polygons.assign([CUT.counter_clockwise(hull)])
		entries.append({"node":node,"polygons":polygons,"height":top,"order":label+str(node.global_position.snapped(Vector3.ONE*.0001))})
	entries.sort_custom(func(a,b): return a.order<b.order if is_equal_approx(a.height,b.height) else a.height>b.height)
	var cover: Array[PackedVector2Array] = []
	var region: Node = parent.get_parent()
	while region != null and not ("harbor_road_geometry" in region): region = region.get_parent()
	if region != null and region.harbor_road_geometry != null:
		cover.append_array(region.harbor_road_geometry._layers[0].polygons)
	if zone == "salvage":
		# The crane yard owns this gravel court; do not paint meadow beneath it.
		cover.append(CUT.rect_polygon(Rect2(Vector2(parent.global_position.x,parent.global_position.z)-Vector2(16,11.5),Vector2(32,23))))
		# The railway supplies its physical ground landing; meadow and its approach
		# finish meet its edge instead of painting over the station's concrete.
		cover.append(CUT.rect_polygon(preload("res://world/railway/RailwayNetwork.gd").ground_landing_rect("harbor_central")))
	if zone == "cemetery":
		cover.append_array(preload("res://world/regions/OriginalCemetery3D.gd").path_footprints(Vector2(parent.global_position.x,parent.global_position.z)))
	for entry in entries:
		var pieces: Array[PackedVector2Array] = CUT.subtract(entry.polygons,cover)
		var local: Array[PackedVector2Array] = []
		var inverse: Transform3D = entry.node.global_transform.affine_inverse()
		# Keep original transforms/children and original elevation; replace only the top surface.
		var local_y: float = (inverse*Vector3(0,entry.height,0)).y
		for polygon in pieces:
			var converted := PackedVector2Array()
			for point in polygon:
				var p: Vector3 = inverse*Vector3(point.x,entry.height,point.y)
				converted.append(Vector2(p.x,p.z))
			local.append(converted)
		entry.node.mesh = CUT.flat_mesh(local,local_y,1.0)
		entry.node.set_meta("harbor_ground_composed_mesh",entry.node.mesh)
		entry.node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		cover.append_array(entry.polygons)
	if zone == "cobra" and parent.get_meta("harbor_ground_fill_reservation",false):
		# The district reserves its whole original footprint in the city base.
		# Saved path deletions/moves must reveal supported ground, never sky.
		var pieces: Array[PackedVector2Array] = []
		for footprint in footprints(zone,Vector2(parent.global_position.x,parent.global_position.z)):
			pieces.append_array(CUT.subtract_exact([footprint],cover))
			cover.append(footprint)
		var local: Array[PackedVector2Array] = []
		for polygon in pieces:
			var points := PackedVector2Array()
			for point in polygon:
				var p := parent.to_local(Vector3(point.x,0,point.y))
				points.append(Vector2(p.x,p.z))
			local.append(points)
		var mesh := CUT.flat_mesh(local,0.0,1.0)
		if mesh != null:
			var fill := MeshInstance3D.new()
			fill.name = "ReservedGroundInfill"
			fill.mesh = mesh
			fill.material_override = preload("res://world/urban_detail/CobraMaterials.gd").ground()
			fill.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			parent.add_child(fill)

static func _render_faces(mesh: Mesh) -> PackedVector3Array:
	var result := PackedVector3Array()
	for surface in mesh.get_surface_count():
		var arrays := MESH_ARRAYS.arrays_of(mesh, surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		if indices.is_empty(): result.append_array(vertices)
		else:
			for index in indices: result.append(vertices[index])
	return result

static func _is_ground(label: String) -> bool:
	if label == "CobraEasternCoast": return true
	return label in ["SalvageMeadow","SalvageTrack","CemeteryNorthGreen","CemeterySouthGreen","CemeteryWestGreen","CemeteryEastGreen","CobraDryMeadow","CobraApproachGround","CobraCommunalGarden","EmblemPaving","CobraGardenPath","CobraFootpathEdge","CobraFootpath","CobraEntrancePath","CobraSecretDrive","CobraHomeGravel","CobraWorkshopForecourt","CobraSecretParking","CobraCrossingLink","CobraPathCornersEdge","CobraPathCorners"] or label.begins_with("SalvageTrack") or label.begins_with("CobraHomeGravel") or label.begins_with("CobraGardenPath") or label.begins_with("CobraFootpath") or label.begins_with("CobraEntrancePath") or label.begins_with("CobraSecretDrive") or label.begins_with("CobraCrossingLink")
