extends RefCounted
## Vegetação local estática: uma malha instanciada, reservas físicas e seed fixa.
static var mesh: ArrayMesh
static var material: StandardMaterial3D

static func scatter(parent: Node3D) -> MultiMeshInstance3D:
	var reserved: Array = []
	for child in parent.find_children("*","MeshInstance3D",true,false):
		if child.mesh==null: continue
		var label := str(child.get_meta("cobra_surface_label",child.name))
		if label.begins_with("CobraPathCorners"): continue
		if not (label.contains("Path") or label.contains("CrossingLink") or label.contains("Gravel") or label.contains("Forecourt") or label.contains("Parking") or label.contains("Drive") or label.contains("Bench") or label.contains("Fence")): continue
		reserved.append([(parent.global_transform.affine_inverse()*child.global_transform).affine_inverse(),child.get_aabb().grow(.35)])
	var roads := preload("res://world/urban_detail/HarborGrassTufts.gd")._road_segments(parent,Rect2(-59,-47,111,92))
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
		if preload("res://world/urban_detail/HarborGrassTufts.gd")._on_road(Vector2(parent.global_position.x+p.x,parent.global_position.z+p.y),roads): continue
		var blocked := false
		for entry in reserved:
			var q: Vector3 = entry[0]*Vector3(p.x,.025,p.y)
			var bounds: AABB = entry[1]
			if q.x>=bounds.position.x and q.x<=bounds.end.x and q.z>=bounds.position.z and q.z<=bounds.end.z:
				blocked=true; break
		if blocked or _on_corner(parent,p): continue
		var size := rng.randf_range(.65,1.35)
		var basis := Basis(Vector3.UP,rng.randf()*TAU).scaled(Vector3(size,size,size))
		transforms.append(Transform3D(basis,Vector3(p.x,.04 if central else .015,p.y)))
		colors.append(Color("879164").lerp(Color("465637"),rng.randf()))
		if transforms.size()>=3000: break
	# Additional centre coverage: same exclusions, no scatter into footpaths.
	for i in 2600:
		var p := Vector2(rng.randf_range(-11.8,11.8),rng.randf_range(-11.8,11.8))
		if p.length()>11.8 or p.distance_to(Vector2(0,-1.875))<3.15: continue
		var blocked := false
		for entry in reserved:
			var q: Vector3=entry[0]*Vector3(p.x,.025,p.y)
			var bounds: AABB=entry[1]
			if q.x>=bounds.position.x and q.x<=bounds.end.x and q.z>=bounds.position.z and q.z<=bounds.end.z: blocked=true; break
		if blocked or _on_corner(parent,p): continue
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
