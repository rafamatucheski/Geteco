extends Node
## Finalização transitória por chunk: o acabamento ainda precisa das caixas originais.
const OPTIMIZER := preload("res://assets/regions/source/prototypes/harbor_art_pack/PortMeshOptimizer.gd")
const TARGET_SCRIPTS := [
	"res://world/urban_detail/UrbanCommercialBuilding.gd",
	"res://world/urban_detail/UrbanIndustrialBuilding.gd",
	"res://world/urban_detail/UrbanServiceBuilding.gd",
	"res://assets/regions/source/world/harbor/hospital/HarborHospitalModel3D.gd",
	"res://assets/regions/source/world/harbor/residences/ResidenceExterior3D.gd",
	"res://world/places/ResidenceParking.gd",
]
static var enabled := OS.get_environment("GETECO_BUILDING_BATCH") != "0"
const PENDING_META := &"harbor_building_batch_pending"
const FINISHED_META := &"harbor_building_batch_finished"

static func schedule(building: Node3D) -> void:
	if not enabled or not _is_target(building): return
	var chunk := building.get_parent()
	if chunk == null or chunk.get_parent() == null: return
	var region := chunk.get_parent()
	# O jogo usa EditableRegion; subclasses mantêm o mesmo marco de acabamento.
	var region_script := region.get_script() as Script
	while region_script != null and region_script.resource_path != "res://world/regions/NativeRegion.gd":
		region_script = region_script.get_base_script()
	if region_script == null: return
	if region.get("region_id") != "harbor" or chunk.has_meta(PENDING_META): return
	chunk.set_meta(PENDING_META, true)
	var worker := load("res://world/urban_detail/HarborBuildingBatch.gd").new() as Node
	worker.name = "BuildingBatchFinalizer"
	chunk.add_child(worker)

func _process(_delta: float) -> void:
	var chunk := get_parent() as Node3D
	# Este marco só existe depois de telhados, texturas, noite e corte do túnel.
	if not chunk.has_meta("vegetation_ready_frame"): return
	finish_chunk(chunk)
	set_process(false)
	queue_free()

static func finish_chunk(chunk: Node3D) -> void:
	if not enabled or chunk.has_meta(FINISHED_META) or not chunk.has_meta("vegetation_ready_frame"): return
	chunk.set_meta(FINISHED_META, true)
	for child in chunk.get_children():
		if child is Node3D and _is_target(child): _optimize_building(child)

static func _is_target(node: Node) -> bool:
	return node.get_script() != null and node.get_script().resource_path in TARGET_SCRIPTS

static func _optimize_building(building: Node3D) -> void:
	var access := building.get_node_or_null("BuildingAccess")
	# Uma visita pode preparar a fachada durante o streaming fatiado. Nesse caso
	# o adaptador já guarda referências individuais e elas precisam continuar vivas.
	if access != null and "_prepared" in access and access.get("_prepared"): return
	var moving: Array[Node] = []
	# Folhas autoradas e pivôs de serviço não têm script próprio, mas são animados.
	for property in ["door_leaves", "public_leaves", "police_door_visuals"]:
		if property in building:
			for leaf in building.get(property): moving.append(leaf)
	if "fire_door_visual" in building and is_instance_valid(building.get("fire_door_visual")):
		moving.append(building.get("fire_door_visual"))
	_collect_branch(building, building, moving)

