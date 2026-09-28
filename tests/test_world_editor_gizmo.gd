extends SceneTree
const UI := preload("res://addons/geteco_world_editor/WorldEditor.gd")
const DATA := preload("res://world/editing/WorldEditData.gd")
var checks := 0
var failures: Array[String] = []
var ui
func _initialize() -> void: run.call_deferred()
func check(ok: bool,label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)
func mouse(at: Vector2,pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = at
	event.pressed = pressed
	ui.canvas._gui_input(event)
func motion(at: Vector2,shift := false) -> void:
	var event := InputEventMouseMotion.new()
	event.position = at
	event.shift_pressed = shift
	ui.canvas._gui_input(event)
func drag(start: Vector2,end: Vector2,shift := false) -> void:
	mouse(start,true)
	motion(end,shift)
	mouse(end,false)
func run() -> void:
	root.size = Vector2i(1440,900)
	ui = UI.new()
	var folder := "res://evidence/world-editor-20260925/"
	ui.edits_path = folder+"gizmo_"+str(OS.get_process_id())+".json"
	ui.draft_path = folder+"gizmo_draft_"+str(OS.get_process_id())+".json"
	root.add_child(ui)
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await process_frame
	check(not ui.canvas.rotation_enabled,"Rotation ring starts disabled")
	ui.rotation_toggle.button_pressed = true
	ui.rotation_toggle.pressed.emit()
	check(ui.canvas.rotation_enabled,"Rotation ring can be enabled explicitly")
	var row := DATA.new_entity("prop",Vector2(53.25,112.125))
	ui._commit(row)
	var id: String = row.id
	var at: Vector2 = ui.canvas.screen(DATA.point(row.position))
	check(ui.canvas.gizmo_hit(at+Vector2(40,0)) == "x","X arrow can be selected")
	check(ui.canvas.gizmo_hit(at+Vector2(0,40)) == "z","Z arrow can be selected")
	drag(at+Vector2(40,0),at+Vector2(56,12))
	var moved: Dictionary = ui.document.regions.harbor[id]
	check(DATA.point(moved.position) == Vector2(57,112.125),"X arrow only changes X; preserves fractional Z")
	at = ui.canvas.screen(DATA.point(moved.position))
	drag(at+Vector2(0,40),at+Vector2(-16,52))
	check(DATA.point(ui.document.regions.harbor[id].position) == Vector2(57,115),"Z arrow only changes Z")
	at = ui.canvas.screen(DATA.point(ui.document.regions.harbor[id].position))
	var previous_history: int = ui.history.size()
	mouse(at+Vector2(-82,0),true)
	motion(at+Vector2(-58,-58))
	motion(at+Vector2(0,-82))
	check(is_equal_approx(ui.canvas.objects[id].rotation,-90),"Rotation previews correct Y axis sign")
	check(ui.history.size() == previous_history,"Preview does not create undo entries")
	mouse(at+Vector2(0,-82),false)
	check(ui.history.size() == previous_history+1,"Drag commits one undo transaction")
	ui.undo()
	check(is_zero_approx(ui.document.regions.harbor[id].rotation),"Undo restores angle")
	ui.redo()
	check(is_equal_approx(ui.document.regions.harbor[id].rotation,-90),"Redo restores rotation")
	ui._set_value("rotation",0)
	drag(at+Vector2(-82,0),at+Vector2(-82,0).rotated(deg_to_rad(22)),true)
	check(is_equal_approx(ui.document.regions.harbor[id].rotation,-15),"Shift snaps rotation to 15 degrees")
	var before: Dictionary = ui.document.duplicate(true)
	mouse(at+Vector2(40,0),true)
	motion(at+Vector2(60,0))
	var cancel := InputEventKey.new()
	cancel.pressed = true
	cancel.keycode = KEY_ESCAPE
	ui.canvas._gui_input(cancel)
	mouse(at+Vector2(60,0),false)
	check(ui.document == before and ui.canvas.objects[id].position == before.regions.harbor[id].position,"Escape restores preview without modifying document")
	ui.canvas.grid = 0
	mouse(at+Vector2(40,0),true)
	motion(at+Vector2(43,0))
	ui.asset_search.grab_focus()
	check(not ui.canvas.dragging and ui.document == before,"Changing focus cancels unfinished transform")
	var road := DATA.new_entity("road",Vector2(0,180))
	road.points = [[-8.2,179.4],[0.7,181.25],[8.4,182.6]]
	ui._commit(road)
	var center: Vector2 = ui.canvas.pivot(road)
	at = ui.canvas.screen(center)
	ui.canvas.grid = 1
	# Click the arrow tip, away from the road vertex which now wins at overlap.
	drag(at+Vector2(60,0),at+Vector2(72,9))
	var road_after: Dictionary = ui.document.regions.harbor[road.id]
	check((DATA.point(road_after.points[2])-DATA.point(road_after.points[0])).is_equal_approx(DATA.point(road.points[2])-DATA.point(road.points[0])),"Road-axis movement preserves every bend")
	check(is_equal_approx(road_after.points[0][1],road.points[0][1]),"Road X axis preserves Z")
	center = ui.canvas.pivot(road_after)
	at = ui.canvas.screen(center)
	var span := DATA.point(road_after.points[2])-DATA.point(road_after.points[0])
	drag(at+Vector2(-82,0),at+Vector2(0,82))
	road_after = ui.document.regions.harbor[road.id]
	check(ui.canvas.pivot(road_after).is_equal_approx(center),"Road rotates around its center")
	check((DATA.point(road_after.points[2])-DATA.point(road_after.points[0])).is_equal_approx(span.rotated(-PI/2)),"Road rotation transforms actual path points")
	ui._select("piece/neco/Office")
	var piece: Dictionary = ui.canvas.objects[ui.canvas.selected_id].duplicate(true)
	at = ui.canvas.screen(DATA.point(piece.position))
	drag(at+Vector2(-82,0),at+Vector2(0,82))
	check(is_equal_approx(ui.document.regions.harbor[piece.id].rotation,90),"Piece ring rotation persists")
	check(not ui.document.regions.harbor[piece.id].has("parts"),"Piece transform remains sparse")
	check(ui.canvas.objects[piece.id].parts != piece.parts,"Piece geometry updates after rotation")
	ui._select("building/Garage")
	at = ui.canvas.screen(DATA.point(ui.canvas.objects["building/Garage"].position))
	check(ui.canvas.gizmo_hit(at+Vector2(40,0)).is_empty(),"Protected locations do not expose transform handles")
	ui._select(id)
	at = ui.canvas.screen(DATA.point(ui.canvas.objects[id].position))
	ui.canvas.grid = 0
	mouse(at+Vector2(40,0),true)
	motion(at+Vector2(48,0))
	check(ui.save(),"Saving during transform commits it")
	var saved: Dictionary = DATA.read_document(ui.edits_path).document
	check(saved.regions.harbor[id].position == ui.canvas.objects[id].position and saved.regions.harbor[id].rotation == ui.canvas.objects[id].rotation,"Position and rotation survive disk reload")
	ui._select(piece.id)
	ui.canvas.center = DATA.point(piece.position)
	ui.canvas.zoom = 13
	ui.canvas.queue_redraw()
	if DisplayServer.get_name() != "headless":
		for child in root.find_children("*","CanvasLayer",true,false): child.hide()
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(folder+"gizmo-editor.png")
	ui.free()
	await process_frame
	print("WORLD_GIZMO checks=",checks," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
