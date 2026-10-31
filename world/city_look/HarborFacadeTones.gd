extends RefCounted
## Harbor-only replacement finish. Existing vertices carry a whole-building
## palette; three shared albedos use baked face UVs, not triplanar/normal samples.
## No overlay meshes, additional surfaces, lights or per-frame work.
const MESH_ARRAYS := preload("res://world/chunk_bake/MeshArrayCache.gd")
const TEXTURES := {
	"brick": preload("res://assets/materials/harbor_facades/brick.png"),
	"plaster": preload("res://assets/materials/harbor_facades/plaster.png"),
	"concrete": preload("res://assets/materials/harbor_facades/concrete.png"),
}
const AUTHORED := {
	"FoundryLofts": Color("70473b"), "ColdStorage": Color("62665d"),
	"MarketHall": Color("795747"), "FreightDepot": Color("685647"),
	"FreightOffice": Color("787b6d"), "UnionWorkshop": Color("724b3f"),
	"CornerDiner": Color("a2715d"), "Laundry": Color("729087"),
	"NorthFrontage3": Color("586c65"), "NorthFrontage4": Color("8c7466"),
	"Police": Color("506773"), "Clinic": Color("83938a"),
}
static var _materials: Dictionary = {}
static var _batched_trim_materials: Dictionary = {}

static func apply(chunk: Node3D) -> void:
	_apply_batched_trim(chunk)
	for node in chunk.find_children("*", "MeshInstance3D", true, false):
		var instance := node as MeshInstance3D
		if instance.mesh == null or instance.has_meta("harbor_facade_tone"): continue
		var building := instance.get_parent()
		while building != null and not building is UrbanBuildingBase:
			building = building.get_parent()
		if building == null or instance.get_meta("city_window", false): continue
		var bounds := instance.global_transform * instance.get_aabb()
		var part := String(instance.name).to_lower()
		var trim := _is_trim(part)
		var wall := bounds.size.y >= 2.5 and maxf(bounds.size.x,bounds.size.z) >= 3.0
		if not wall and not trim: continue
		if part.contains("glass") or (part.contains("window") and not trim) or part.contains("shutter") or part.contains("sign"): continue
		var palette := _palette(building as UrbanBuildingBase, part)
		var result := ArrayMesh.new()
		var changed := false
		var local_inverse: Transform3D = building.global_transform.affine_inverse()
		for surface in instance.mesh.get_surface_count():
			var material := instance.get_active_material(surface) as StandardMaterial3D
			var arrays := MESH_ARRAYS.arrays_of(instance.mesh, surface).duplicate()
			if _eligible(material):
				var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
				var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				var colors := PackedColorArray()
				var uv := PackedVector2Array()
				colors.resize(vertices.size())
				uv.resize(vertices.size())
				colors.fill(Color.WHITE)
				for i in mini(vertices.size(),normals.size()):
					var world := instance.global_transform * vertices[i]
					var normal := (instance.global_basis.inverse().transposed()*normals[i]).normalized()
					uv[i] = Vector2(world.x, -world.y) / 4.0 if absf(normal.z) > .5 else Vector2(world.z, -world.y) / 4.0
					if absf(normal.y) > .5: uv[i] = Vector2(world.x,world.z) / 4.0
					var height := (local_inverse * world).y
					var wear := lerpf(.76,1.0,clampf(height / maxf(building.height,.1),0.0,1.0))
					colors[i] = Color("958f7f") * lerpf(.85,1.0,clampf(height / maxf(building.height,.1),0.0,1.0)) if trim else (palette.color as Color) * wear
					colors[i].a = 1.0
				arrays[Mesh.ARRAY_COLOR] = colors
				arrays[Mesh.ARRAY_TEX_UV] = uv
				material = _material("plaster" if trim else String(palette.style))
				changed = true
			var primitive: int = instance.mesh.surface_get_primitive_type(surface) if instance.mesh is ArrayMesh else Mesh.PRIMITIVE_TRIANGLES
			result.add_surface_from_arrays(primitive,arrays)
			result.surface_set_material(surface,material if material != null else instance.get_active_material(surface))
		if not changed: continue
		if instance.mesh is BoxMesh: instance.set_meta("harbor_source_box",true)
		instance.mesh = result
		instance.material_override = null
		for surface in result.get_surface_count(): instance.set_surface_override_material(surface,null)
		instance.set_meta("harbor_facade_tone",true)

## Skyline/lowrise details already arrive in MultiMeshes. Replace their shared
## stone finish too, preserving per-instance colours and the existing batching.
static func _apply_batched_trim(chunk: Node3D) -> void:
	var stone := UrbanMaterials.trim_stone()
	var cream := UrbanMaterials.trim_cream()
	for node in chunk.find_children("*", "MultiMeshInstance3D", true, false):
		var instance := node as MultiMeshInstance3D
		var source := instance.material_override as StandardMaterial3D
		if source == null or source.emission_enabled or source not in [stone,cream]: continue
		var owner_node := instance.get_parent()
		while owner_node != null and not owner_node is UrbanBuildingBase:
			owner_node = owner_node.get_parent()
		if owner_node == null: continue
		if not _batched_trim_materials.has(source):
			var replacement := source.duplicate() as StandardMaterial3D
			replacement.albedo_color *= Color(.70,.70,.68,1.0)
			replacement.roughness = maxf(replacement.roughness,.92)
			_batched_trim_materials[source] = replacement
		instance.material_override = _batched_trim_materials[source]
		instance.set_meta("harbor_facade_tone",true)

static func _eligible(material: StandardMaterial3D) -> bool:
	return material != null and not material.emission_enabled and not material.get_meta("city_window",false) and material.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED and material.metallic <= .2

static func _is_trim(part: String) -> bool:
	for token in ["cornice", "parapet", "pilaster", "lintel", "sill", "plinth", "storeyband", "porticosurround", "entryportal", "architrave", "stonerail", "baycap"]:
		if part.contains(token): return true
	return false

static func _palette(building: UrbanBuildingBase, part: String) -> Dictionary:
	var kind := building.building_kind
	var id := building.building_id
	var color: Color = AUTHORED.get(id,building.base_color)
	if not AUTHORED.has(id): color = color.lerp(Color("756b59"),.16).darkened(.07)
	# Preserve terrace identities as whole units, never random facade panels.
	if kind == "rowhouse_terrace": color = Color("795347") if part.ends_with("0") else Color("75695a")
	var style := "plaster"
	if kind in ["brownstone","rowhouse","rowhouse_terrace","l_shaped_block","artisan_workshop","warehouse","warehouse_shop"] or id in ["FoundryLofts","MarketHall","UnionWorkshop"]:
		style = "brick"
	elif kind in ["office","police_precinct","hospital","police_substation"]: style = "concrete"
	return {"color":color,"style":style}

static func _material(style: String) -> StandardMaterial3D:
	if not _materials.has(style):
		var material := StandardMaterial3D.new()
		material.albedo_texture = TEXTURES[style]
		material.vertex_color_use_as_albedo = true
		material.vertex_color_is_srgb = true
		material.roughness = .96
		material.metallic_specular = .12
		material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		_materials[style] = material
	return _materials[style]

