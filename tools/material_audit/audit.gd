extends SceneTree
## Auditoria somente leitura. Não mede FPS, duração nem tempo de quadro.
## --no-save --chunks=3,0;3,1;0,1;1,1 --state=day|night|rain
## --output=res://evidence/otimizacao-20261014-D6/materials-day.json
const REGION := preload("res://world/regions/NativeRegion.gd")
const CITY := preload("res://world/city_look/CityLookMaterials.gd")
const MODES := ["exact", "color", "roughness", "scalar"]
const OMIT := ["resource_name", "resource_path", "resource_scene_unique_id"]
var resource_signatures: Dictionary = {}

func _initialize() -> void:
	run.call_deferred()

## Valores completos, sem arredondar cores, UVs ou parâmetros. Uma textura com
## os mesmos pixels pode ter outro RID; comparar conteúdo evita falso negativo.
func encode(value: Variant, stack: Array = []) -> String:
	if value is Resource:
		var resource := value as Resource
		var id := resource.get_instance_id()
		if id in stack: return "cycle:%s:%d" % [resource.get_class(), id]
		if resource_signatures.has(id): return resource_signatures[id]
		var encoded: String
		if resource is Texture2D:
			var pixels := (resource as Texture2D).get_image()
			if pixels != null:
				encoded = "texture:%s:%d:%d:%d:%s:%s" % [resource.get_class(), pixels.get_width(), pixels.get_height(), pixels.get_format(), pixels.has_mipmaps(), pixels.get_data().hex_encode().sha256_text()]
			else:
				encoded = "texture-unreadable:%s:%d" % [resource.get_class(), id]
		else:
			var nested := stack.duplicate()
			nested.append(id)
			encoded = var_to_str(properties(resource, nested)).sha256_text()
		resource_signatures[id] = encoded
		return encoded
	if value is Dictionary:
		var pairs: Array[String] = []
		for key in value: pairs.append(encode(key, stack) + ":" + encode(value[key], stack))
		pairs.sort()
		return "dictionary:" + var_to_str(pairs)
	if value is Array:
		var entries: Array[String] = []
		for item in value: entries.append(encode(item, stack))
		return "array:" + var_to_str(entries)
	if value is Object:
		return "object:%s:%d" % [value.get_class(), value.get_instance_id()]
	# var_to_bytes conserva a precisão binária dos floats (var_to_str arredonda).
	return str(typeof(value)) + ":" + var_to_bytes(value).hex_encode()

func properties(resource: Resource, stack: Array = []) -> Dictionary:
	var result := {"class": resource.get_class()}
	var names: Array[String] = []
	for property in resource.get_property_list():
		var label := str(property.name)
		if (int(property.usage) & PROPERTY_USAGE_STORAGE) == 0 or label in OMIT: continue
		names.append(label)
	names.sort()
	for label in names: result[label] = encode(resource.get(label), stack)
	return result

func signatures(material: Material) -> Dictionary:
	var props := properties(material, [material.get_instance_id()])
	var result := {}
	for mode in MODES:
		var selected := props.duplicate()
		for key in props:
			if key == "class": continue
			if mode == "color" and key == "albedo_color": selected.erase(key)
			if mode == "roughness" and key == "roughness": selected.erase(key)
			# Não apagar enums/flags inteiros: culling, blend e transparência
			# fazem parte do contrato. Uniformes escalares do shader são valores.
			if mode == "scalar":
				var value: Variant = material.get(key)
				if typeof(value) == TYPE_FLOAT or (material is ShaderMaterial and str(key).begins_with("shader_parameter/") and typeof(value) == TYPE_INT): selected.erase(key)
		result[mode] = var_to_str(selected).sha256_text()
	return result

func add_material(material: Material, path: String, entries: Dictionary, visited: Array = []) -> void:
	if material == null or material.get_instance_id() in visited: return
	var id := material.get_instance_id()
	if not entries.has(id):
		var origins: Array[String] = []
		for key in CITY._cache:
			var cached: Variant = CITY._cache[key]
			if cached is Material and is_same(cached, material): origins.append("CityLookMaterials." + str(key))
		for key in UrbanMaterials._cache:
			var cached: Variant = UrbanMaterials._cache[key]
			if cached is Material and is_same(cached, material): origins.append("UrbanMaterials." + str(key))
		for key in UrbanSurfaces._materials:
			var cached: Variant = UrbanSurfaces._materials[key]
			if cached is Material and is_same(cached, material): origins.append("UrbanSurfaces." + str(key))
		var state := {}
		if material is BaseMaterial3D:
			state = {"albedo": var_to_str(material.albedo_color), "roughness": material.roughness, "metallic": material.metallic, "emission": var_to_str(material.emission), "emission_energy": material.emission_energy_multiplier}
		entries[id] = {"id": id, "class": material.get_class(), "resource": material.resource_path, "references": 0, "paths": [], "origins": origins, "state": state, "signatures": signatures(material), "properties": properties(material, [id])}
	entries[id].references += 1
	if entries[id].paths.size() < 5: entries[id].paths.append(path)
	var chain := visited.duplicate()
	chain.append(id)
	add_material(material.next_pass, path + "/next_pass", entries, chain)