static func _collect_branch(node: Node3D, building: Node3D, moving: Array[Node]) -> void:
	var groups := {}
	for child in node.get_children():
		if child in moving: continue
		if child.get_script() != null:
			if child is Node3D and _is_target(child): _optimize_building(child)
			continue
		if child is MeshInstance3D:
			var mesh := child as MeshInstance3D
			if mesh.mesh == null: continue
			var bounds := mesh.transform * mesh.get_aabb()
			if _small_detail(mesh, bounds.size): mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			if not _eligible(mesh): continue
			# Não unir lados distantes: o corte do túnel seleciona cada lote pelo AABB.
			var center := bounds.get_center()
			var cell := Vector3i(floori(center.x / 8.0), floori(center.y / 4.0), floori(center.z / 8.0))
			var thin_axis := bounds.size.min_axis_index()
			var key := "%s|%d|%d|%d|%d|%s|%d" % [cell, mesh.get_active_material(0).get_instance_id(), mesh.layers, mesh.cast_shadow, mesh.gi_mode, mesh.extra_cull_margin, thin_axis]
			if not groups.has(key): groups[key] = []
			groups[key].append(mesh)
		elif child is Label3D:
			child.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		elif child is Node3D and not child is CollisionObject3D and child.get_groups().is_empty():
			_collect_branch(child, building, moving)
	for entries in groups.values():
		if entries.size() > 1: _merge(node, entries)

static func _eligible(mesh: MeshInstance3D) -> bool:
	if mesh.mesh == null or mesh.mesh.get_surface_count() != 1 or not mesh.visible: return false
	if mesh.get_child_count() > 0 or mesh.get_meta("interior_solid_id", "") != "": return false
	if mesh.material_overlay != null or mesh.skin != null or mesh.transparency != 0.0: return false
	if mesh.visibility_range_begin != 0.0 or mesh.visibility_range_end != 0.0: return false
	if not mesh.get_groups().is_empty() or not mesh.get_meta_list().is_empty(): return false
	var label := String(mesh.name).to_lower()
	for protected in ["door", "shutter", "glass", "sign", "nameplate", "lamp", "light", "neon"]:
		if label.contains(protected): return false
	var material := mesh.get_active_material(0) as StandardMaterial3D
	if material == null or material.emission_enabled or material.get_meta("city_window", false): return false
	if material.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED: return false
	# Volumes, lajes e paredes continuam caixas independentes para acabamento e acesso.
	var size := (mesh.transform * mesh.get_aabb()).size
	if size.y >= 2.5 or size.x * size.y * size.z >= 3.0: return false
	if size.x >= 3.0 and size.z >= 3.0: return false
	return true

static func _small_detail(mesh: MeshInstance3D, size: Vector3) -> bool:
	var label := String(mesh.name).to_lower()
	# Nem nomes sugestivos autorizam tirar sombra de um volume arquitetônico grande.
	if size.x * size.y * size.z >= 3.0 or (size.x >= 3.0 and size.z >= 3.0): return false
	if label.contains("door") or label.contains("shutter"): return false
	if String(mesh.get_parent().name).to_lower().contains("hvac"): return true
	for detail in ["frame", "mullion", "transom", "trim", "seam", "rail", "bar", "hvac", "chiller", "grille", "louver", "fin", "handle", "hinge", "sign", "nameplate"]:
		if label.contains(detail): return true
	# O hospital usa nomes automáticos; detalhes finos são reconhecidos pela espessura.
	return minf(size.x, minf(size.y, size.z)) <= 0.12 and size.x * size.y * size.z < 0.25

static func _merge(parent: Node3D, entries: Array) -> void:
	var source := entries[0] as MeshInstance3D
	var staging := Node3D.new()
	# Cópias visuais isolam o otimizador de colisão, scripts e nós animados.
	for entry: MeshInstance3D in entries:
		var copy := MeshInstance3D.new()
		copy.mesh = entry.mesh
		copy.material_override = entry.get_active_material(0)
		copy.transform = entry.transform
		staging.add_child(copy)
	OPTIMIZER.optimize_hierarchy(staging, false)
	var batches := staging.get_node("BatchedStaticGeometry") as Node3D
	staging.remove_child(batches)
	batches.name = "BuildingStaticBatch"
	parent.add_child(batches)
	for batch: MeshInstance3D in batches.get_children():
		batch.layers = source.layers
		batch.cast_shadow = source.cast_shadow
		batch.gi_mode = source.gi_mode
		batch.extra_cull_margin = source.extra_cull_margin
	staging.free()
	for entry: MeshInstance3D in entries:
		parent.remove_child(entry)
		entry.free()
