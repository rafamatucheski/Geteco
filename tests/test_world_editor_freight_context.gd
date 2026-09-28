extends SceneTree
const DATA := preload("res://world/editing/WorldEditData.gd")
const SESSION := preload("res://addons/geteco_world_editor/WorldSessionContext.gd")
const UI := preload("res://addons/geteco_world_editor/WorldEditor.gd")
const CANVAS := preload("res://addons/geteco_world_editor/WorldMapCanvas.gd")
const COMPANY := SESSION.PREFIX+"vertice"
const FOREST := SESSION.PREFIX+"vertice_woodland"
var failures: Array[String] = []
var checks := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool,label: String) -> void:
	checks+=1
	print("EDITOR_FREIGHT ","PASS " if ok else "FAIL ",label)
	if not ok: failures.append(label)
func run() -> void:
	var disk_hash := DATA.disk_hash()
	var supplement := SESSION.read()
	check(supplement.get("version")==SESSION.VERSION and supplement.get("context") is Dictionary,"Shipped session geometry is available without regenerating the world")
	if not failures.is_empty(): quit(1); return
	check(supplement.context.has(COMPANY) and supplement.context.has(FOREST),"Company and rural woodland have distinct searchable contexts")
	var stale := {"harbor":{"objects":{"road/vertice_rural_access":{"id":"road/vertice_rural_access","type":"road","points":[[0,0],[1,1]],"width":2}},"context":{"context/harbor/existing":{"id":"context/harbor/existing"}},"land":[]}}
	SESSION.upgrade(stale,supplement)
	var road: Dictionary = stale.harbor.objects["road/vertice_rural_access"]
	check(DATA.point(road.points[0]).distance_to(Vector2(-55,137.5))<.01 and DATA.point(road.points[-1]).distance_to(Vector2(-340,-2))<.01 and is_equal_approx(road.width,9),"Old cached catalog receives the actual safe rural road and gate endpoint")
	check(stale.harbor.land.any(func(rect): return Rect2(float(rect[0])/16,float(rect[1])/16,float(rect[2])/16,float(rect[3])/16).has_point(Vector2(-420,150))),"Old land cache includes the complete western extension")
	check(stale.harbor.context.has("context/harbor/existing"),"Upgrade preserves unrelated authored contexts")
	var once := JSON.stringify(stale)
	SESSION.upgrade(stale,supplement)
	check(JSON.stringify(stale)==once,"Repeated loads do not duplicate session context")
	for id in [COMPANY,FOREST]:
		var row: Dictionary = supplement.context[id]
		check(row.locked and row.type=="context" and not row.parts.is_empty(),id+" has visible protected geometry")
	var company: Dictionary = supplement.context[COMPANY]
	var envelope := Rect2(DATA.point(company.position)-DATA.point(company.size)*.5,DATA.point(company.size))
	check(envelope.has_point(Vector2(-340,-80)) and envelope.has_point(Vector2(-340,-2)),"Actual company geometry includes warehouse and truck gate")
	check(supplement.context[FOREST].parts.any(func(part): return part.size()>6 and part[6].size()>4),"Woodland exports canopy silhouettes instead of every mesh triangle")
	check(supplement.context[FOREST].parts.filter(func(part): return part[4]>6 and part[2]>2 and part[5]!="000000").size()>300,"Forest preserves actual tall colored canopies even from a headless export")
	# Independent extent regression: old framing only considered the first road
	# point and centers, ignoring background land, road ends and rotated corners.
	var canvas := CANVAS.new()
	canvas.land=[[-16000,-8000,1600,1600]]
	canvas.terrain=[[600,700,64,64,"778877"]]
	canvas.objects={"road/test":{"id":"road/test","type":"road","points":[[0,0],[-500,300]],"width":8},"building/test":{"id":"building/test","type":"building","position":[300,300],"size":[100,200],"rotation":45}}
	var bounds := canvas.world_bounds()
	check(bounds.position.x<=-1000 and bounds.position.y<=-500 and bounds.end.x>=664 and bounds.end.y>=764,"Framing includes all terrain edges, not only object centers")
	canvas.land=[]
	canvas.terrain=[]
	bounds=canvas.world_bounds()
	check(bounds.position.x<=-504 and bounds.end.x>405 and bounds.end.y>405,"Framing includes final road point, road width and rotated building corners")
	canvas.free()
	var view := SubViewport.new()
	view.size=Vector2i(1440,900)
	root.add_child(view)
	var ui := UI.new()
	ui.edits_path="res://.godot/world_editor_freight_fixture_unused.json"
	ui.draft_path="res://.godot/world_editor_freight_fixture_draft_unused.json"
	view.add_child(ui)
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for i in 8: await process_frame
	check(ui.canvas.objects.has(COMPANY) and ui.canvas.objects.has(FOREST) and ui.canvas.objects.has("road/vertice_rural_access"),"Real 2D editor shows company, forest and road on initial load")
	ui.canvas._rebuild_context_mesh(ui.canvas._visible_parts())
	check(ui.canvas.context_mesh!=null and ui.canvas.context_mesh.get_surface_count()==1,"Static context uses one cached colored triangle surface")
	check(ui.location_ids.has(COMPANY) and ui.location_ids.has(FOREST),"Company and woodland appear in Go to location")
	check(ui.find_children("FreightOutskirts","",true,false).is_empty() and ui.find_children("Vertice","",true,false).is_empty(),"Editor uses baked context and never constructs gameplay scenes on load/redraw")
	ui._fit_world()
	for p in [Vector2(-430,-160),Vector2(-430,158),Vector2(-340,-2)]:
		check(Rect2(Vector2.ZERO,ui.canvas.size).grow(.5).has_point(ui.canvas.screen(p)),"Fit world includes expansion edge "+str(p))
	ui._go_location(ui.location_ids.find(COMPANY)+1)
	check(ui.canvas.selected_id==COMPANY and ui.canvas.center.distance_to(DATA.point(company.position))<.01,"Go to Vértice focuses and selects its actual footprint")
	check(ui.canvas.objects[COMPANY].locked,"Runtime-operated company is not offered as a freely movable unrelated building")
	var change: Dictionary = ui.canvas.objects["road/vertice_rural_access"].duplicate(true)
	change.width=10.0
	ui.document.regions.harbor[change.id]=change
	ui._refresh()
	check(is_equal_approx(ui.canvas.objects[change.id].width,10.0),"User road edits remain authoritative over refreshed canonical defaults")
	check(DATA.disk_hash()==disk_hash,"Opening and testing the editor never changes the saved map")
	view.free()
	for i in 3: await process_frame
	print("EDITOR_FREIGHT_RESULT checks=",checks," failures=",failures)
	quit(0 if failures.is_empty() else 1)
