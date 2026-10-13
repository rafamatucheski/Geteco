extends SceneTree
## Geração offline do piloto; só grava nos diretórios pertencentes à P6.
const FACTORY := preload("res://world/urban_detail/UrbanBuildingFactory.gd")
const CATALOG := preload("res://assets/buildings/baked/BuildingBakeCatalog.gd")
const BAKED := preload("res://assets/buildings/baked/BakedCommercialBuilding.gd")
const EDIT_DATA := preload("res://world/editing/WorldEditData.gd")

func _initialize() -> void: run.call_deferred()

static func records() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var document: Dictionary = EDIT_DATA.read_document().document
	var changes: Dictionary = document.get("regions", {}).get("harbor", {})
	var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://world/regions/OriginalWorldData.json"))
	for raw: Dictionary in source.harbor_buildings:
		if raw.kind != "office" or raw.id == "NorthFrontage4": continue
		result.append(raw.duplicate(true))
		var edit: Dictionary = changes.get("building/" + str(raw.id), {})
		if edit.is_empty() or edit.get("deleted", false) or edit.get("model", "") != "office": continue
		# Os mesmos campos da adaptação WorldEditRuntime, sem escrever o documento.
		var row := raw.duplicate(true)
		row.merge({"position": EDIT_DATA.xyz(edit.position), "size": EDIT_DATA.point(edit.size),
			"kind": edit.model, "color": edit.color, "height_override": float(edit.height),
			"original_name": row.get("original_name", "")}, true)
		result.append(row)
	return result

static func counts(node: Node) -> Dictionary:
	return {"meshes": node.find_children("*", "MeshInstance3D", true, false).size(),
		"bodies": node.find_children("*", "StaticBody3D", true, false).size(),
		"boxes": node.find_children("*", "CollisionShape3D", true, false).size()}

static func assign_owners(node: Node, scene_root: Node) -> void:
	for child in node.get_children():
		child.owner = scene_root
		assign_owners(child, scene_root)

static func merge_frames(building: UrbanBuildingBase) -> void:
	var groups := {}
	for node in building.visuals_root.get_children():
		if not node is MeshInstance3D: continue
		var mesh := node as MeshInstance3D
		var label := str(mesh.name)
		# Nomes repetidos recebem IDs automáticos do Godot. O material e a posição
		# distinguem os caixilhos superiores das folhas da entrada e dos HVAC.
		var frame := mesh.material_override == UrbanMaterials.metal_dark() and mesh.position.y >= 4.4 and mesh.position.y < building.height and (mesh.mesh as BoxMesh).size.z <= .08
		if not (frame or label.begins_with("SpandrelBand")): continue
		var cell := floori(mesh.position.x / 8.0)
		var material := mesh.get_active_material(0)
		var signature := "%d|%.3f|%d|%d|%s|%s" % [cell, mesh.position.y, material.get_instance_id(), mesh.cast_shadow, mesh.get_meta("baked_detail", false), mesh.get_meta("baked_batch_shadow", false)]
		if not groups.has(signature): groups[signature] = []
		groups[signature].append(mesh)
	var serial := 0
	for entries: Array in groups.values():
		if entries.size() < 2: continue
		var source: MeshInstance3D = entries[0]
		var tool := SurfaceTool.new()
		tool.begin(Mesh.PRIMITIVE_TRIANGLES)
		for mesh: MeshInstance3D in entries: tool.append_from(mesh.mesh, 0, mesh.transform)
		tool.index()
		var batch := MeshInstance3D.new()
		batch.name = "BakedFacadeFrames%d" % serial
		serial += 1
		batch.mesh = tool.commit()
		batch.material_override = source.get_active_material(0)
		batch.cast_shadow = source.cast_shadow
		if source.get_meta("baked_detail", false): batch.set_meta("baked_detail", true)
		if source.get_meta("baked_batch_shadow", false): batch.set_meta("baked_batch_shadow", true)
		building.visuals_root.add_child(batch)
		for mesh: MeshInstance3D in entries: mesh.free()

static func simplify_collision(building: UrbanBuildingBase) -> void:
	var compound := StaticBody3D.new()
	compound.name = "CommercialSolids"
	compound.collision_layer = 1
	compound.collision_mask = 0
	for body in building.collision_root.get_children():
		for shape in body.get_children():
			shape.transform = body.transform * shape.transform
			body.remove_child(shape)
			compound.add_child(shape)
		body.free()
	building.collision_root.add_child(compound)

