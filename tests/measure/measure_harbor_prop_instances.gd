extends SceneTree
## Contagem estrutural por chunk; não mede FPS nem chamadas reais da GPU.

const REGION := preload("res://world/regions/NativeRegion.gd")
const OUTPUT := "res://evidence/harbor-prop-instancing-20261013"
const BUILD_SOURCES := [
	"world/regions/NativeRegion.gd", "world/city_look/CityChunkDressing.gd",
	"world/urban_detail/HarborProp3D.gd", "world/urban_detail/HarborManholeExterior3D.gd",
	"world/harbor_route_detail/HarborRouteProps.gd", "world/urban_detail/HarborPropInstancing.gd",
	"world/urban_detail/HarborRoadGeometry3D.gd", "world/urban_detail/HarborUrbanSurface3D.gd",
	"world/urban_detail/GroundCut.gd", "world/editing/world_edits.json",
	"world/urban_detail/UrbanBuildingFactory.gd", "world/urban_detail/HarborBuildingBatch.gd",
]
const SECTIONS := {
	"oeste": [Vector2i(1, 1), Vector2i(2, 1)],
	"leste": [Vector2i(5, 1), Vector2i(6, 1)],
}

func _initialize() -> void:
	run.call_deferred()

func source_label(node: Node, chunk: Node) -> String:
	var current := node
	while current != chunk and current != null:
		if current.get_script() != null:
			return String(current.get_script().resource_path).get_file().get_basename()
		current = current.get_parent()
	return "Outros"

func empty_counts() -> Dictionary:
	return {"visible_geometry": 0, "shadow_geometry": 0, "mesh_nodes": 0,
		"multimesh_nodes": 0, "multimesh_instances": 0, "other_geometry": 0}

func count_geometry(counts: Dictionary, node: GeometryInstance3D) -> void:
	counts.visible_geometry += 1
	if node.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
		counts.shadow_geometry += 1
	if node is MeshInstance3D:
		counts.mesh_nodes += 1
	elif node is MultiMeshInstance3D:
		counts.multimesh_nodes += 1
		var multi: MultiMesh = node.multimesh
		if multi != null:
			counts.multimesh_instances += multi.instance_count if multi.visible_instance_count < 0 else multi.visible_instance_count
	else:
		counts.other_geometry += 1

func run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args():
		push_error("A contagem exige --no-save.")
		quit(1)
		return
	var label := "depois"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--label="):
			label = argument.trim_prefix("--label=")
	if label not in ["antes", "depois"]:
		push_error("Use --label=antes ou --label=depois.")
		quit(1)
		return
	var region = REGION.build_region("harbor", Vector3.INF)
	region.initial_prewarm_only = true
	root.add_child(region)
	while not region.prepared:
		await process_frame
	var report := {
		"label": label,
		"prop_instancing_enabled": OS.get_environment("GETECO_PROP_INSTANCING") != "0",
		"engine": Engine.get_version_info().string,
		"scope": "GeometryInstance3D com is_visible_in_tree nos chunks oeste x64-192 z64-128 e leste x320-448 z64-128; pertencimento pelo chunk, sem frustum ou oclusão. Sombras contam cast_shadow diferente de OFF. Não mede FPS ou draw calls da GPU.",
		"sections": {},
		"source_sha256": {},
	}
	for path in BUILD_SOURCES:
		var resource_path: String = "res://" + path
		report.source_sha256[path] = FileAccess.get_sha256(resource_path) if FileAccess.file_exists(resource_path) else "ausente"
	for section in SECTIONS:
		var counts := empty_counts()
		var sources := {}
		var lights := 0
		var collisions := 0
		for key in SECTIONS[section]:
			region._build_chunk(key)
			var chunk: Node3D = region.chunks[key]
			for found in chunk.find_children("*", "GeometryInstance3D", true, false):
				if not found.is_visible_in_tree():
					continue
				count_geometry(counts, found)
				var source := source_label(found, chunk)
				if not sources.has(source):
					sources[source] = empty_counts()
				count_geometry(sources[source], found)
			lights += chunk.find_children("*", "Light3D", true, false).size()
			collisions += chunk.find_children("*", "CollisionShape3D", true, false).size()
			region.chunks.erase(key)
			region._detach_cached_records(chunk)
			chunk.free()
		counts["sources"] = sources
		counts["lights"] = lights
		counts["collision_shapes"] = collisions
		report.sections[section] = counts
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	var file := FileAccess.open(OUTPUT + "/" + label + ".json", FileAccess.WRITE)
	if file == null:
		push_error("Não foi possível gravar a contagem.")
		region.free()
		quit(1)
		return
	file.store_string(JSON.stringify(report, "\t", true))
	file.close()
	print("Contagem de geometria Harbor: ", JSON.stringify(report))
	region.free()
	quit(0)
