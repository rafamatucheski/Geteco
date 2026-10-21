extends SceneTree
const CANVAS := preload("res://addons/geteco_world_editor/WorldMapCanvas.gd")
var checks := 0
var failures := 0

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func run() -> void:
	var canvas := CANVAS.new()
	root.add_child(canvas)
	canvas.size = Vector2(1000,700)
	canvas.center = Vector2.ZERO
	canvas.zoom = .08
	var parts: Array = []
	for i in 5000: parts.append([0,0,1,1,float(i%3),"859591"])
	var row := {"id":"piece/dense","type":"piece","position":[0,0],"size":[100,100],"rotation":0.0,"parts":parts}
	canvas.objects[row.id] = row
	canvas.rebuild_context()
	check(canvas.overview_active(), "Global map zoom selects schematic footprints")
	var overview := canvas._overview_mesh()
	check(overview != null and overview.surface_get_array_len(0) == 6, "Thousands of detail parts become one compact footprint in overview")
	check(canvas.context_triangles.is_empty(), "Overview does not triangulate the full detail map")
	var cached_id := overview.get_instance_id()
	canvas.center = Vector2(20,10)
	canvas.zoom = .1
	check(canvas._overview_mesh().get_instance_id() == cached_id, "Panning and overview zoom reuse the same world mesh")
	check(canvas.pick(canvas.screen(Vector2(.5,.5))) == row.id, "Overview retains precise object picking")
	check(canvas.pick(canvas.screen(Vector2(30,30))).is_empty(), "A schematic box does not invent a hit outside the actual geometry")
	canvas.queue_redraw()
	await process_frame
	await process_frame
	await process_frame
	var recorded := canvas.overview_record_count
	check(recorded > 0 and canvas.overview_layer != null,"Global scene records retained CanvasItem commands")
	canvas.center += Vector2(30,10)
	canvas.zoom = .12
	canvas.queue_redraw()
	await process_frame
	await process_frame
	check(canvas.overview_record_count == recorded,"Camera movement changes only retained CanvasItem transform")
	canvas.objects[row.id].position = [10,0]
	canvas.update_context([row.id])
	check(canvas._overview_mesh().get_instance_id() != cached_id, "Editing invalidates only the overview geometry cache")
	canvas.center = Vector2.ZERO
	canvas.zoom = 4
	check(not canvas.overview_active(), "Zooming in restores detailed map rendering")
	canvas._rebuild_context_mesh(canvas._visible_parts())
	check(canvas.context_mesh != null and canvas.context_mesh.surface_get_array_len(0) == parts.size()*6, "All original detail triangles remain available after leaving overview")
	canvas.free()
	print("WORLD_EDITOR_OVERVIEW_LOD checks=",checks," failures=",failures)
	quit(0 if failures == 0 else 1)
