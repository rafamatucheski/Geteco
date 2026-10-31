extends RefCounted
## Posse visual dos pátios autorados, mais a posse física de estrada/solo.
## O recorte visual deixa a colisão intacta; compose_collision cuida disso à parte.
const MESH_ARRAYS := preload("res://world/chunk_bake/MeshArrayCache.gd")
const CUT := preload("res://world/urban_detail/GroundCut.gd")
const DETAIL := preload("res://world/desert/DesertSurfaceDetail.gd")
const LAYOUT := preload("res://world/desert/DesertLayout.gd")

## A estrada já emitiu seu próprio colisor. Só o solo arenoso abaixo de seu
## footprint perde faces; o chão fora da pista, as alturas e o desenho não mudam.
## Separado de compose(): o recorte visual dos pátios conserva seu contrato.
static func compose_collision(chunk: Node3D, rect: Rect2, corridors: Array[Dictionary]) -> void:
	var cover: Array[PackedVector2Array] = []
	var cover_bounds: Array[Rect2] = []
	for row in corridors:
		if row.bounds.intersects(rect):
			cover.append(row.polygon)
			cover_bounds.append(row.bounds)
	if cover.is_empty(): return
	for node in chunk.get_children():
		if not node is MeshInstance3D or not node.get_meta("desert_base_ground", false): continue
		if node.has_meta("desert_road_collision_owned"): continue
		for body in node.get_children():
			if not body is StaticBody3D: continue
			for collider in body.get_children():
				if not collider is CollisionShape3D or not collider.shape is ConcavePolygonShape3D: continue
				var faces: PackedVector3Array = collider.shape.get_faces()
				var output := _subtract_collision(faces, cover, cover_bounds)
				if output == faces: continue
				if output.is_empty():
					collider.disabled = true
				else:
					var shape := ConcavePolygonShape3D.new()
					shape.backface_collision = collider.shape.backface_collision
					shape.margin = collider.shape.margin
					shape.set_faces(output)
					collider.shape = shape
		node.set_meta("desert_road_collision_owned", true)

static func _subtract_collision(faces: PackedVector3Array, cover: Array[PackedVector2Array], cover_bounds: Array[Rect2]) -> PackedVector3Array:
	var output := PackedVector3Array()
	for offset in range(0, faces.size(), 3):
		var a := Vector2(faces[offset].x, faces[offset].z)
		var b := Vector2(faces[offset + 1].x, faces[offset + 1].z)
		var c := Vector2(faces[offset + 2].x, faces[offset + 2].z)
		var triangle := PackedVector2Array([a, b, c])
		var bounds := CUT.bounds(triangle)
		var local_cover: Array[PackedVector2Array] = []
		for index in cover.size():
			if bounds.intersects(cover_bounds[index]): local_cover.append(cover[index])
		if local_cover.is_empty():
			for index in 3: output.append(faces[offset + index])
			continue
		var denominator := (b - a).cross(c - a)
		if absf(denominator) < 0.0000001:
			for index in 3: output.append(faces[offset + index])
			continue
		var pieces: Array[PackedVector2Array] = [triangle]
		for part in CUT.subtract_exact(pieces, local_cover):
			var indices := Geometry2D.triangulate_polygon(part)
			for index in range(0, indices.size(), 3):
				var order := [indices[index], indices[index + 1], indices[index + 2]]
				if (part[order[1]] - part[order[0]]).cross(part[order[2]] - part[order[0]]) * denominator < 0.0:
					order = [order[0], order[2], order[1]]
				for vertex in order:
					var p: Vector2 = part[vertex]
					var wb := (p - a).cross(c - a) / denominator
					var wc := (b - a).cross(p - a) / denominator
					var wa := 1.0 - wb - wc
					output.append(faces[offset] * wa + faces[offset + 1] * wb + faces[offset + 2] * wc)
	return output

