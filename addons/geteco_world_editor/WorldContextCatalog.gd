extends RefCounted
## Read-only background from actual constructed scene geometry, including composite places.
const PIECES := preload("res://world/editing/WorldEditPieces.gd")
const DATA := preload("res://world/editing/WorldEditData.gd")
const LABELS := {"cemetery":"Cemitério", "salvage":"Ferro-velho", "ship":"Northstar", "south_port_ship_detail":"Santa Mare / Porto Sul", "sawmill_yard":"Madeireira", "mountain_village":"Vilarejo da montanha", "cargo_plane":"Avião no lago", "harbor_bridge":"Ponte de Harbor", "environmental_parity":"Teleférico", "cave_approach":"Acesso à caverna", "harbor_restaurant":"Terraço", "container":"Contêiner", "south_port_rail":"Ferrovia", "harbor_public_realm":"Área pública", "harbor_dressing":"Paisagismo", "harbor_route_zone":"Conjunto urbano"}

static func build(region: Node3D) -> Dictionary:
	var rows := {}
	var kinds := {}
	var total := 0
	var covered := 0
	var index := 0
	for key in region.records:
		for record in region.records[key]:
			total += 1
			kinds[record.kind] = int(kinds.get(record.kind,0))+1
			if record.kind == "road" or not DATA.record_id(record).is_empty():
				covered += 1
				continue
			var holder := Node3D.new()
			region.add_child(holder)
			region._build_record(holder,record)
			await region.get_tree().process_frame
			var id: String = "context/"+region.region_id+"/"+str(record.kind)+"/"+str(index)
			index += 1
			var label: String = LABELS.get(record.kind,str(record.kind).capitalize())
			if record.kind in ["original_facade","mountain_place"]: label = str(record.data.original_name)
			elif record.kind == "lake": label = "Lago alpino" if record.variant == "alpine" else "Lago secreto"
			elif record.has("id"): label = str(record.id)
			elif record.has("zone_id"): label += " / "+str(record.zone_id)
			var fallback: Vector3 = record.get("position",Vector3((key.x+.5)*64,0,(key.y+.5)*64))
			if record.has("data") and record.data.get("exterior_position") is Vector3: fallback = record.data.exterior_position
			rows[id] = from_node(holder,id,label,record.kind,fallback,true)
			for group in PIECES.collect(holder):
				var piece_id := "piece/"+str(group.get_meta("world_edit_piece_id"))
				var piece_label := str(group.get_meta("world_edit_label",piece_id))
				var row := from_node(group,piece_id,piece_label,record.kind,group.global_position)
				var bounds_center := DATA.point(row.position)
				var pivot := DATA.xy(group.global_position)
				var margin := (DATA.point(pivot)-bounds_center).abs()
				row.size = [float(row.size[0])+2*margin.x,float(row.size[1])+2*margin.y]
				row.merge({"type":"piece","position":pivot,"rotation":0.0,"locked":group.get_meta("world_edit_locked",false),"source_record":PIECES.record_key(record),"ground":row.parts.all(func(part): return float(part[4]) < group.global_position.y+.3)},true)
				var physical_points: Array[Vector3] = []
				PIECES._points(group,physical_points)
				if not physical_points.is_empty():
					row.selection_height = -INF
					for point in physical_points: row.selection_height = maxf(row.selection_height,point.y)
					row.ground = row.selection_height < group.global_position.y+.3
				rows[piece_id] = row
			holder.free()
			covered += 1
	return {"objects":rows,"record_count":total,"covered_records":covered,"kind_counts":kinds}

