extends SceneTree
const UI := preload("res://addons/geteco_world_editor/WorldEditor.gd")
const DATA := preload("res://world/editing/WorldEditData.gd")
const GRAPH := preload("res://gameplay/NativeTrafficRoutes.gd")
var failures := 0
var checks := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)
func run() -> void:
	root.size = Vector2i(1280,720)
	var ui := UI.new()
	ui.edits_path = "res://.godot/connections_test_%d.json" % OS.get_process_id()
	ui.draft_path = ui.edits_path+".draft"
	root.add_child(ui)
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await process_frame
	ui.catalog = {"harbor":{"objects":{},"context":{}},"mountain":{"objects":{},"context":{}}}
	ui.document = DATA.empty_document()
	ui._refresh()
	var main := DATA.new_entity("road",Vector2.ZERO)
	main.points = [[-40,0],[40,7]]
	ui._commit(main)
	var branch := DATA.new_entity("road",Vector2.ZERO)
	branch.points = [[0,-30],[0,-10]]
	ui._commit(branch)
	ui.canvas.selected_point = 1
	var start := ui.canvas.screen(Vector2(0,-10))
	ui.canvas._start_drag(start,"")
	ui.canvas._update_drag(ui.canvas.screen(Vector2(0,2)),false)
	ui.canvas.finish_drag()
	var endpoint := DATA.point(ui.document.regions.harbor[branch.id].points[-1])
	check(endpoint.distance_to(Geometry2D.get_closest_point_to_segment(endpoint,Vector2(-40,0),Vector2(40,7))) < .0001,"Diagonal road snaps exactly despite grid")
	var graph := GRAPH.new()
	var roads: Array = []
	for row in ui.document.regions.harbor.values():
		var points := PackedVector3Array()
		for p in row.points: points.append(Vector3(p[0],0,p[1]))
		roads.append({"id":row.id,"width":row.width,"points":points})
	graph.configure(roads)
	var junction := false
	for edges in graph.edges.values():
		if edges.size() == 3: junction = true
	check(junction,"Snapped T creates actual traffic junction")
	ui.undo()
	check(ui.document.regions.harbor[branch.id].points[-1] == [0,-10],"Undo restores loose end")
	ui.redo()
	check(DATA.point(ui.document.regions.harbor[branch.id].points[-1]).is_equal_approx(endpoint),"Redo restores connection")
	ui._select(branch.id)
	ui.canvas.selected_point = 0
	ui._continue_road()
	ui._place("continue_road",Vector2(0,-50))
	check(DATA.point(ui.document.regions.harbor[branch.id].points[0]) == Vector2(0,-50),"Continue first end preserves road identity")
	ui.canvas.selected_point = 0
	ui._create_road_return()
	var loop: Dictionary = ui.document.regions.harbor[ui.canvas.selected_id]
	check(loop.id != branch.id and loop.points.size() == 5,"Return preserves original street and adds connecting loop")
	check(DATA.point(loop.points[0]) == Vector2(0,-50),"Return joins selected endpoint exactly")
	var points := PackedVector3Array()
	for p in loop.points: points.append(Vector3(p[0],0,p[1]))
	var approach := PackedVector3Array()
	for p in ui.document.regions.harbor[branch.id].points: approach.append(Vector3(p[0],0,p[1]))
	graph.configure([{"id":loop.id,"width":loop.width,"points":points},{"id":branch.id,"width":branch.width,"points":approach}])
	var route := graph.route_near(Vector3(0,0,-48))
	check(route != null and not route.get_meta("traffic_open",true),"Return generates a closed traffic route")
	ui._layout_option(4)
	check(not ui.canvas.road_snap_enabled,"Snapping can be disabled")
	var narrow := branch.duplicate(true)
	narrow.width = 3
	check(ui.canvas.road_connection(endpoint,narrow,6).is_empty(),"Narrow street cannot claim traffic connection")
	narrow.width = 7.5
	narrow.pathway = true
	check(ui.canvas.road_connection(endpoint,narrow,6).is_empty(),"Pedestrian paths cannot claim traffic connection")
	ui._select(branch.id)
	ui.canvas.selected_point = 0
	ui._continue_road()
	var cancel := InputEventKey.new()
	cancel.pressed = true
	cancel.keycode = KEY_ESCAPE
	var before := ui.document.duplicate(true)
	ui.canvas._gui_input(cancel)
	check(ui.canvas.armed.is_empty() and ui.document == before,"Escape cancels continuation without editing")
	ui._select(loop.id)
	check(not ui.canvas.rotation_enabled,"Rotation starts disabled")
	ui.rotation_toggle.button_pressed = true
	ui.rotation_toggle.pressed.emit()
	var ring := ui.canvas.screen(ui.canvas.pivot(loop))+Vector2(-82,0)
	check(ui.canvas.gizmo_hit(ring) == "rotate","Enabled ring receives input")
	ui.canvas._start_drag(ring,"rotate")
	ui.canvas._update_drag(ui.canvas.screen(ui.canvas.pivot(loop))+Vector2(0,82),false)
	ui.canvas.finish_drag()
	check(ui.document.regions.harbor[loop.id].points != loop.points,"Enabled ring actually rotates street")
	ui.undo()
	ui.rotation_toggle.button_pressed = false
	ui.rotation_toggle.pressed.emit()
	check(ui.canvas.gizmo_hit(ring) == "","Disabled ring does not capture clicks")
	check(ui.save(),"Connections save successfully")
	var loaded: Dictionary = DATA.read_document(ui.edits_path).document
	check(loaded.regions.harbor.size() == 3,"Saved streets reload")
	for id in ui.document.regions.harbor:
		var saved: Dictionary = loaded.regions.harbor[id]
		var original: Dictionary = ui.document.regions.harbor[id]
		check(saved.points.size() == original.points.size(),"Saved point count survives reload")
		for i in original.points.size(): check(DATA.point(saved.points[i]).is_equal_approx(DATA.point(original.points[i])),"Saved coordinates survive JSON numeric conversion")
	if DisplayServer.get_name() != "headless":
		for child in root.find_children("*","CanvasLayer",true,false): child.hide()
		ui._select(branch.id)
		ui.canvas.selected_point = 0
		ui._select(branch.id)
		ui.canvas.center = Vector2(0,-25)
		ui.canvas.zoom = 6
		ui.canvas.queue_redraw()
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://evidence/world-editor-connections.png")
	print("CONNECTIONS: %d checks, %d failures" % [checks,failures])
	ui.queue_free()
	await process_frame
	quit(1 if failures else 0)
