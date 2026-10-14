extends RefCounted
## Vegetação local estática: uma malha instanciada, reservas físicas e seed fixa.
static var mesh: ArrayMesh
static var material: StandardMaterial3D

static func scatter(parent: Node3D) -> MultiMeshInstance3D:
	var reserved: Array = []
	for child in parent.find_children("*","MeshInstance3D",true,false):
		if child.mesh==null: continue
		var label := str(child.get_meta("cobra_surface_label",child.name))
		if not child.is_visible_in_tree() or not (label.contains("Bench") or label.contains("Fence")): continue
		reserved.append([(parent.global_transform.affine_inverse()*child.global_transform).affine_inverse(),child.mesh.get_aabb().grow(.35)])
	var roads := preload("res://world/urban_detail/HarborGrassTufts.gd")._road_segments(parent,Rect2(-59,-47,111,92))
	var paving := _paved_areas(parent)
	var paving_grid := _paving_grid(paving)
	var rng := RandomNumberGenerator.new()
	rng.seed = 770017
	var transforms: Array[Transform3D] = []
	var colors: Array[Color] = []
	for i in 15000:
		var p := Vector2(rng.randf_range(-57,50),rng.randf_range(-44,44))
		# Rejection is bounded; dense centre and loose, uneven peripheral grass.
		var central := p.length()<12.0
		if not central and rng.randf()>.24: continue
		if p.distance_to(Vector2(0,-1.875))<3.15: continue
		# Aurora occupies this formerly empty roadside lot; keep its paving clear.
		var world_point := Vector2(parent.global_position.x+p.x,parent.global_position.z+p.y)
		if Rect2(409,109,22,30).has_point(world_point): continue
		if _on_paving(world_point,paving_grid.get(Vector2i(floori(world_point.x/8),floori(world_point.y/8)),[])): continue
		if paving.is_empty() and preload("res://world/urban_detail/HarborGrassTufts.gd")._on_road(world_point,roads): continue
		var blocked := false
		for entry in reserved:
			var q: Vector3 = entry[0]*Vector3(p.x,.025,p.y)
			var bounds: AABB = entry[1]
			if q.x>=bounds.position.x and q.x<=bounds.end.x and q.z>=bounds.position.z and q.z<=bounds.end.z:
				blocked=true; break
		if blocked: continue
		var size := rng.randf_range(.65,1.35)
		var basis := Basis(Vector3.UP,rng.randf()*TAU).scaled(Vector3(size,size,size))
		transforms.append(Transform3D(basis,Vector3(p.x,.04 if central else .015,p.y)))
		colors.append(Color("879164").lerp(Color("465637"),rng.randf()))
		if transforms.size()>=3000: break
	# Additional centre coverage: same exclusions, no scatter into footpaths.
	for i in 2600:
		var p := Vector2(rng.randf_range(-11.8,11.8),rng.randf_range(-11.8,11.8))
		if p.length()>11.8 or p.distance_to(Vector2(0,-1.875))<3.15: continue
		var world_point := Vector2(parent.global_position.x+p.x,parent.global_position.z+p.y)
		if _on_paving(world_point,paving_grid.get(Vector2i(floori(world_point.x/8),floori(world_point.y/8)),[])): continue
		if paving.is_empty() and preload("res://world/urban_detail/HarborGrassTufts.gd")._on_road(world_point,roads): continue
		var blocked := false
		for entry in reserved:
			var q: Vector3=entry[0]*Vector3(p.x,.025,p.y)
			var bounds: AABB=entry[1]
			if q.x>=bounds.position.x and q.x<=bounds.end.x and q.z>=bounds.position.z and q.z<=bounds.end.z: blocked=true; break
		if blocked: continue
		var size := rng.randf_range(.65,1.3)
		transforms.append(Transform3D(Basis(Vector3.UP,rng.randf()*TAU).scaled(Vector3.ONE*size),Vector3(p.x,.04,p.y)))
		colors.append(Color("7e8958").lerp(Color("405032"),rng.randf()))
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.use_colors = true
	multi.mesh = _blade_mesh()
	multi.instance_count = transforms.size()
	for i in transforms.size():
		multi.set_instance_transform(i,transforms[i])
		multi.set_instance_color(i,colors[i])
	var display := MultiMeshInstance3D.new()
	display.name = "CobraWildGrass"
	display.multimesh = multi
	display.material_override = material
	display.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(display)
	return display