static func compose(chunk: Node3D, rect: Rect2, roads: RefCounted) -> void:
	var sites := DETAIL.site_polygons()
	sites.append(CUT.rect_polygon(LAYOUT.DRAG_MEET_BOUNDS))
	var affected := false
	for polygon in sites:
		if CUT.bounds(polygon).intersects(rect): affected=true; break
	if not affected: return
	var asphalt: Array[PackedVector2Array]=[]
	var shoulders: Array[PackedVector2Array]=[]
	for row in roads.corridors:
		if row.bounds.intersects(rect): asphalt.append(row.polygon)
	for row in roads.shoulders:
		if row.bounds.intersects(rect): shoulders.append(row.polygon)
	var site_cover: Array[PackedVector2Array]=[]
	for polygon in sites:
		if CUT.bounds(polygon).intersects(rect): site_cover.append(polygon)
	var shoulder_cover := asphalt.duplicate()
	shoulder_cover.append_array(site_cover)
	var base_cover := shoulder_cover.duplicate()
	base_cover.append_array(shoulders)
	for child in chunk.get_children():
		if not child is MeshInstance3D or child.mesh==null: continue
		if child.get_meta("desert_base_ground",false): clip_visual(child,base_cover)
		elif child.name=="GravelShoulder": clip_visual(child,shoulder_cover)
		elif child.name in [&"TruckApron",&"DigoApron",&"DragMeetPaddock"]: clip_visual(child,asphalt)

static func clip_visual(node: MeshInstance3D, cover: Array[PackedVector2Array]) -> void:
	if cover.is_empty(): return
	var cover_bounds: Array[Rect2]=[]
	for polygon in cover: cover_bounds.append(CUT.bounds(polygon))
	var mesh := ArrayMesh.new()
	var removed_area := 0.0
	for surface in node.mesh.get_surface_count():
		var source := MESH_ARRAYS.arrays_of(node.mesh, surface)
		var vertices: PackedVector3Array=source[Mesh.ARRAY_VERTEX]
		var source_normals: PackedVector3Array=source[Mesh.ARRAY_NORMAL]
		var has_colors: bool=source[Mesh.ARRAY_COLOR]!=null and not source[Mesh.ARRAY_COLOR].is_empty()
		var output := PackedVector3Array()
		var normals := PackedVector3Array()
		var colors := PackedColorArray()
		# These streamed floor builders emit non-indexed world-coordinate triangles.
		for offset in range(0,vertices.size(),3):
			var a := Vector2(vertices[offset].x,vertices[offset].z)
			var b := Vector2(vertices[offset+1].x,vertices[offset+1].z)
			var c := Vector2(vertices[offset+2].x,vertices[offset+2].z)
			var denominator := (b-a).cross(c-a)
			if absf(denominator)<0.0000001: continue
			var triangle := PackedVector2Array([a,b,c])
			var bounds := CUT.bounds(triangle)
			var local_cover: Array[PackedVector2Array]=[]
			for k in cover.size():
				if bounds.intersects(cover_bounds[k]): local_cover.append(cover[k])
			if local_cover.is_empty():
				for j in 3:
					output.append(vertices[offset+j])
					normals.append(source_normals[offset+j])
					if has_colors: colors.append(source[Mesh.ARRAY_COLOR][offset+j])
				continue
			var pieces: Array[PackedVector2Array]=[triangle]
			removed_area+=absf(denominator)*.5
			for part in CUT.subtract_exact(pieces,local_cover):
				var indices := Geometry2D.triangulate_polygon(part)
				for j in range(0,indices.size(),3):
					removed_area-=absf((part[indices[j+1]]-part[indices[j]]).cross(part[indices[j+2]]-part[indices[j]]))*.5
				for index in indices:
					var p := part[index]
					var wb := (p-a).cross(c-a)/denominator
					var wc := (b-a).cross(p-a)/denominator
					var wa := 1.0-wb-wc
					output.append(vertices[offset]*wa+vertices[offset+1]*wb+vertices[offset+2]*wc)
					normals.append((source_normals[offset]*wa+source_normals[offset+1]*wb+source_normals[offset+2]*wc).normalized())
					if has_colors: colors.append(source[Mesh.ARRAY_COLOR][offset]*wa+source[Mesh.ARRAY_COLOR][offset+1]*wb+source[Mesh.ARRAY_COLOR][offset+2]*wc)
		if output.is_empty(): continue
		var arrays: Array=[]
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX]=output
		arrays[Mesh.ARRAY_NORMAL]=normals
		if has_colors: arrays[Mesh.ARRAY_COLOR]=colors
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
		mesh.surface_set_material(mesh.get_surface_count()-1,node.mesh.surface_get_material(surface))
	node.set_meta("removed_hidden_ground_m2",maxf(0,removed_area))
	node.mesh=mesh if mesh.get_surface_count()>0 else null
