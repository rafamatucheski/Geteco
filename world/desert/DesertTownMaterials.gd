extends RefCounted
## Shared metre-scale finishes. No generated texture or material work after prewarm.
const URBAN := preload("res://assets/urban_detail/UrbanMaterials.gd")
const SHOP := preload("res://world/places/ShopInteriorMaterials.gd")
static var _cache: Dictionary={}

static func prewarm() -> void:
	for kind in ["adobe","cream","chalk","roof","stone","wood","steel","rust","glass","rubber"]: material(kind)

static func material(kind: String) -> StandardMaterial3D:
	if _cache.has(kind): return _cache[kind]
	var result: StandardMaterial3D
	match kind:
		"adobe":
			result=URBAN.textured_wall(Color("d3b18e"),.96).duplicate() as StandardMaterial3D
			result.albedo_color=Color("d2ac8b")
		"cream":
			result=URBAN.textured_wall(Color("d8c5a0"),.96).duplicate() as StandardMaterial3D
			result.albedo_color=Color("ceb693")
		"chalk":
			result=URBAN.textured_wall(Color("d2cbc0"),.96).duplicate() as StandardMaterial3D
			result.albedo_color=Color("c8c3b4")
		"roof":
			result=URBAN.textured_wall(Color("a8a59a"),.98).duplicate() as StandardMaterial3D
			result.albedo_color=Color("a49c86")
		"stone":
			result=SHOP.material("stone",Color("a49278")).duplicate() as StandardMaterial3D
			result.uv1_scale=Vector3.ONE*.65
		"wood": result=SHOP.material("wood",Color("8c7051")).duplicate() as StandardMaterial3D
		_:
			result=StandardMaterial3D.new()
			result.albedo_color={"steel":Color("68726c"),"rust":Color("95604c"),"glass":Color("304c50"),"rubber":Color("292c29")}.get(kind,Color.WHITE)
			result.metallic=.42 if kind in ["steel","rust"] else .0
			result.roughness=.28 if kind=="glass" else .83
	result.uv1_triplanar=true
	result.uv1_world_triplanar=true
	result.texture_filter=BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_cache[kind]=result
	return result

static func batch_visuals(root: Node3D) -> void:
	# Merge different static box/cylinder sizes by shared material. Physical pieces remain separate.
	var groups: Dictionary={}
	for child in root.get_children():
		if not child is MeshInstance3D or child.get_child_count()>0 or child.mesh.get_surface_count()!=1: continue
		var mat: Material=child.material_override
		if mat==null: continue
		var key := mat.get_rid()
		if not groups.has(key): groups[key]=[]
		groups[key].append(child)
	for items: Array in groups.values():
		if items.size()<2: continue
		var vertices := PackedVector3Array()
		var normals := PackedVector3Array()
		var uv := PackedVector2Array()
		for node: MeshInstance3D in items:
			var source: Array=node.mesh.surface_get_arrays(0)
			var positions: PackedVector3Array=source[Mesh.ARRAY_VERTEX]
			var source_normals: PackedVector3Array=source[Mesh.ARRAY_NORMAL]
			var indices: PackedInt32Array=source[Mesh.ARRAY_INDEX] if source[Mesh.ARRAY_INDEX]!=null else PackedInt32Array()
			var source_uv: PackedVector2Array=source[Mesh.ARRAY_TEX_UV] if source[Mesh.ARRAY_TEX_UV]!=null else PackedVector2Array()
			var count: int=indices.size() if not indices.is_empty() else positions.size()
			for i in count:
				var index: int=indices[i] if not indices.is_empty() else i
				vertices.append(node.transform*positions[index])
				normals.append((node.basis*source_normals[index]).normalized())
				uv.append(source_uv[index] if index<source_uv.size() else Vector2.ZERO)
		var arrays: Array=[]
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX]=vertices
		arrays[Mesh.ARRAY_NORMAL]=normals
		arrays[Mesh.ARRAY_TEX_UV]=uv
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
		var combined := MeshInstance3D.new()
		combined.name="BatchedTownDetail"
		combined.mesh=mesh
		combined.material_override=items[0].material_override
		root.add_child(combined)
		for item: MeshInstance3D in items: item.free()
