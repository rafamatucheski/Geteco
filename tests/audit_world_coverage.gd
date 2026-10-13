extends SceneTree
## Auditoria: o que o editor 3D construiu e NÃO consegue selecionar. Uso:
## --script res://tests/audit_world_coverage.gd -- --no-save --area=harbor --radius=2 [--x= --z=]
const DATA := preload("res://world/editing/WorldEditData.gd")
const UNITS := preload("res://world/editing/WorldUnits.gd")
const HARBOR := preload("res://world/editing/EditableRegion.gd")
const DESERT := preload("res://world/editing/EditableDesertRegion.gd")
func _initialize() -> void: run.call_deferred()
func arg(name: String, fallback: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with(name + "="): return a.trim_prefix(name + "=")
	return fallback
func owner_id(node: Node) -> String:
	var n := node
	while n != null:
		if n.has_meta("world_edit_piece_id") or n.has_meta("editor_id"): return "ok"
		n = n.get_parent()
	return ""
func run() -> void:
	var area := arg("--area", "harbor")
	var radius := int(arg("--radius", "1"))
	var focus := Vector3(float(arg("--x", "45")), 0, float(arg("--z", "110")))
	Engine.set_meta("geteco_live_preview_build", true)
	Engine.set_meta("geteco_world_edit_document", DATA.empty_document())
	var region: Node3D = DESERT.build_region(area, focus) if area == "desert" else HARBOR.build_region(area, focus)
	root.add_child(region)
	var began := Time.get_ticks_msec()
	var cell_size := 96.0 if area == "desert" else 64.0
	var cell := Vector2i(floori(focus.x / cell_size), floori(focus.z / cell_size))
	region.retention_radius = radius + 1
	for x in range(-radius, radius + 1):
		for z in range(-radius, radius + 1):
			if area == "desert": region._ensure_chunk_surfaces(cell + Vector2i(x, z))
			else: region._ensure_chunk(cell + Vector2i(x, z))
	for i in 3000:
		await process_frame
		if region.is_streaming_idle(): break
	print("build ms=", Time.get_ticks_msec() - began, " chunks=", region.chunks.size())
	var missing := {}
	var total := 0
	var covered := 0
	for mesh in region.find_children("*", "MeshInstance3D", true, false):
		if not mesh.mesh or not mesh.is_visible_in_tree(): continue
		total += 1
		if owner_id(mesh) == "ok": covered += 1; continue
		var top := mesh
		while top.get_parent() != null and top.get_parent() != region and not str(top.get_parent().name).begins_with("Chunk_") and not str(top.get_parent().name).begins_with("Desert_"): top = top.get_parent()
		var key: String = str(top.name).rstrip("0123456789@") + " <" + mesh.mesh.get_class() + ">"
		missing[key] = int(missing.get(key, 0)) + 1
	var mm_missing := {}
	for mm in region.find_children("*", "MultiMeshInstance3D", true, false):
		if owner_id(mm) == "ok": continue
		var key: String = str(mm.name) + " x" + str(mm.multimesh.instance_count)
		mm_missing[key] = int(mm_missing.get(key, 0)) + 1
	print("meshes total=", total, " cobertas=", covered, " sem peça=", total - covered)
	var keys := missing.keys()
	keys.sort_custom(func(a, b): return missing[a] > missing[b])
	for k in keys.slice(0, 60): print("  SEM ", missing[k], "  ", k)
	var mkeys := mm_missing.keys()
	mkeys.sort_custom(func(a, b): return mm_missing[a] > mm_missing[b])
	for k in mkeys.slice(0, 30): print("  MM  ", mm_missing[k], "  ", k)
	quit()
