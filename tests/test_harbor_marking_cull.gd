extends SceneTree
## Faixa pintada por célula (24/10): com o corte por caixa (marking_cull_enabled) cada célula do porto
## precisa sair com os MESMOS tracinhos de antes (posição, rumo, comprimento, cor), e mais barata.
## Peças soltas (dash_batch_enabled=false) para comparar sem MultiMesh, que o headless não guarda.
const REGION := preload("res://world/regions/NativeRegion.gd")
const ROAD := preload("res://world/urban_detail/HarborRoadGeometry3D.gd")
var failures := 0
var checks := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; print("FAIL ", label)
func marks(geometry: Object, rect: Rect2, cull: bool) -> Array:
	ROAD.marking_cull_enabled = cull
	var parent := Node3D.new()
	geometry._build_markings(parent, rect)
	var out: Array = []
	for node in parent.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		out.append("%.4f,%.4f,%.4f|%.4f|%.4f|%s" % [mesh.position.x, mesh.position.y, mesh.position.z, mesh.rotation.y, (mesh.mesh as PlaneMesh).size.y, mesh.material_override.albedo_color.to_html()])
	parent.free()
	out.sort()
	return out
func run() -> void:
	var region = REGION.build_region("harbor", Vector3.INF)
	region.initial_prewarm_only = true
	root.add_child(region)
	while not region.prepared: await process_frame
	var geometry: Object = region.harbor_road_geometry
	var batch_was: bool = ROAD.dash_batch_enabled
	ROAD.dash_batch_enabled = false
	var keys: Dictionary = {}
	for key in region.records: keys[key] = true
	var old_usec := 0
	var new_usec := 0
	var total := 0
	for key: Vector2i in keys:
		var rect := Rect2(key.x * REGION.CELL, key.y * REGION.CELL, REGION.CELL, REGION.CELL)
		var began := Time.get_ticks_usec()
		var before := marks(geometry, rect, false)
		old_usec += Time.get_ticks_usec() - began
		began = Time.get_ticks_usec()
		var after := marks(geometry, rect, true)
		new_usec += Time.get_ticks_usec() - began
		total += before.size()
		check(before == after, "cell %s same dashes (%d x %d)" % [key, before.size(), after.size()])
	ROAD.dash_batch_enabled = batch_was
	ROAD.marking_cull_enabled = true
	check(total > 500, "harbor has real lane paint: %d dashes" % total)
	print("HARBOR_MARKING_CULL cells=%d dashes=%d old_ms=%.1f new_ms=%.1f checks=%d failures=%d" % [keys.size(), total, old_usec / 1000.0, new_usec / 1000.0, checks, failures])
	region.queue_free()
	quit(1 if failures else 0)
