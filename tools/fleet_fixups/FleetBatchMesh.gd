extends RefCounted
## Só autoria de malha offline. As superfícies semânticas continuam disponíveis para pintura,
## portas, dano de vidro e equipamento. Nenhuma simplificação em runtime é instalada.
const ROLES = preload("res://runtime/VehicleSurfaceRoles.gd")
const PAINT = preload("res://runtime/VehiclePaint.gd")

static func counts(model: Node) -> Dictionary:
	var result := {"meshes":0,"surfaces":0,"triangles":0}
	for part in model.find_children("*","MeshInstance3D",true,false):
		if part.mesh == null: continue
		result.meshes += 1
		result.surfaces += part.mesh.get_surface_count()
		result.triangles += part.mesh.get_faces().size()/3
	return result

static func role(part: MeshInstance3D, surface: int, archetype: String) -> String:
	var key: String = ROLES.key(part,surface)
	var mat := part.get_active_material(surface) as StandardMaterial3D
	if mat == null: return key
	if key.is_empty():
		var recipe: Dictionary = PAINT.source_for(archetype)
		if not recipe.is_empty() and mat.albedo_color.is_equal_approx(Color.html(recipe.color)) and is_equal_approx(mat.metallic,float(recipe.metallic)) and is_equal_approx(mat.roughness,float(recipe.roughness)):
			key = "paint"
		elif mat.emission_enabled:
			var at: Vector3=part.transform*ROLES.center(part,surface)
			if archetype in ["police_cruiser","police_suv","police_transport"] and mat.albedo_color.is_equal_approx(Color("e83c42")): key="bar_left"
			elif archetype in ["police_cruiser","police_suv","police_transport"] and mat.albedo_color.is_equal_approx(Color("3689ef")): key="bar_right"
			elif at.z>0 and mat.albedo_color.r>.55 and mat.albedo_color.g<.4: key="tail"
			elif at.z<0 and mat.albedo_color.s<.35 and mat.albedo_color.v>.8: key="headlight"
			else: key="lens"
		elif mat.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED or (mat.roughness<=.19 and absf(mat.metallic-.3)<=.06): key="glass"
		else: key="trim"
	return key

static func reduced_mesh(source: Mesh, ratio: float) -> Mesh:
	if source is CylinderMesh:
		var primitive := source.duplicate() as CylinderMesh
		primitive.radial_segments=mini(20,primitive.radial_segments)
		primitive.rings=1
		return primitive
	if source is SphereMesh:
		var primitive := source.duplicate() as SphereMesh
		primitive.radial_segments=mini(16,primitive.radial_segments)
		primitive.rings=mini(8,primitive.rings)
		return primitive
	var result := ArrayMesh.new()
	for surface in source.get_surface_count():
		var arrays: Array = source.surface_get_arrays(surface)
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX]!=null else PackedInt32Array()
		var count: int = indices.size() if not indices.is_empty() else arrays[Mesh.ARRAY_VERTEX].size()
		if count>240 and ratio<.99:
			# Index coincident vertices first: imported flat arrays otherwise expose
			# every triangle edge as a boundary to the simplifier.
			var st := SurfaceTool.new()
			st.create_from(source,surface)
			st.index()
			arrays=st.commit_to_arrays()
			var importer := ImporterMesh.new()
			importer.add_surface(Mesh.PRIMITIVE_TRIANGLES,arrays)
			importer.generate_lods(25.0,60.0,[])
			var wanted := maxi(72,roundi(count*ratio))
			var best: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			var distance: int = absi(best.size()-wanted)
			for lod in importer.get_surface_lod_count(0):
				var candidate := importer.get_surface_lod_indices(0,lod)
				if candidate.size()>=36 and abs(candidate.size()-wanted)<distance:
					best=candidate
					distance=abs(candidate.size()-wanted)
			arrays[Mesh.ARRAY_INDEX]=best
		result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
		result.surface_set_material(result.get_surface_count()-1,source.surface_get_material(surface))
	return result