## Use the same outer road polygons as ground ownership: these include the
## complete sidewalk and junction corners, not just asphalt width + 0.8 m.
## Reserve the whole tuft footprint (maximum blade reach is 0.23 m).
static func _paved_areas(parent: Node3D, margin: float = .3) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var area:=Rect2(Vector2(parent.global_position.x-59,parent.global_position.z-47),Vector2(111,92)).grow(margin)
	var cut:=preload("res://world/urban_detail/GroundCut.gd")
	# Composed render triangles are authoritative: source boxes and deleted pieces
	# no longer describe the actual paths after the saved editor outlines apply.
	for child in parent.find_children("*","MeshInstance3D",true,false):
		if child.mesh==null or not child.is_visible_in_tree(): continue
		var label:=str(child.get_meta("cobra_surface_label",child.get_meta("harbor_ground_label",child.name)))
		if not (label.contains("Path") or label.contains("CrossingLink") or label.contains("Gravel") or label.contains("Forecourt") or label.contains("Parking") or label.contains("Drive")): continue
		var faces:=preload("res://world/urban_detail/HarborDressingGround.gd")._render_faces(child.mesh)
		for i in range(0,faces.size(),3):
			var polygon:=PackedVector2Array()
			for j in 3:
				var point:Vector3=child.global_transform*faces[i+j]
				polygon.append(Vector2(point.x,point.z))
			if absf((polygon[1]-polygon[0]).cross(polygon[2]-polygon[0]))<.000001: continue
			_append_paving(result,polygon,margin)
	var region: Node = parent
	while region != null and not ("harbor_road_geometry" in region): region=region.get_parent()
	if region==null: return result
	if region.harbor_road_geometry!=null and not region.harbor_road_geometry._layers.is_empty():
		for polygon in region.harbor_road_geometry._layers[0].polygons:
			if cut.bounds(polygon).intersects(area): _append_paving(result,polygon,margin)
	# Ground patches may belong to neighbouring chunks not loaded yet. Use the
	# final runtime records and their replacement masks rather than source saves.
	if "records" in region:
		var factory:=preload("res://world/editing/WorldGroundFactory.gd")
		for rows in region.records.values():
			for row in rows:
				if row.kind!="editor_ground" or row.data.get("surface","") in ["grass","earth","sand"]: continue
				var polygon:=factory.footprint(row.data)
				if not cut.bounds(polygon).intersects(area): continue
				var pieces:Array[PackedVector2Array]=Geometry2D.intersect_polygons(polygon,cut.rect_polygon(row.clip))
				for mask in row.get("masks",[]): pieces=cut.subtract_exact(pieces,mask)
				for piece in pieces: _append_paving(result,piece,margin)
	return result

static func _append_paving(result: Array[Dictionary], polygon: PackedVector2Array, margin: float) -> void:
	var polygons:Array[PackedVector2Array]=[polygon]
	if margin>0: polygons=Geometry2D.offset_polygon(polygon,margin,Geometry2D.JOIN_ROUND)
	for expanded in polygons:
		result.append({"polygon":expanded,"bounds":preload("res://world/urban_detail/GroundCut.gd").bounds(expanded)})

static func _paving_grid(areas: Array[Dictionary]) -> Dictionary:
	var grid:Dictionary={}
	for area in areas:
		for x in range(floori(area.bounds.position.x/8),floori(area.bounds.end.x/8)+1):
			for z in range(floori(area.bounds.position.y/8),floori(area.bounds.end.y/8)+1):
				var key:=Vector2i(x,z)
				if not grid.has(key): grid[key]=[]
				grid[key].append(area)
	return grid

static func _on_paving(point: Vector2, areas: Array) -> bool:
	for area in areas:
		if area.bounds.has_point(point) and Geometry2D.is_point_in_polygon(point,area.polygon): return true
	return false

static func _on_corner(parent: Node3D,point: Vector2) -> bool:
	if not ("_cobra_joints" in parent): return false
	for joint in parent._cobra_joints:
		if point.distance_to(joint)<parent._cobra_joints[joint].x*.5+.4: return true
	return false

static func _blade_mesh() -> ArrayMesh:
	if mesh!=null: return mesh
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for blade in 5:
		var a := float(blade)*2.4
		var d := Vector3(cos(a),0,sin(a))
		var side := Vector3(-d.z,0,d.x)*.05
		var base := d*.065
		var height := .2+.045*float(blade%3)
		for point in [base-side,base+side,d*.17+Vector3.UP*height]:
			tool.set_normal(Vector3.UP)
			tool.add_vertex(point)
	mesh=tool.commit()
	material=StandardMaterial3D.new()
	material.vertex_color_use_as_albedo=true
	material.vertex_color_is_srgb=true
	material.cull_mode=BaseMaterial3D.CULL_DISABLED
	material.roughness=1
	return mesh
