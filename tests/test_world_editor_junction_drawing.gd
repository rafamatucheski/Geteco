extends SceneTree
const DRAWING := preload("res://addons/geteco_world_editor/WorldRoadDrawing.gd")
const CANVAS := preload("res://addons/geteco_world_editor/WorldMapCanvas.gd")
const GRAPH := preload("res://gameplay/NativeTrafficRoutes.gd")
var failures := 0
var checks := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool,label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)
func run() -> void:
	var rows: Array = [
		{"id":"main","points":[[-70,0],[70,0]],"width":8.0,"surface":"asphalt"},
		{"id":"right","points":[[-40,0],[-40,35]],"width":8.0,"surface":"asphalt"},
		{"id":"cross","points":[[0,-35],[0,35]],"width":8.0,"surface":"asphalt"},
		{"id":"angle","points":[[40,0],[65,-30]],"width":6.0,"surface":"asphalt"}]
	var original := rows.duplicate(true)
	var drawing := DRAWING.new()
	drawing.configure(rows)
	check(drawing.junctions.size() == 3,"One continuous avenue supports three distinct junctions")
	for j in drawing.junctions:
		check(j.arms.size() == (4 if j.at == Vector2.ZERO else 3),"T and X retain every branch")
		for mark in drawing.markings:
			for i in range(mark.points.size()-1):
				check(Geometry2D.get_closest_point_to_segment(j.at,mark.points[i],mark.points[i+1]).distance_to(j.at) > 5,"No centre marking crosses intersection core")
	for surface in drawing.surfaces:
		for layer in ["border","fill"]:
			for polygon in surface[layer]: check(not Geometry2D.triangulate_polygon(polygon).is_empty(),"Junction polygon triangulates: "+str(polygon))
	var revision := drawing.revision
	drawing.configure(rows)
	check(drawing.revision == revision,"Unchanged network reuses geometry")
	check(rows == original,"Presentation preserves all authored coordinates and road IDs")
	var graph := GRAPH.new()
	var roads: Array[Dictionary] = []
	for row in rows:
		var points := PackedVector3Array()
		for p in row.points: points.append(Vector3(p[0],0,p[1]))
		roads.append({"id":row.id,"points":points,"width":row.width})
	graph.configure(roads)
	check(graph.route_between(Vector3(-70,0,0),Vector3(70,0,0)) != null,"Traffic can drive straight across all junctions")
	for target in [Vector3(-40,0,35),Vector3(0,0,35),Vector3(65,0,-30)]:
		check(graph.route_between(Vector3(-70,0,0),target) != null,"Traffic can turn onto each branch")
	var runtime := preload("res://world/urban_detail/HarborRoadGeometry3D.gd").new()
	runtime.configure(roads)
	check(runtime._junctions.size() == 3,"Runtime also discovers all three junctions")
	for j in drawing.junctions: check(runtime._marking_hits_junction(j.at),"Game already clears markings at junctions")
	var canvas := CANVAS.new()
	root.size = Vector2i(1100,680)
	root.add_child(canvas)
	canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas.zoom = 7
	canvas.center = Vector2.ZERO
	for row in rows:
		row.type = "road"
		canvas.objects[row.id] = row
	canvas.queue_redraw()
	if DisplayServer.get_name() != "headless":
		for child in root.find_children("*","CanvasLayer",true,false): child.hide()
		await process_frame
		await RenderingServer.frame_post_draw
		var capture := root.get_texture().get_image()
		for at in [Vector2(-40,0),Vector2(-40,4),Vector2(0,0),Vector2(4,0),Vector2(40,0)]:
			var pixel := canvas.screen(at)*Vector2(capture.get_size())/root.get_visible_rect().size
			var color := capture.get_pixel(roundi(pixel.x),roundi(pixel.y))
			check(color.is_equal_approx(Color("3b4852")),"Intersection is uninterrupted asphalt at "+str(at))
		capture.save_png("res://evidence/world-editor-junctions.png")
	canvas.free()
	drawing.configure([{"id":"loop","points":[[-20,-20],[20,-20],[20,20],[-20,20],[-20,-20]],"width":8.0,"surface":"asphalt"}])
	var island_clear := true
	for surface in drawing.surfaces:
		for polygon in surface.fill: island_clear = island_clear and not Geometry2D.is_point_in_polygon(Vector2.ZERO,polygon)
	check(island_clear,"Closed street preserves its empty central island")
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://addons/geteco_world_editor/base_catalog.json")).regions
	var catalog_roads: Array = []
	for area in catalog.values():
		for row in area.objects.values():
			if row.type == "road": catalog_roads.append({"id":row.id,"points":row.points,"width":row.width,"surface":row.get("surface","asphalt")})
	drawing.configure(catalog_roads)
	for surface in drawing.surfaces:
		for layer in ["border","fill"]:
			for polygon in surface[layer]: check(not Geometry2D.triangulate_polygon(polygon).is_empty(),"Catalog polygon triangulates: "+str(polygon))
	print("JUNCTION_DRAWING checks=",checks," failures=",failures)
	quit(1 if failures else 0)