static func bake(source: Node3D, budget_ratio: float=.25, archetype: String="") -> Node3D:
	var result := Node3D.new()
	result.name=source.name
	for meta in source.get_meta_list(): result.set_meta(meta,source.get_meta(meta))
	result.set_meta("fleet_redesign_version",1)
	result.set_meta("fleet_finish",true)
	var groups := {}
	var materials := {}
	var mesh_cache := {}
	var door: Dictionary=preload("res://data/catalogs/VehicleDoorSpecs.gd").row(archetype)
	# Preserve functional branches (vault doors, markers, skeletons) intact.
	for node in source.get_children():
		if not node is MeshInstance3D:
			var copy := node.duplicate()
			result.add_child(copy)
			continue
		var part := node as MeshInstance3D
		if part.mesh==null: continue
		if not part.visible and not part.has_meta("batch_keep") and part.name not in ["VaultDoorLeft","VaultDoorRight","VaultCargo"]: continue
		var group := "Body"
		# Grupo explícito vence o conjunto da roda: as manoplas da moto ficam no pivô de
		# direção (o wheel_center é copiado abaixo), mas precisam continuar achadas por metadado.
		if part.has_meta("batch_group"):
			group=str(part.get_meta("batch_group"))
		elif part.has_meta("wheel_center"):
			group="Wheel_"+str(part.get_meta("wheel_center"))+"_"+str(part.get_meta("wheel_spins",true))
		elif part.has_meta("batch_keep") or part.name in ["VaultDoorLeft","VaultDoorRight","VaultCargo"]:
			group=str(part.name)
		elif not door.is_empty():
			# O DoorBuilder transfere estes objetos completos para a folha. Agrupá-los
			# no casco deixaria as faces de cima/baixo deles na carroceria.
			var bounds: AABB=part.transform*part.mesh.get_aabb()
			var inside: bool=bounds.position.z>=float(door.zf)-.02 and bounds.end.z<=float(door.zr)+.02 and bounds.position.y>=float(door.sill)-.02 and bounds.end.y<=float(door.top)+.02
			if inside and bounds.size.x<.6:
				if bounds.position.x>.2: group="DoorTrimR"
				elif bounds.end.x<-.2: group="DoorTrimL"
		if not groups.has(group): groups[group]={"surfaces":{},"meta":{}}
		var data: Dictionary = groups[group]
		if part.has_meta("wheel_center"):
			data.meta["wheel_center"]=part.get_meta("wheel_center")
			data.meta["wheel_spins"]=part.get_meta("wheel_spins",true)
		if group==str(part.name):
			for meta in part.get_meta_list(): data.meta[meta]=part.get_meta(meta)
		var extra: Dictionary=part.get_meta("batch_group_meta",{})
		for meta in extra: data.meta[meta]=extra[meta]
		var ratio: float=float(part.get_meta("batch_ratio",budget_ratio))
		var cache_key := str(part.mesh.get_instance_id())+":"+str(ratio)
		if not mesh_cache.has(cache_key): mesh_cache[cache_key]=reduced_mesh(part.mesh,ratio)
		var mesh: Mesh = mesh_cache[cache_key]
		for surface in mesh.get_surface_count():
			var original := part.get_active_material(surface)
			if original==null: continue
			var key := role(part,surface,archetype)
			var arrays: Array=mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
			var normal: PackedVector3Array=arrays[Mesh.ARRAY_NORMAL] if arrays[Mesh.ARRAY_NORMAL]!=null else PackedVector3Array()
			var uv: PackedVector2Array=arrays[Mesh.ARRAY_TEX_UV] if arrays[Mesh.ARRAY_TEX_UV]!=null else PackedVector2Array()
			var color: PackedColorArray=arrays[Mesh.ARRAY_COLOR] if arrays[Mesh.ARRAY_COLOR]!=null else PackedColorArray()
			var indices: PackedInt32Array=arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX]!=null else PackedInt32Array()
			var baked_color := Color.WHITE
			var material: Material=original
			var signature := str(original.get_instance_id())+":"+key
			if original is StandardMaterial3D:
				material=original.duplicate()
				# A cor é dado de geometria para acabamento não interativo; um material pode
				# desenhar grades pretas, liga escovada e pequenos detalhes coloridos.
				var semantic := key=="paint" or key=="roof_paint" or "glass" in key or ROLES.is_headlight_lens(key) or ROLES.is_tail_lens(key) or key in ["bar_left","bar_right","rubber","tire","wheel_rubber"]
				if not semantic and original.albedo_texture==null and not original.emission_enabled and original.transparency==BaseMaterial3D.TRANSPARENCY_DISABLED:
					baked_color=original.albedo_color if original.vertex_color_is_srgb else original.albedo_color.srgb_to_linear()
					material.albedo_color=Color.WHITE
					material.vertex_color_use_as_albedo=true
					key="trim"
				var properties := {}
				for property: Dictionary in material.get_property_list():
					var property_name: String=property.name
					if int(property.usage)&PROPERTY_USAGE_STORAGE and not property_name.begins_with("resource_") and property_name!="script": properties[property_name]=material.get(property_name)
				signature=str(hash(properties))+":"+key
			# As superfícies dos faróis esquerdo/direito precisam ficar separadas: o equipamento tira
			# os lados do projetor e da lente quebrada dos respectivos limites.
			if ROLES.is_headlight_lens(key):
				signature += ":"+str(signf((part.transform*ROLES.center(part,surface)).x))
			if not materials.has(signature): materials[signature]=material
			if not data.surfaces.has(signature):
				var tool := SurfaceTool.new()
				tool.begin(Mesh.PRIMITIVE_TRIANGLES)
				data.surfaces[signature]={"tool":tool,"role":key}
			var tool: SurfaceTool=data.surfaces[signature].tool
			var total: int=indices.size() if not indices.is_empty() else vertices.size()
			for cursor in total:
				var index: int=indices[cursor] if not indices.is_empty() else cursor
				tool.set_normal((part.basis.inverse().transposed()*normal[index]).normalized() if index<normal.size() else Vector3.UP)
				tool.set_uv(uv[index] if index<uv.size() else Vector2.ZERO)
				tool.set_color((color[index] if index<color.size() and original is StandardMaterial3D and original.vertex_color_use_as_albedo else Color.WHITE)*baked_color)
				tool.add_vertex(part.transform*vertices[index])
	for group: String in groups:
		var data: Dictionary=groups[group]
		var node := MeshInstance3D.new()
		node.name=group.replace("(","").replace(")","").replace(",","_")
		var mesh := ArrayMesh.new()
		var roles: Array[String]=[]
		for signature: String in data.surfaces:
			var entry: Dictionary=data.surfaces[signature]
			var tool: SurfaceTool=entry.tool
			tool.index()
			tool.set_material(materials[signature])
			tool.commit(mesh)
			roles.append(str(entry.role))
		node.mesh=mesh
		for meta in data.meta: node.set_meta(meta,data.meta[meta])
		node.set_meta("batch_surface_material_keys",roles)
		result.add_child(node)
	assign_owners(result,result)
	return result

static func assign_owners(node: Node, owner_node: Node) -> void:
	for child in node.get_children():
		child.owner=owner_node
		assign_owners(child,owner_node)

static func save_model(model: Node3D, destination: String) -> Error:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(destination.get_base_dir()))
	assign_owners(model,model)
	var packed := PackedScene.new()
	var status := packed.pack(model)
	if status==OK: status=ResourceSaver.save(packed,destination)
	return status
