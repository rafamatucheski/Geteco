extends SceneTree
## Inventário estrutural dos chunks completos; não mede FPS nem draw calls da GPU.
## GETECO_BUILDING_BATCH=0 permite comparar a mesma árvore sem trocar arquivos.
const REGION := preload("res://world/regions/NativeRegion.gd")
const TARGETS := ["HarborHospitalModel3D", "UrbanCommercialBuilding", "UrbanIndustrialBuilding", "ResidenceExterior3D", "ResidenceParking", "UrbanServiceBuilding"]
const SECTIONS := {"oeste": [Vector2i(1, 1), Vector2i(2, 1)], "leste": [Vector2i(5, 1), Vector2i(6, 1)]}
const FOLDER := "res://evidence/harbor-building-batch-20261013"
const SOURCES := [
	"world/regions/NativeRegion.gd", "world/regions/OriginalWorldData.json",
	"world/city_look/CityChunkDressing.gd", "world/city_look/CityLookMaterials.gd",
	"world/urban_detail/UrbanBuildingFactory.gd", "world/urban_detail/HarborBuildingBatch.gd",
	"world/urban_detail/UrbanCommercialBuilding.gd", "world/urban_detail/UrbanIndustrialBuilding.gd",
	"world/urban_detail/UrbanServiceBuilding.gd", "world/places/ResidenceParking.gd",
	"assets/regions/source/world/harbor/hospital/HarborHospitalModel3D.gd",
	"assets/regions/source/world/harbor/residences/ResidenceExterior3D.gd",
	"assets/regions/source/prototypes/harbor_art_pack/PortMeshOptimizer.gd",
	"world/urban_detail/HarborProp3D.gd", "world/urban_detail/HarborManholeExterior3D.gd",
	"world/urban_detail/HarborUrbanSurface3D.gd", "world/urban_detail/HarborRoadGeometry3D.gd",
	"world/urban_detail/GroundCut.gd",
]

func _initialize() -> void:
	run.call_deferred()

func counters() -> Dictionary:
	return {"geometry_instances": 0, "mesh_instances": 0, "surfaces": 0, "shadow_casters": 0}

func script_owner(node: Node, chunk: Node) -> String:
	var current := node
	while current != null and current != chunk:
		if current.get_script() != null:
			return String(current.get_script().resource_path).get_file().get_basename()
		current = current.get_parent()
	return "sem_script"

func add_counts(target: Dictionary, source: Dictionary) -> void:
	for key in target:
		target[key] += source[key]

func scan(chunk: Node3D, owners: Dictionary) -> void:
	for found in chunk.find_children("*", "GeometryInstance3D", true, false):
		var geometry := found as GeometryInstance3D
		if not geometry.is_visible_in_tree() or geometry.is_queued_for_deletion(): continue
		var owner_name := script_owner(geometry, chunk)
		if not owners.has(owner_name): owners[owner_name] = counters()
		var counts := counters()
		counts.geometry_instances = 1
		counts.shadow_casters = int(geometry.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
		if geometry is MeshInstance3D and geometry.mesh != null:
			counts.mesh_instances = 1
			counts.surfaces = geometry.mesh.get_surface_count()
		elif geometry is MultiMeshInstance3D and geometry.multimesh != null and geometry.multimesh.mesh != null:
			# Superfícies submetidas pelo MultiMesh, sem multiplicar pelas instâncias.
			counts.surfaces = geometry.multimesh.mesh.get_surface_count()
		add_counts(owners[owner_name], counts)

func run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args():
		push_error("A contagem exige --no-save.")
		quit(1)
		return
	var label := "antes" if OS.get_environment("GETECO_BUILDING_BATCH") == "0" else "depois"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--label="): label = argument.trim_prefix("--label=")
	if label not in ["antes", "depois"]:
		push_error("Rótulo deve ser antes ou depois.")
		quit(1)
		return
	var region = REGION.build_region("harbor", Vector3.INF)
	region.initial_prewarm_only = true
	root.add_child(region)
	while not region.prepared: await process_frame
	var report := {
		"label": label,
		"building_batch_enabled": OS.get_environment("GETECO_BUILDING_BATCH") != "0",
		"engine": Engine.get_version_info().string,
		"scope": "Chunks completos de 64 m: oeste x64-192/z64-128; leste x320-448/z64-128. Visibilidade na árvore, sem frustum/oclusão. Dono = script ancestral mais próximo, incluindo o próprio nó. Não mede FPS nem draw calls da GPU.",
		"surface_scope": "Superfícies de MeshInstance3D e MultiMeshInstance3D; Label3D/Decal contam em geometria mas não têm superfícies Mesh consultáveis.",
		"source_sha256": {},
		"sections": {}
	}
	for source in SOURCES:
		report.source_sha256[source] = FileAccess.get_sha256("res://" + source)
	for section in SECTIONS:
		var owners := {}
		for key in SECTIONS[section]:
			region._build_chunk(key)
			var chunk: Node3D = region.chunks[key]
			# Permite descarte das fontes via queue_free e finalizações adiadas.
			await process_frame
			await process_frame
			scan(chunk, owners)
			region.chunks.erase(key)
			region._detach_cached_records(chunk)
			chunk.free()
		var total := counters()
		var buildings := counters()
		for owner_name in owners:
			add_counts(total, owners[owner_name])
			if owner_name in TARGETS: add_counts(buildings, owners[owner_name])
		report.sections[section] = {"owners": owners, "total": total, "target_buildings": buildings}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(FOLDER))
	var file := FileAccess.open(FOLDER.path_join(label + ".json"), FileAccess.WRITE)
	if file == null:
		push_error("Não foi possível gravar a contagem.")
		region.free()
		quit(1)
		return
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("CONTAGEM_PREDIOS_PORTO ", JSON.stringify(report.sections))
	region.free()
	quit(0)
