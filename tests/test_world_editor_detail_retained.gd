extends SceneTree
const CANVAS := preload("res://addons/geteco_world_editor/WorldMapCanvas.gd")
var checks := 0
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool,label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)
func run() -> void:
	var canvas := CANVAS.new()
	root.add_child(canvas)
	canvas.size = Vector2(640,480)
	canvas.center = Vector2(20,20)
	canvas.zoom = 3.0
	var near := {"id":"piece/near","type":"piece","position":[0,0],"size":[20,20],"rotation":0,"parts":[[-3,-2,6,4,2,"778899",[[-3,-2],[3,-2],[0,2]]]]}
	canvas.objects[near.id] = near
	canvas.objects["piece/far"] = {"id":"piece/far","type":"piece","position":[2000,2000],"size":[10,10],"parts":[[1995,1995,10,10,1,"aa7755"]]}
	canvas.objects["ground/near"] = {"id":"ground/near","type":"ground","position":[40,40],"size":[5,5],"rotation":0,"surface":"earth"}
	for index in 5000:
		var id := "prop/far/%d" % index
		canvas.objects[id] = {"id":id,"type":"prop","position":[3000+index*3,3000],"size":[2,2],"rotation":0,"color":"889977"}
	canvas.rebuild_context()
	canvas.queue_redraw()
	for frame in 4: await process_frame
	check(not canvas.overview_active(),"Zoom 3 remains detailed rather than enabling schematic footprints")
	check(canvas.overview_record_count>0 and canvas.overview_layer!=null,"Detailed rendering records a retained CanvasItem")
	check(canvas.context_mesh!=null and canvas.context_mesh.surface_get_array_len(0)==3,"Detail retains the real triangular silhouette and culls the distant context")
	check(canvas.context_overview_mesh==null,"Detailed rendering does not substitute a bounding-box overview mesh")
	check(canvas._detail_rows().size()==1 and canvas._detail_rows()[0].id=="ground/near","The detail spatial cache excludes thousands of offscreen props")
	check(canvas.pick(canvas.screen(Vector2(0,-1)))==near.id,"Picking uses the exact native triangle")
	check(canvas.pick(canvas.screen(Vector2(8,8))).is_empty(),"Empty space in the native bounding rectangle remains unselectable")
	var recorded := canvas.overview_record_count
	var mesh_id := canvas.context_mesh.get_instance_id()
	canvas.center += Vector2(1,1)
	canvas.zoom = 3.02
	canvas.queue_redraw()
	for frame in 3: await process_frame
	check(canvas.overview_record_count==recorded,"Camera changes within the spatial cells reuse all retained detail commands")
	check(canvas.context_mesh.get_instance_id()==mesh_id,"Camera movement reuses the true detail mesh")
	canvas.center += Vector2(120,0)
	canvas.queue_redraw()
	for frame in 3: await process_frame
	check(canvas.overview_record_count==recorded and canvas.context_mesh.get_instance_id()==mesh_id,"A 120 m pan across cell edges stays inside retained real-geometry margins")
	canvas.center -= Vector2(120,0)
	canvas.queue_redraw()
	for frame in 3: await process_frame
	check(canvas.overview_record_count==recorded,"Returning across cell edges does not oscillate the detail cache")
	canvas.objects["ground/near"].position = [2000,2000]
	canvas.invalidate_overview()
	canvas.queue_redraw()
	for frame in 3: await process_frame
	check(canvas.overview_record_count>recorded and canvas._detail_rows().is_empty(),"Editing invalidates retained detail and its spatial object cache")
	canvas.center = Vector2(2000,2000)
	canvas.queue_redraw()
	for frame in 3: await process_frame
	check(canvas.context_mesh!=null and canvas.context_mesh.surface_get_array_len(0)==6,"Crossing cells reveals the distant object's real geometry")
	canvas.free()
	print("WORLD_EDITOR_DETAIL_RETAINED checks=",checks," failures=",failures)
	quit(0 if failures==0 else 1)