static func add_lod(building: UrbanBuildingBase) -> void:
	var body := building.visuals_root.get_node("CommercialBody") as MeshInstance3D
	var lod := MeshInstance3D.new()
	lod.name = "BakedFacadeLOD"
	lod.mesh = body.mesh
	lod.material_override = body.material_override
	lod.transform = body.transform
	lod.visibility_range_begin = 50.0
	lod.visibility_range_begin_margin = 2.0
	lod.set_meta("baked_lod", true)
	# O proxy conserva a altura do corpo. Ático e tampas mantêm a silhueta autorada,
	# sem inventar uma laje alta nem novos sólidos nas varreduras de acesso.
	for mesh: MeshInstance3D in building.visuals_root.find_children("*", "MeshInstance3D", true, false):
		if mesh.name in [&"Penthouse", &"PenthouseCap"]: continue
		var label := str(mesh.name).to_lower()
		if mesh.has_meta("baked_window_key") or label.contains("door") or label.contains("handle") or label.contains("glass") or label.contains("sign") or mesh.get_parent().name == &"ArchitecturalSign": continue
		mesh.visibility_range_end = 50.0
		mesh.visibility_range_end_margin = 2.0
	building.visuals_root.add_child(lod)

func run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args():
		push_error("A ferramenta exige --no-save para isolar o save do jogador.")
		quit(2)
		return
	FACTORY.baked_enabled = false
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CATALOG.OUTPUT))
	var variants := {}
	for record in records():
		# A classificação vem da própria P5, sem repetir suas regras nem salvar
		# seu estado de ambiente dentro da cena assada.
		CATALOG.set_detail_enabled(false)
		var building := FACTORY.build_building(record) as UrbanBuildingBase
		root.add_child(building)
		CATALOG.set_detail_enabled(true)
		var detailed := FACTORY.build_building(record) as UrbanBuildingBase
		root.add_child(detailed)
		var canonical_meshes := building.visuals_root.find_children("*", "MeshInstance3D", true, false)
		var detail_meshes := detailed.visuals_root.find_children("*", "MeshInstance3D", true, false)
		for index in canonical_meshes.size():
			var source_mesh := canonical_meshes[index] as MeshInstance3D
			var bounds := source_mesh.transform * source_mesh.get_aabb()
			if FACTORY.BUILDING_BATCH._small_detail(source_mesh, bounds.size): source_mesh.set_meta("baked_batch_shadow", true)
			if detail_meshes[index].visibility_range_end > 0.0:
				canonical_meshes[index].set_meta("baked_detail", true)
		detailed.free()
		CATALOG.set_detail_enabled(false)
		var data: Dictionary = building.get_meta("_urban_data")
		var before := counts(building)
		var floors := maxi(1, int((building.height - 4.4) / 2.2))
		var columns := maxi(2, int((building.building_size.x - 2.4) / 2.4))
		var windows: Array[MeshInstance3D] = []
		for node in building.visuals_root.get_children():
			if node is MeshInstance3D and node.material_override in [UrbanMaterials.glass_window(), UrbanMaterials.glass_window_lit(true), UrbanMaterials.glass_window_lit(false)]: windows.append(node)
		for f in floors:
			for c in columns: windows[f * columns + c].set_meta("baked_window_key", "f%d_c%d" % [f, c])
		merge_frames(building)
		simplify_collision(building)
		add_lod(building)
		var after := counts(building)
		# Dados e orientação vêm da factory a cada instanciação, nunca da posição do bake.
		root.remove_child(building)
		building.position = Vector3.ZERO
		building.visuals_root.rotation = Vector3.ZERO
		building.collision_root.rotation = Vector3.ZERO
		building.remove_meta("_urban_data")
		building.remove_meta("_urban_finalized")
		building.set_script(BAKED)
		building.set_meta("baked_commercial", true)
		assign_owners(building, building)
		var packed := PackedScene.new()
		var status := packed.pack(building)
		var signature := CATALOG.key(data)
		var path := CATALOG.OUTPUT + "/" + str(data.id) + "_" + signature.substr(0, 12) + ".scn"
		if status == OK: status = ResourceSaver.save(packed, path, ResourceSaver.FLAG_COMPRESS)
		if status != OK:
			push_error("Falha ao salvar prédio assado: " + path)
			building.free()
			quit(1)
			return
		variants[signature] = {"id": data.id, "scene": path, "before": before, "after": after}
		print("P6_ASSADO ", data.id, " antes=", before, " depois=", after)
		building.free()
	var manifest := {"source_stamp": CATALOG.source_stamp(), "variants": variants}
	var resource := Resource.new()
	resource.set_meta("building_manifest", manifest)
	var manifest_status := ResourceSaver.save(resource, CATALOG.OUTPUT + "/manifest.tres")
	if manifest_status != OK:
		push_error("Falha ao salvar catálogo assado.")
		quit(1)
		return
	var file := FileAccess.open(CATALOG.OUTPUT + "/manifest.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(manifest, "\t"))
	file.close()
	print("P6_GERACAO variantes=", variants.size())
	quit()