static func from_node(node: Node3D,id: String,label: String,kind: String,fallback: Vector3,skip_pieces := false) -> Dictionary:
	var parts: Array = []
	collect(node,parts,skip_pieces)
	# Curved small props can have every triangle below the map simplification
	# threshold. Keep a visible footprint instead of classifying empty art as floor.
	if parts.is_empty() and not skip_pieces:
		var points: Array[Vector3] = []
		PIECES._points(node,points)
		if not points.is_empty():
			var footprint := AABB(points[0],Vector3.ZERO)
			for point in points: footprint = footprint.expand(point)
			parts.append([footprint.position.x,footprint.position.z,maxf(.08,footprint.size.x),maxf(.08,footprint.size.z),footprint.end.y,"9db7c4"])
	parts.sort_custom(func(a,b): return float(a[4]) < float(b[4]))
	var bounds := Rect2(Vector2(fallback.x,fallback.z)-Vector2.ONE,Vector2.ONE*2)
	if not parts.is_empty():
		bounds = Rect2(parts[0][0],parts[0][1],parts[0][2],parts[0][3])
		for part in parts: bounds = bounds.merge(Rect2(part[0],part[1],part[2],part[3]))
	return {"id":id,"type":"context","kind":kind,"label":label,"locked":true,"position":[bounds.get_center().x,bounds.get_center().y],"size":[bounds.size.x,bounds.size.y],"parts":parts}

static func collect(node: Node,parts: Array,skip_pieces := false) -> void:
	if skip_pieces and node.has_meta("world_edit_piece_id"): return
	if node is Node3D and not node.visible: return
	if node is MeshInstance3D and node.mesh != null:
		var material: Material = node.material_override
		if material == null and node.mesh.get_surface_count() > 0: material = node.get_active_material(0)
		part(node.mesh,node.global_transform,material,parts)
	elif node is MultiMeshInstance3D and node.multimesh != null and node.multimesh.mesh != null:
		var mm: MultiMesh = node.multimesh
		var material: Material = node.material_override
		if material == null and mm.mesh.get_surface_count() > 0: material = mm.mesh.surface_get_material(0)
		var count := mm.instance_count if mm.visible_instance_count < 0 else mini(mm.instance_count,mm.visible_instance_count)
		for i in count: part(mm.mesh,node.global_transform*mm.get_instance_transform(i),material,parts)
	for child in node.get_children(): collect(child,parts,skip_pieces)

static func part(mesh: Mesh,transform: Transform3D,material: Material,parts: Array) -> void:
	var bounds := transform*mesh.get_aabb()
	if bounds.size.x*bounds.size.z < .04: return
	for surface in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR] if arrays[Mesh.ARRAY_COLOR] != null else PackedColorArray()
		var mat: Material = material if material != null else mesh.surface_get_material(surface)
		var tint := Color("657c68")
		if mat is BaseMaterial3D:
			tint = mat.albedo_color
			if mat.albedo_texture is NoiseTexture2D and mat.albedo_texture.color_ramp != null: tint *= mat.albedo_texture.color_ramp.sample(.5)
			if tint.a < .1: continue
		var count := indices.size() if not indices.is_empty() else vertices.size()
		for offset in range(0,count-2,3):
			var polygon: Array = []
			var high := -INF
			var low := INF
			var color := tint
			var rect := Rect2()
			for corner in 3:
				var index: int = indices[offset+corner] if not indices.is_empty() else offset+corner
				var p := transform*vertices[index]
				var point := Vector2(p.x,p.z)
				polygon.append([snappedf(point.x,.01),snappedf(point.y,.01)])
				high = maxf(high,p.y)
				low = minf(low,p.y)
				if corner == 0:
					rect = Rect2(point,Vector2.ZERO)
					if not colors.is_empty() and mat is BaseMaterial3D and mat.vertex_color_use_as_albedo: color *= colors[index]
				else: rect = rect.expand(point)
			var a := DATA.point(polygon[0])
			var b := DATA.point(polygon[1])
			var c := DATA.point(polygon[2])
			if absf((b-a).cross(c-a)) < .04: continue
			# Floors first; top surfaces then preserve the internal structure of batched models.
			parts.append([snappedf(rect.position.x,.01),snappedf(rect.position.y,.01),snappedf(rect.size.x,.01),snappedf(rect.size.y,.01),snappedf((high+low)*.5,.01),color.to_html(false),polygon])