func ranked_groups(entries: Dictionary, mode: String) -> Array:
	var groups := {}
	for entry: Dictionary in entries.values():
		var key: String = entry.signatures[mode]
		if not groups.has(key): groups[key] = []
		groups[key].append(entry)
	var result: Array = []
	for group: Array in groups.values():
		if group.size() < 2: continue
		var variants := {}
		var references := 0
		var members: Array = []
		var changed: Array[String] = []
		var first: Dictionary = group[0].properties
		for entry: Dictionary in group:
			variants[entry.signatures.exact] = true
			references += int(entry.references)
			members.append({"id": entry.id, "class": entry.class, "resource": entry.resource, "references": entry.references, "paths": entry.paths, "origins": entry.origins, "state": entry.state})
			for key in entry.properties:
				if entry.properties[key] != first.get(key) and not key in changed: changed.append(key)
		# Grupos aproximados devem realmente diferir; os idênticos já estão em exact.
		if mode != "exact" and variants.size() < 2: continue
		changed.sort()
		result.append({"instances": group.size(), "extra_instances": group.size() - 1, "exact_variants": variants.size(), "references": references, "differing_properties": changed, "members": members})
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a.extra_instances != b.extra_instances: return a.extra_instances > b.extra_instances
		return a.references > b.references)
	return result

func inspect_chunk(chunk: Node) -> Dictionary:
	var entries := {}
	var geometries := 0
	var without_material := 0
	for geometry in chunk.find_children("*", "GeometryInstance3D", true, false):
		if not geometry.is_visible_in_tree(): continue
		geometries += 1
		var mesh: Mesh
		if geometry is MeshInstance3D: mesh = geometry.mesh
		elif geometry is MultiMeshInstance3D and geometry.multimesh != null: mesh = geometry.multimesh.mesh
		var path := str(chunk.get_path_to(geometry))
		if mesh != null:
			for surface in mesh.get_surface_count():
				var material: Material = geometry.material_override
				if material == null:
					material = geometry.get_active_material(surface) if geometry is MeshInstance3D else mesh.surface_get_material(surface)
				if material == null: without_material += 1
				add_material(material, "%s/surface%d" % [path, surface], entries)
		else:
			if geometry.material_override == null: without_material += 1
			add_material(geometry.material_override, path, entries)
		add_material(geometry.material_overlay, path + "/overlay", entries)
	var result := {"distinct_materials": entries.size(), "visible_geometry": geometries, "slots_without_explicit_material": without_material}
	for mode in MODES:
		var groups := ranked_groups(entries, mode)
		result[mode + "_group_count"] = groups.size()
		result[mode + "_top20"] = groups.slice(0, 20)
	var savings := 0
	for group: Dictionary in ranked_groups(entries, "exact"): savings += int(group.extra_instances)
	result["exact_extra_instances"] = savings
	return result

func run() -> void:
	var arguments := OS.get_cmdline_user_args()
	if not "--no-save" in arguments:
		push_error("Auditoria exige --no-save.")
		quit(1)
		return
	var keys: Array[Vector2i] = [Vector2i(3, 0), Vector2i(3, 1), Vector2i(0, 1), Vector2i(1, 1)]
	var output := ""
	var state := "day"
	for argument in arguments:
		if argument.begins_with("--chunks="):
			keys.clear()
			for pair in argument.trim_prefix("--chunks=").split(";"):
				var parts := pair.split(",")
				if parts.size() != 2:
					push_error("Trecho inválido: " + pair)
					quit(1)
					return
				keys.append(Vector2i(int(parts[0]), int(parts[1])))
		elif argument.begins_with("--output="): output = argument.trim_prefix("--output=")
		elif argument.begins_with("--state="): state = argument.trim_prefix("--state=")
	if not state in ["day", "night", "rain"]:
		push_error("Estado inválido; use day, night ou rain.")
		quit(1)
		return
	var region = REGION.build_region("harbor", Vector3.INF)
	region.initial_prewarm_only = true
	root.add_child(region)
	while not region.prepared: await process_frame
	var report := {"state": state, "material_dedupe_env": OS.get_environment("GETECO_MATERIAL_DEDUPE"), "notes": "Igualdade de propriedades não prova segurança para compartilhar materiais mutáveis. Rain aplica somente os controles de material; não simula clima nem certifica aparência. Materiais internos de Label3D não são expostos e não entram na contagem.", "chunks": {}}
	for key in keys:
		region._build_chunk(key)
		for frame in 4: await process_frame
		CITY.set_night(1.0 if state == "night" else 0.0)
		CITY.set_wetness(1.0 if state == "rain" else 0.0)
		resource_signatures.clear()
		var snapshot := inspect_chunk(region.chunks[key])
		report.chunks[str(key)] = snapshot
		print("AUDITORIA trecho=%s materiais=%d extras_idênticos=%d grupos_cor=%d grupos_rugosidade=%d grupos_escalar=%d" % [key, snapshot.distinct_materials, snapshot.exact_extra_instances, snapshot.color_group_count, snapshot.roughness_group_count, snapshot.scalar_group_count])
	if not output.is_empty():
		if not output.begins_with("res://evidence/"):
			push_error("A saída deve ficar em res://evidence/.")
			region.free()
			quit(1)
			return
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output.get_base_dir()))
		var file := FileAccess.open(output, FileAccess.WRITE)
		if file == null:
			push_error("Não foi possível escrever a auditoria.")
			region.free()
			quit(1)
			return
		file.store_string(JSON.stringify(report, "\t"))
	else: print(JSON.stringify(report))
	region.free()
	quit(0)
