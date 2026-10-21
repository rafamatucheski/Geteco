@tool
extends RefCounted
## A sparse mesh spanning the course (red/white tape, start gate) must retain
## its real projected triangles rather than fill its entire selection AABB.
static func refine(root: Node, rows: Array) -> void:
	var wanted := {}
	for row: Dictionary in rows:
		if str(row.get("source_record","")).begins_with("unit/harbor/s_motocross"):
			var parts: Array = row.get("parts",[])
			if parts.size() != 1: continue
			var part: Array = parts[0]
			if part.size() > 7 and part[7] == true: continue
			if float(part[2])*float(part[3]) > 400.0: wanted[str(row.id)] = row
	if wanted.is_empty(): return
	for group: Node3D in preload("res://world/editing/WorldEditPieces.gd").collect(root):
		var id := "piece/"+str(group.get_meta("world_edit_piece_id",""))
		if not wanted.has(id): continue
		var row: Dictionary = wanted[id]
		var actual := projected_parts(group)
		if not actual.is_empty():
			row.parts = actual
			row["footprint_geometry"] = true

static func projected_parts(group: Node3D) -> Array:
	var parts: Array = []
	preload("res://addons/geteco_world_editor/WorldContextCatalog.gd").collect(group,parts)
	# Vertical tape has zero top-down triangle area. Render its actual edge as a
	# thin strip; the general catalog's empty-art AABB fallback would recreate
	# the original giant filled rectangle even after collecting real triangles.
	var pending: Array[Node] = [group]
	var seen := {}
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		if node is Node3D and not node.visible: continue
		if node is MeshInstance3D and node.mesh != null:
			var faces: PackedVector3Array = node.mesh.get_faces()
			var color := "9db7c4"
			var material: Material = node.material_override
			if material == null and node.mesh.get_surface_count() > 0: material = node.get_active_material(0)
			if material is BaseMaterial3D: color = material.albedo_color.to_html(false)
			for index in range(0,faces.size()-2,3):
				var a: Vector3 = node.global_transform*faces[index]
				var b: Vector3 = node.global_transform*faces[index+1]
				var c: Vector3 = node.global_transform*faces[index+2]
				var points := [Vector2(a.x,a.z),Vector2(b.x,b.z),Vector2(c.x,c.z)]
				if absf((points[1]-points[0]).cross(points[2]-points[0])) >= .04: continue
				var left: Vector2 = points[0]
				var right: Vector2 = points[1]
				for pair in [[0,2],[1,2]]:
					if (points[pair[0]] as Vector2).distance_squared_to(points[pair[1]]) > left.distance_squared_to(right):
						left = points[pair[0]]
						right = points[pair[1]]
				if left.distance_squared_to(right) < .01: continue
				if left.x > right.x or (is_equal_approx(left.x,right.x) and left.y > right.y):
					var swap := left
					left = right
					right = swap
				var first := left.snapped(Vector2.ONE*.01)
				var second := right.snapped(Vector2.ONE*.01)
				var key := Vector4(first.x,first.y,second.x,second.y)
				if seen.has(key): continue
				seen[key] = true
				var across := (right-left).normalized().orthogonal()*.06
				var polygon: Array = []
				var bounds := Rect2(left-across,Vector2.ZERO)
				for point in [left-across,right-across,right+across,left+across]:
					polygon.append([point.x,point.y])
					bounds = bounds.expand(point)
				parts.append([bounds.position.x,bounds.position.y,bounds.size.x,bounds.size.y,maxf(a.y,maxf(b.y,c.y)),color,polygon])
		for child in node.get_children(): pending.append(child)
	return parts
