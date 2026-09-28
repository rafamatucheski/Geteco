extends RefCounted
## Paint only authored body materials. Original meshes and other surfaces stay shared.
static var _sources: Dictionary = {}
var materials: Array[StandardMaterial3D] = []
var original_color := Color.WHITE
var roof_materials: Array[StandardMaterial3D] = []

static func source_for(archetype: String) -> Dictionary:
	if archetype == "police_transport": archetype = "courier_van"
	if _sources.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://runtime/VehiclePaintSources.json"))
		if parsed is Dictionary: _sources = parsed
	return _sources.get(archetype,{})

func bind(root: Node3D, archetype: String) -> void:
	materials.clear()
	roof_materials.clear()
	var source := source_for(archetype)
	var copies: Dictionary = {}
	for part: MeshInstance3D in root.find_children("*","MeshInstance3D",true,false):
		if part.mesh == null: continue
		var key := ""
		var surface_keys: Variant = []
		for metadata in part.get_meta_list():
			if str(metadata).ends_with("surface_material_keys"): surface_keys = part.get_meta(metadata)
			elif str(metadata).ends_with("material_key"): key = str(part.get_meta(metadata))
		if part.material_override != null:
			var original := part.material_override as StandardMaterial3D
			if key == "roof_paint":
				part.material_override = _local(original,copies)
				roof_materials.append(part.material_override)
				continue
			if _is_paint(original,key,source): part.material_override = _local(original,copies)
			continue
		for index in part.mesh.get_surface_count():
			var original := part.get_active_material(index) as StandardMaterial3D
			var surface_key: String = str(surface_keys[index]) if index < surface_keys.size() else key
			if _is_paint(original,surface_key,source): part.set_surface_override_material(index,_local(original,copies))
	for material in materials:
		if material not in roof_materials:
			original_color = material.albedo_color
			break

func _is_paint(material: StandardMaterial3D, key: String, source: Dictionary) -> bool:
	if material == null: return false
	if not key.is_empty(): return key == "paint"
	if material.resource_name == "paint": return true
	if source.is_empty(): return false
	# Old exports lack semantic tags: match the exact authored paint recipe,
	# never an approximate body color or all materials on a vehicle.
	return material.albedo_color.is_equal_approx(Color.html(source.color)) and is_equal_approx(material.metallic,float(source.metallic)) and is_equal_approx(material.roughness,float(source.roughness)) and not material.emission_enabled and material.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED

func _local(original: StandardMaterial3D, copies: Dictionary) -> StandardMaterial3D:
	if not copies.has(original):
		var instance := original.duplicate() as StandardMaterial3D
		copies[original] = instance
		materials.append(instance)
	return copies[original]

func apply(color: Color) -> void:
	for material in materials:
		material.albedo_color = preload("res://runtime/VehicleTwoTone.gd").roof_color(color) if material in roof_materials else Color(color.r,color.g,color.b,1.0)
